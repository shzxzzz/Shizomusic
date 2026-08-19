import AVFoundation
import MediaPlayer
import SwiftUI

struct PlayableTrack: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int
    let artworkName: String
    let fileURL: URL?

    init(
        id: String,
        title: String,
        artist: String,
        durationSeconds: Int,
        artworkName: String,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.artworkName = artworkName
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
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var playbackError: String?
    @Published var isShuffleEnabled = false {
        didSet { persistState() }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { persistState(); updateNowPlaying() }
    }

    private let player = AVPlayer()
    private var currentIndex: Int?
    private var history: [PlayableTrack] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var shouldResumeAfterInterruption = false
    private var isRestoring = true

    private static let stateKey = "playback.queue.v1"

    init() {
        configureAudioSession()
        restoreState()
        observePlayer()
        configureRemoteCommands()
        isRestoring = false
    }

    var progress: Double {
        guard currentTrack.durationSeconds > 0 else { return 0 }
        return min(max(elapsedSeconds / Double(currentTrack.durationSeconds), 0), 1)
    }

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
            history.removeAll { $0.fileURL != nil }
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
        if let index = queue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
            currentTrack = queue[index]
        } else if currentIndex == nil || currentTrack == .empty {
            currentIndex = 0
            currentTrack = queue[0]
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

    func play(_ tracks: [PlayableTrack], startingAt index: Int = 0) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        history.removeAll()
        selectTrack(at: index, autoplay: true)
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
            try AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            updateNowPlaying()
        } catch {
            playbackError = error.localizedDescription
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        persistState()
    }

    func seek(to seconds: Double) {
        let duration = Double(max(currentTrack.durationSeconds, 0))
        let target = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        elapsedSeconds = target
        updateNowPlaying()
    }

    func seek(toProgress progress: Double) {
        seek(to: Double(currentTrack.durationSeconds) * min(max(progress, 0), 1))
    }

    func skip(by interval: Double) {
        seek(to: elapsedSeconds + interval)
    }

    func next() {
        advance(automatic: false)
    }

    func previous() {
        if elapsedSeconds > 3 {
            seek(to: 0)
            return
        }
        guard !history.isEmpty else {
            seek(to: 0)
            return
        }
        let previous = history.removeLast()
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
        var future = currentIndex + 1 < queue.count ? Array(queue[(currentIndex + 1)...]) : []
        future.shuffle()
        queue = playedAndCurrent + future
        persistState()
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

    private func clear() {
        player.replaceCurrentItem(with: nil)
        queue = []
        currentIndex = nil
        currentTrack = .empty
        elapsedSeconds = 0
        isPlaying = false
        persistState()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func selectTrack(at index: Int, autoplay: Bool, recordHistory: Bool = true) {
        guard queue.indices.contains(index) else { return }
        if recordHistory, currentTrack != .empty, currentTrack.id != queue[index].id {
            history.append(currentTrack)
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

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if autoplay { resume() }
        persistState()
        updateNowPlaying()
    }

    private func advance(automatic: Bool) {
        guard let currentIndex, !queue.isEmpty else { return }
        if automatic, repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }

        let nextIndex = currentIndex + 1
        if queue.indices.contains(nextIndex) {
            selectTrack(at: nextIndex, autoplay: true)
        } else if repeatMode == .all {
            selectTrack(at: 0, autoplay: true)
        } else {
            pause()
            seek(to: Double(currentTrack.durationSeconds))
        }
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
            Task { @MainActor in
                guard let self else { return }
                elapsedSeconds = max(time.seconds.isFinite ? time.seconds : 0, 0)
                updateNowPlaying()
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
            Task { @MainActor in
                self?.playbackError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                self?.advance(automatic: true)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            shouldResumeAfterInterruption = isPlaying
            pause()
        } else if shouldResumeAfterInterruption,
                  let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
            resume()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        pause()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
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
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            Task { @MainActor in
                switch event.repeatType {
                case .off: self?.repeatMode = .off
                case .one: self?.repeatMode = .one
                case .all: self?.repeatMode = .all
                @unknown default: self?.repeatMode = .off
                }
            }
            return .success
        }
        center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            Task { @MainActor in
                let shouldShuffle = event.shuffleType != .off
                if self?.isShuffleEnabled != shouldShuffle { self?.toggleShuffle() }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard currentTrack != .empty else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyPlaybackDuration: currentTrack.durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private struct PersistedState: Codable {
        let queue: [PlayableTrack]
        let currentID: String?
        let elapsedSeconds: Double
        let shuffle: Bool
        let repeatMode: RepeatMode
    }

    private func persistState() {
        guard !isRestoring else { return }
        let state = PersistedState(
            queue: queue,
            currentID: currentTrack == .empty ? nil : currentTrack.id,
            elapsedSeconds: elapsedSeconds,
            shuffle: isShuffleEnabled,
            repeatMode: repeatMode
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        queue = state.queue.filter { track in
            guard let url = track.fileURL else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
        isShuffleEnabled = state.shuffle
        repeatMode = state.repeatMode
        guard let currentID = state.currentID,
              let index = queue.firstIndex(where: { $0.id == currentID }) else { return }
        currentIndex = index
        currentTrack = queue[index]
        if let url = currentTrack.fileURL {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            seek(to: state.elapsedSeconds)
        }
    }
}

// Temporary compatibility for the preview-only models that will be removed as
// the remaining mocked catalog screens are connected to repositories.
typealias MockPlayableTrack = PlayableTrack
typealias MockPlaybackState = PlaybackCoordinator
