import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

private final class MediaArtworkBox: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

private func makeMediaItemArtwork(from image: UIImage) -> MPMediaItemArtwork? {
    let size = image.size
    guard size.width.isFinite,
          size.height.isFinite,
          size.width > 0,
          size.height > 0 else { return nil }

    // MediaPlayer invokes this handler on its own background queue. Keeping the
    // closure outside PlaybackCoordinator prevents it from inheriting @MainActor.
    // UIImage is immutable here and retained only for read-only artwork requests.
    let box = MediaArtworkBox(image: image)
    let requestHandler: @Sendable (CGSize) -> UIImage = { _ in box.image }
    return MPMediaItemArtwork(boundsSize: size, requestHandler: requestHandler)
}

struct PlayableTrack: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artistNames: [String]
    let albumTitle: String?
    let albumArtist: String?
    let releaseID: String?
    let durationSeconds: Int
    let artworkName: String
    let artworkURL: URL?
    let fileURL: URL?

    init(
        id: String,
        title: String,
        artist: String,
        artistNames: [String]? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        releaseID: String? = nil,
        durationSeconds: Int,
        artworkName: String,
        artworkURL: URL? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistNames = artistNames ?? [artist]
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.releaseID = releaseID
        self.durationSeconds = durationSeconds
        self.artworkName = artworkName
        self.artworkURL = artworkURL
        self.fileURL = fileURL
    }

    static let empty = PlayableTrack(
        id: "empty",
        title: String(localized: "player.no_track"),
        artist: String(localized: "player.add_music_hint"),
        durationSeconds: 0,
        artworkName: "MistyLake"
    )
}

@MainActor
final class PlaybackCoordinator: ObservableObject {
    enum RepeatMode: String, CaseIterable, Codable, Sendable {
        case off
        case all
        case one

        var systemImage: String { self == .one ? "repeat.1" : "repeat" }
    }

    @Published private(set) var currentTrack: PlayableTrack = .empty
    @Published private(set) var queue: [PlayableTrack] = []
    @Published private(set) var playbackHistory: [PlayableTrack] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var playbackError: String?
    @Published private(set) var queueContext: QueueSourceContext = .adHoc
    @Published var isShuffleEnabled = false {
        didSet { persistState() }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { persistState(); updateNowPlaying() }
    }

    private let player = AVPlayer()
    private lazy var nowPlayingSession: MPNowPlayingSession = {
        let session = MPNowPlayingSession(players: [self.player])
        session.automaticallyPublishesNowPlayingInfo = false
        return session
    }()
    private var currentIndex: Int?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var shouldResumeAfterInterruption = false
    private var isRestoring = true
    private let queueRepository: any PlaybackQueueRepository
    private let statisticsRepository: any ListeningStatisticsRepository
    private var persistenceTask: Task<Void, Never>?
    private var listeningSessionID: UUID?
    private var listenedSeconds = 0.0
    private var unflushedListenedSeconds = 0.0
    private var lastObservedPosition = 0.0
    private var qualifiedRecorded = false

    init(
        queueRepository: any PlaybackQueueRepository = GRDBPlaybackQueueRepository(),
        statisticsRepository: any ListeningStatisticsRepository = GRDBListeningStatisticsRepository(),
        restoresQueue: Bool = true
    ) {
        self.queueRepository = queueRepository
        self.statisticsRepository = statisticsRepository
        configureAudioSession()
        observePlayer()
        configureRemoteCommands()
        UserDefaults.standard.removeObject(forKey: "playback.queue.v1")
        if restoresQueue {
            Task { [weak self] in
                await self?.restoreState()
                self?.isRestoring = false
            }
        } else {
            isRestoring = false
        }
    }

    var progress: Double {
        guard currentTrack.durationSeconds > 0 else { return 0 }
        return min(max(elapsedSeconds / Double(currentTrack.durationSeconds), 0), 1)
    }

    var hasCurrentTrack: Bool { currentTrack != .empty && currentTrack.fileURL != nil }

    var upcomingTracks: [PlayableTrack] {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return queue }
        let next = queue.index(after: currentIndex)
        return next < queue.endIndex ? Array(queue[next...]) : []
    }

    func replaceLibrary(_ tracks: [PlayableTrack]) {
        let localTracks = tracks.filter { $0.fileURL != nil }
        guard !localTracks.isEmpty else {
            let removedCurrentTrack = currentTrack.fileURL != nil
            queue.removeAll { $0.fileURL != nil }
            playbackHistory.removeAll { $0.fileURL != nil }
            if removedCurrentTrack {
                if queue.isEmpty {
                    clear()
                } else {
                    selectTrack(at: 0, autoplay: false, recordHistory: false)
                }
            } else {
                currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
                persistState()
            }
            return
        }

        let currentID = currentTrack.id
        let nonLocal = queue.filter { $0.fileURL == nil }
        queue = nonLocal + localTracks
        let localIDs = Set(localTracks.map(\.id))
        playbackHistory.removeAll { $0.fileURL != nil && !localIDs.contains($0.id) }
        if let index = queue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
            currentTrack = queue[index]
        } else {
            let fallbackIndex = min(currentIndex ?? 0, queue.count - 1)
            selectTrack(at: fallbackIndex, autoplay: false, recordHistory: false)
            return
        }
        persistState()
    }

    func play(_ track: PlayableTrack) {
        playbackError = nil
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            selectTrack(at: index, autoplay: true)
        } else {
            queue.append(track)
            selectTrack(at: queue.count - 1, autoplay: true)
        }
    }

    func play(
        _ tracks: [PlayableTrack],
        startingAt index: Int = 0,
        context: QueueSourceContext = .adHoc
    ) {
        guard tracks.indices.contains(index) else { return }
        playbackError = nil
        finishListeningSession(as: .skip)
        queueContext = context
        playbackHistory.removeAll()
        if isShuffleEnabled {
            let selected = tracks[index]
            let remaining = tracks.enumerated()
                .filter { $0.offset != index }
                .map(\.element)
            queue = [selected] + shuffledEnsuringChange(remaining)
            selectTrack(at: 0, autoplay: true)
        } else {
            queue = tracks
            selectTrack(at: index, autoplay: true)
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentTrack.fileURL != nil else {
            playbackError = String(localized: "player.file_unavailable")
            return
        }
        do {
            let isResumingSession = listeningSessionID != nil
            if !isResumingSession { startListeningSession() }
            try AVAudioSession.sharedInstance().setActive(true)
            nowPlayingSession.becomeActiveIfPossible(completion: nil)
            player.play()
            isPlaying = true
            lastObservedPosition = elapsedSeconds
            if isResumingSession { emitListeningEvent(.resumed) }
            updateNowPlaying()
        } catch {
            playbackError = error.localizedDescription
        }
    }

    func pause() {
        pause(recording: .paused)
    }

    private func pause(recording kind: ListeningEventKind) {
        guard isPlaying else {
            player.pause()
            return
        }
        accountPlayback(to: elapsedSeconds)
        player.pause()
        isPlaying = false
        emitListeningEvent(kind)
        updateNowPlaying()
        persistState()
    }

    func seek(to seconds: Double) {
        seek(to: seconds, eventKind: .seek)
    }

    private func seek(to seconds: Double, eventKind: ListeningEventKind) {
        let duration = Double(max(currentTrack.durationSeconds, 0))
        let target = min(max(seconds, 0), duration)
        let previous = elapsedSeconds
        accountPlayback(to: previous)
        emitListeningEvent(eventKind, from: previous, to: target)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        elapsedSeconds = target
        lastObservedPosition = target
        updateNowPlaying()
    }

    func seek(toProgress progress: Double) {
        seek(to: Double(currentTrack.durationSeconds) * min(max(progress, 0), 1))
    }

    func skip(by interval: Double) {
        seek(to: elapsedSeconds + interval, eventKind: .seek)
    }

    func next() {
        advance(automatic: false)
    }

    func previous() {
        if elapsedSeconds > 3 {
            seek(to: 0)
            return
        }
        guard !playbackHistory.isEmpty else {
            seek(to: 0)
            return
        }
        let previous = playbackHistory.removeLast()
        guard let index = queue.firstIndex(where: { $0.id == previous.id }) else { return }
        selectTrack(at: index, autoplay: true, recordHistory: false)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        guard isShuffleEnabled, let currentIndex, queue.indices.contains(currentIndex) else { return }
        let playedAndCurrent = Array(queue[...currentIndex])
        let future = currentIndex + 1 < queue.count ? Array(queue[(currentIndex + 1)...]) : []
        let shuffledFuture = shuffledEnsuringChange(future)
        queue = playedAndCurrent + shuffledFuture
        persistState()
        updateNowPlaying()
    }

    private func shuffledEnsuringChange(_ tracks: [PlayableTrack]) -> [PlayableTrack] {
        guard tracks.count > 1 else { return tracks }
        var shuffled = tracks.shuffled()
        if shuffled == tracks {
            shuffled.append(shuffled.removeFirst())
        }
        return shuffled
    }

    func playNext(_ track: PlayableTrack) {
        guard let currentIndex else { play(track); return }
        queue.removeAll { $0.id == track.id }
        queue.insert(track, at: min(currentIndex + 1, queue.count))
        persistState()
    }

    func addToQueue(_ track: PlayableTrack) {
        if !queue.contains(where: { $0.id == track.id }) { queue.append(track) }
        persistState()
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let currentIndex else { return }
        let start = currentIndex + 1
        guard start < queue.count else { return }
        var upcoming = Array(queue[start...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(start..., with: upcoming)
        persistState()
    }

    func removeUpcoming(atOffsets offsets: IndexSet) {
        guard let currentIndex else { return }
        let start = currentIndex + 1
        let absoluteOffsets = IndexSet(offsets.map { start + $0 })
        queue.remove(atOffsets: absoluteOffsets)
        persistState()
        updateNowPlaying()
    }

    func clearUpcoming() {
        guard let currentIndex, currentIndex + 1 < queue.count else { return }
        queue.removeSubrange((currentIndex + 1)...)
        persistState()
        updateNowPlaying()
    }

    func clearPlaybackError() { playbackError = nil }

    private func clear() {
        finishListeningSession(as: .stopped)
        player.replaceCurrentItem(with: nil)
        queue = []
        playbackHistory = []
        currentIndex = nil
        currentTrack = .empty
        elapsedSeconds = 0
        isPlaying = false
        persistState()
        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = nil
    }

    private func selectTrack(at index: Int, autoplay: Bool, recordHistory: Bool = true) {
        guard queue.indices.contains(index) else { return }
        finishListeningSession(as: .skip)
        if recordHistory, currentTrack != .empty, currentTrack.id != queue[index].id {
            playbackHistory.append(currentTrack)
        }
        currentIndex = index
        currentTrack = queue[index]
        elapsedSeconds = 0

        guard let url = currentTrack.fileURL else {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            playbackError = String(localized: "player.file_unavailable")
            persistState()
            updateNowPlaying()
            return
        }

        startListeningSession()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if autoplay {
            resume()
        } else {
            isPlaying = false
        }
        persistState()
        updateNowPlaying()
    }

    private func advance(automatic: Bool) {
        guard let currentIndex, !queue.isEmpty else { return }
        if automatic {
            let completedPosition = Double(max(currentTrack.durationSeconds, 0))
            accountPlayback(to: completedPosition)
            elapsedSeconds = completedPosition
        }
        if automatic, repeatMode == .one {
            finishListeningSession(as: .completed)
            startListeningSession()
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard finished else { return }
                Task { @MainActor in
                    self?.elapsedSeconds = 0
                    self?.resume()
                }
            }
            return
        }

        let nextIndex = currentIndex + 1
        if automatic { finishListeningSession(as: .completed) }
        if queue.indices.contains(nextIndex) {
            selectTrack(at: nextIndex, autoplay: true)
        } else if repeatMode == .all {
            selectTrack(at: 0, autoplay: true)
        } else {
            pause(recording: automatic ? .completed : .paused)
            seek(to: Double(currentTrack.durationSeconds), eventKind: .seek)
        }
    }

    private func startListeningSession() {
        guard currentTrack != .empty, currentTrack.fileURL != nil else { return }
        listeningSessionID = UUID()
        listenedSeconds = 0
        unflushedListenedSeconds = 0
        lastObservedPosition = elapsedSeconds
        qualifiedRecorded = false
        emitListeningEvent(.started)
    }

    private func accountPlayback(to position: Double) {
        guard listeningSessionID != nil, isPlaying else {
            lastObservedPosition = position
            return
        }
        let delta = position - lastObservedPosition
        if delta >= 0, delta <= 2.0 {
            listenedSeconds += delta
            unflushedListenedSeconds += delta
        }
        lastObservedPosition = position

        let duration = Double(max(currentTrack.durationSeconds, 1))
        let threshold = max(1, min(30, duration * 0.5))
        if !qualifiedRecorded, listenedSeconds >= threshold {
            qualifiedRecorded = true
            emitListeningEvent(.qualified)
        }
    }

    private func emitListeningEvent(
        _ kind: ListeningEventKind,
        from: Double? = nil,
        to: Double? = nil
    ) {
        guard let sessionID = listeningSessionID, currentTrack != .empty else { return }
        let event = ListeningEventDraft(
            sessionID: sessionID,
            trackID: currentTrack.id,
            kind: kind,
            position: elapsedSeconds,
            fromPosition: from,
            toPosition: to,
            listenedSeconds: unflushedListenedSeconds,
            context: queueContext
        )
        unflushedListenedSeconds = 0
        let repository = statisticsRepository
        Task { try? await repository.record(event) }
    }

    private func finishListeningSession(as kind: ListeningEventKind) {
        guard listeningSessionID != nil else { return }
        accountPlayback(to: elapsedSeconds)
        emitListeningEvent(kind)
        listeningSessionID = nil
        listenedSeconds = 0
        unflushedListenedSeconds = 0
        qualifiedRecorded = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds.isFinite ? time.seconds : 0
            Task { @MainActor in
                guard let self else { return }
                self.accountPlayback(to: max(seconds, 0))
                self.elapsedSeconds = max(seconds, 0)
                self.updateNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance(automatic: true) }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                ?? String(localized: "player.playback_failed")
            Task { @MainActor in
                self?.playbackError = message
                self?.finishListeningSession(as: .stopped)
                self?.advance(automatic: false)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            Task { @MainActor in self?.handleRouteChange(reasonRaw: reasonRaw) }
        }
    }

    private func handleInterruption(typeRaw: UInt, optionsRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .began {
            shouldResumeAfterInterruption = isPlaying
            pause(recording: .interruption)
        } else if shouldResumeAfterInterruption,
                  AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
            resume()
        }
    }

    private func handleRouteChange(reasonRaw: UInt) {
        guard AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable else { return }
        pause(recording: .interruption)
    }

    private func configureRemoteCommands() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = nowPlayingSession.remoteCommandCenter
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let positionTime = event.positionTime
            Task { @MainActor in self?.seek(to: positionTime) }
            return .success
        }
        center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let repeatModeName: String
            switch event.repeatType {
            case .off: repeatModeName = "off"
            case .one: repeatModeName = "one"
            case .all: repeatModeName = "all"
            @unknown default: repeatModeName = "off"
            }
            Task { @MainActor in
                switch repeatModeName {
                case "one": self?.repeatMode = .one
                case "all": self?.repeatMode = .all
                default: self?.repeatMode = .off
                }
            }
            return .success
        }
        center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let shouldShuffle = event.shuffleType != .off
            Task { @MainActor in
                if self?.isShuffleEnabled != shouldShuffle { self?.toggleShuffle() }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard currentTrack != .empty else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyPlaybackDuration: currentTrack.durationSeconds,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex ?? 0
        ]
        if let artworkURL = currentTrack.artworkURL,
           let image = UIImage(contentsOfFile: artworkURL.path),
           let artwork = makeMediaItemArtwork(from: image) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = info

        let center = nowPlayingSession.remoteCommandCenter
        center.playCommand.isEnabled = !isPlaying && currentTrack.fileURL != nil
        center.pauseCommand.isEnabled = isPlaying
        center.togglePlayPauseCommand.isEnabled = currentTrack.fileURL != nil
        center.nextTrackCommand.isEnabled = !upcomingTracks.isEmpty || repeatMode == .all
        center.previousTrackCommand.isEnabled = currentTrack.fileURL != nil
        center.changePlaybackPositionCommand.isEnabled = currentTrack.durationSeconds > 0
        center.changeRepeatModeCommand.currentRepeatType = switch repeatMode {
        case .off: .off
        case .all: .all
        case .one: .one
        }
        center.changeShuffleModeCommand.currentShuffleType = isShuffleEnabled ? .items : .off
    }

    private func persistState() {
        guard !isRestoring else { return }
        persistenceTask?.cancel()
        let repository = queueRepository
        let history = playbackHistory
        let current = currentTrack == .empty ? nil : currentTrack
        let upcoming = upcomingTracks
        let elapsed = elapsedSeconds
        let shuffle = isShuffleEnabled
        let repeatValue = repeatMode.rawValue
        let context = queueContext
        persistenceTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            try? await repository.save(
                history: history,
                current: current,
                upcoming: upcoming,
                elapsedSeconds: elapsed,
                shuffleEnabled: shuffle,
                repeatMode: repeatValue,
                context: context
            )
        }
    }

    private func restoreState() async {
        guard let state = try? await queueRepository.load() else { return }
        let history = state.items.filter { $0.status == .history }.sorted { $0.position < $1.position }.map(\.track)
        let current = state.items.first { $0.status == .current }?.track
        let upcoming = state.items.filter { $0.status == .upcoming }.sorted { $0.position < $1.position }.map(\.track)
        playbackHistory = history
        queue = history + (current.map { [$0] } ?? []) + upcoming
        currentIndex = current == nil ? nil : history.count
        currentTrack = current ?? .empty
        isShuffleEnabled = state.shuffleEnabled
        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
        queueContext = state.context
        if let url = currentTrack.fileURL {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            seek(to: state.elapsedSeconds)
        }
    }
}
