import CryptoKit
import Foundation

extension Notification.Name {
    static let catalogLibraryDidChange = Notification.Name("ShizoMusic.catalogLibraryDidChange")
    static let musicFolderDidChange = Notification.Name("ShizoMusic.musicFolderDidChange")
}

@MainActor
final class CatalogTransferManager: NSObject, ObservableObject {
    @Published private(set) var transfers: [MediaTransfer] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var downloadedBytes: Int64 = 0

    private let authorization: AuthorizationStore
    private let repository: CatalogRepository
    private var uploadInFlight = false
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.shizomusic.media-transfers")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(authorization: AuthorizationStore, repository: CatalogRepository = CatalogRepository()) {
        self.authorization = authorization
        self.repository = repository
        super.init()
        _ = session
    }

    func synchronize() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await repository.recoverInterruptedTransfers(activeIDs: await activeTransferIDs())
            try await repository.enqueueLocalUploads()
            if let credentials = try await authorization.syncCredentials() {
                let catalog = try await credentials.client.catalog(accessToken: credentials.accessToken)
                try await repository.merge(catalog, baseURL: credentials.client.baseURL)
                NotificationCenter.default.post(name: .catalogLibraryDidChange, object: nil)
                await startNextUpload(credentials: credentials)
            }
            await reload()
            let queuedDownloads = transfers.filter { $0.direction == .download && $0.state == .queued }
            for transfer in queuedDownloads { await resume(transfer) }
        } catch { errorMessage = error.localizedDescription; await reload() }
    }

    func download(trackID: String) async {
        do { try await repository.enqueueDownload(trackID: trackID); await reload(); if let item = transfers.first(where: { $0.trackID == trackID && $0.direction == .download && $0.state == .queued }) { await resume(item) } }
        catch { errorMessage = error.localizedDescription }
    }

    func download(remoteFileID: String) async {
        do {
            guard let trackID = try await repository.enqueueDownload(remoteFileID: remoteFileID) else {
                errorMessage = String(localized: "search.download_source_unavailable")
                return
            }
            await reload()
            if let item = transfers.first(where: { $0.trackID == trackID && $0.direction == .download && $0.state == .queued }) {
                await resume(item)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func pause(_ transfer: MediaTransfer) async {
        try? await repository.setTransferState(transfer.id, .paused)
        session.getAllTasks { [repository] tasks in
            guard let task = tasks.first(where: { $0.taskDescription?.contains(transfer.id.uuidString) == true }) else { return }
            if let download = task as? URLSessionDownloadTask {
                download.cancel { data in Task { try? await repository.setTransferState(transfer.id, .paused, resumeData: data) } }
            } else {
                task.cancel()
                Task { @MainActor in self.uploadInFlight = false }
            }
        }
        await reload()
    }

    func resume(_ transfer: MediaTransfer) async {
        do {
            if transfer.direction == .download, let (url, resumeData) = try await repository.downloadRequest(transfer.id) {
                let task = resumeData.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: url)
                task.taskDescription = "download|\(transfer.id.uuidString)"; task.resume()
                try await repository.setTransferState(transfer.id, .running, error: nil)
            } else if transfer.direction == .upload, let credentials = try await authorization.syncCredentials() {
                try await repository.setTransferState(transfer.id, .queued, error: nil)
                await startNextUpload(credentials: credentials)
            }
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func cancel(_ transfer: MediaTransfer) async {
        session.getAllTasks { tasks in
            tasks.first(where: { $0.taskDescription?.contains(transfer.id.uuidString) == true })?.cancel()
        }
        if transfer.direction == .upload { uploadInFlight = false }
        try? await repository.setTransferState(transfer.id, .cancelled)
        if let sessionID = transfer.uploadSessionID,
           let credentials = try? await authorization.syncCredentials() {
            try? await credentials.client.cancelUpload(id: sessionID, accessToken: credentials.accessToken)
        }
        await reload()
    }

    func retry(_ transfer: MediaTransfer) async {
        try? await repository.setTransferState(transfer.id, .queued, error: nil)
        if transfer.direction == .download {
            await resume(transfer)
        } else {
            await synchronize()
        }
    }
    func deleteLocalCopy(trackID: String) async -> Int? {
        do {
            let remaining = try await repository.deleteLocalCopy(trackID: trackID)
            NotificationCenter.default.post(name: .musicFolderDidChange, object: nil)
            await reload()
            return remaining
        }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    func remoteSourceCount(trackID: String) async -> Int {
        (try? await repository.remoteSourceCount(trackID: trackID)) ?? 0
    }
    func removeAllDownloads() async {
        do {
            try await repository.removeAllDownloads()
            NotificationCenter.default.post(name: .musicFolderDidChange, object: nil)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    func reload() async {
        if let values = try? await repository.transfers() { transfers = values }
        if let value = try? await repository.downloadedStorageBytes() { downloadedBytes = value }
    }

    private func activeTransferIDs() async -> Set<UUID> {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                let ids = tasks.compactMap { task -> UUID? in
                    guard let value = task.taskDescription?.split(separator: "|").dropFirst().first else { return nil }
                    return UUID(uuidString: String(value))
                }
                continuation.resume(returning: Set(ids))
            }
        }
    }

    private func startNextUpload(credentials: AuthorizationStore.SyncCredentials) async {
        guard !uploadInFlight else { return }
        do {
            guard let candidate = try await repository.nextUpload() else { return }
            uploadInFlight = true
            let mime = candidate.format == "flac" ? "audio/flac" : "audio/mpeg"
            let upload = try await credentials.client.createUpload(filename: candidate.fileURL.lastPathComponent, mimeType: mime,
                                                                    byteSize: candidate.byteSize, sha256: candidate.contentHash, accessToken: credentials.accessToken)
            if upload.alreadyAvailableFileId != nil {
                try await repository.updateUpload(candidate.transferID, state: .completed, transferred: candidate.byteSize, total: candidate.byteSize)
                uploadInFlight = false; await reload(); await startNextUpload(credentials: credentials); return
            }
            let nextPart = (upload.uploadedParts.max() ?? 0) + 1
            try await repository.updateUpload(candidate.transferID, state: .running, sessionID: upload.id, nextPart: nextPart, total: candidate.byteSize)
            try startUploadPart(candidate: candidate, upload: upload, partNumber: nextPart, credentials: credentials)
        } catch { uploadInFlight = false; errorMessage = error.localizedDescription; await reload() }
    }

    private func startUploadPart(candidate: LocalUploadCandidate, upload: APIUploadSession, partNumber: Int, credentials: AuthorizationStore.SyncCredentials) throws {
        guard partNumber <= upload.totalParts else { Task { await completeUpload(candidate: candidate, uploadID: upload.id) }; return }
        let handle = try FileHandle(forReadingFrom: candidate.fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64((partNumber - 1) * upload.partSize))
        let data = try handle.read(upToCount: upload.partSize) ?? Data()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShizoMusicUploadParts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let partURL = root.appendingPathComponent("\(candidate.transferID.uuidString)-\(partNumber).part")
        try data.write(to: partURL, options: .atomic)
        let request = credentials.client.uploadPartRequest(uploadID: upload.id, partNumber: partNumber, sha256: hash, accessToken: credentials.accessToken)
        let task = session.uploadTask(with: request, fromFile: partURL)
        task.taskDescription = "upload|\(candidate.transferID.uuidString)|\(upload.id.uuidString)|\(partNumber)|\(upload.totalParts)|\(upload.partSize)"
        task.resume()
    }

    private func completeUpload(candidate: LocalUploadCandidate, uploadID: UUID) async {
        do {
            guard let credentials = try await authorization.syncCredentials() else { throw URLError(.userAuthenticationRequired) }
            _ = try await credentials.client.completeUpload(id: uploadID, accessToken: credentials.accessToken)
            try await repository.updateUpload(candidate.transferID, state: .completed, transferred: candidate.byteSize, total: candidate.byteSize)
            uploadInFlight = false; await synchronize()
        } catch { try? await repository.updateUpload(candidate.transferID, state: .failed, error: error.localizedDescription); uploadInFlight = false; await reload() }
    }

    private func handleUploadCompletion(description: String, statusCode: Int?, errorDescription: String?) async {
        let values = description.split(separator: "|")
        guard values.count == 6,
              let transferID = UUID(uuidString: String(values[1])), let uploadID = UUID(uuidString: String(values[2])),
              let part = Int(values[3]), let totalParts = Int(values[4]), let partSize = Int(values[5]),
              let candidate = try? await repository.uploadCandidate(id: transferID) else { uploadInFlight = false; return }
        let partURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShizoMusicUploadParts", isDirectory: true)
            .appendingPathComponent("\(transferID.uuidString)-\(part).part")
        try? FileManager.default.removeItem(at: partURL)
        if let errorDescription { try? await repository.updateUpload(transferID, state: .failed, error: errorDescription); uploadInFlight = false; await reload(); return }
        if let statusCode, !(200..<300).contains(statusCode) {
            try? await repository.updateUpload(transferID, state: .failed, error: "HTTP \(statusCode)")
            uploadInFlight = false
            await reload()
            return
        }
        let transferred = min(Int64(part * partSize), candidate.byteSize)
        try? await repository.updateUpload(transferID, state: .running, nextPart: part + 1, transferred: transferred, total: candidate.byteSize)
        guard let credentials = try? await authorization.syncCredentials() else { uploadInFlight = false; return }
        if part >= totalParts { await completeUpload(candidate: candidate, uploadID: uploadID) }
        else {
            let upload = APIUploadSession(id: uploadID, partSize: partSize, totalParts: totalParts, uploadedParts: Array(1...part), expiresAt: "", alreadyAvailableFileId: nil)
            do { try startUploadPart(candidate: candidate, upload: upload, partNumber: part + 1, credentials: credentials) }
            catch { try? await repository.updateUpload(transferID, state: .failed, error: error.localizedDescription); uploadInFlight = false }
        }
        await reload()
    }
}

extension CatalogTransferManager: URLSessionTaskDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            ShizoMusicAppDelegate.backgroundSessionCompletion?()
            ShizoMusicAppDelegate.backgroundSessionCompletion = nil
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let description = task.taskDescription
        let errorCode = (error as NSError?)?.code
        let errorDescription = error?.localizedDescription
        let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        if errorCode == NSURLErrorCancelled { return }
        guard description?.hasPrefix("upload|") == true else {
            if let errorDescription, let value = description?.split(separator: "|").last, let id = UUID(uuidString: String(value)) {
                Task { @MainActor in try? await self.repository.setTransferState(id, .failed, error: errorDescription, resumeData: resumeData); await self.reload() }
            }
            return
        }
        guard let description else { return }
        Task { @MainActor in
            await self.handleUploadCompletion(description: description, statusCode: statusCode, errorDescription: errorDescription)
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let value = downloadTask.taskDescription?.split(separator: "|").last, let id = UUID(uuidString: String(value)), totalBytesExpectedToWrite > 0 else { return }
        Task { @MainActor in try? await self.repository.setTransferState(id, .running, progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)); await self.reload() }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let value = downloadTask.taskDescription?.split(separator: "|").last, let id = UUID(uuidString: String(value)) else { return }
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard statusCode.map({ (200..<300).contains($0) }) ?? false else {
            try? FileManager.default.removeItem(at: location)
            Task { @MainActor in
                try? await self.repository.setTransferState(id, .failed, error: "HTTP \(statusCode ?? 0)")
                await self.reload()
            }
            return
        }
        let retained = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(id.uuidString)")
        try? FileManager.default.removeItem(at: retained); try? FileManager.default.moveItem(at: location, to: retained)
        Task { @MainActor in
            do {
                try await self.repository.finishDownload(id, temporaryURL: retained)
                NotificationCenter.default.post(name: .musicFolderDidChange, object: nil)
            } catch {
                try? await self.repository.setTransferState(id, .failed, error: error.localizedDescription)
            }
            await self.reload()
        }
    }
}
