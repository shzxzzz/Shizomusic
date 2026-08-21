import SwiftUI

struct DownloadManagementScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: CatalogTransferManager
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var musicSearch: MusicSearchStore
    @State private var confirmsCleanup = false

    var body: some View {
        NavigationStack {
            List {
                Section("downloads.storage") {
                    LabeledContent("downloads.offline_copies", value: ByteCountFormatter.string(fromByteCount: manager.downloadedBytes, countStyle: .file))
                    if manager.downloadedBytes > 0 { Button("downloads.remove_all", role: .destructive) { confirmsCleanup = true } }
                }
                Section("search.server_acquisitions") {
                    if musicSearch.acquisitionJobs.isEmpty {
                        Text("search.no_acquisitions").foregroundStyle(.secondary)
                    } else {
                        ForEach(musicSearch.acquisitionJobs) { job in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(verbatim: job.title).lineLimit(1); Spacer(); Text(verbatim: job.state).font(.caption).foregroundStyle(.secondary) }
                                ProgressView(value: job.progress)
                                if let detail = job.errorDetail { Text(verbatim: detail).font(.caption).foregroundStyle(.red) }
                                if job.state == "failed" { Button("sync.retry") { Task { await musicSearch.retryAcquisition(job.id) } }.font(.caption) }
                            }.padding(.vertical, 3)
                        }
                    }
                }
                if manager.transfers.isEmpty {
                    ContentUnavailableView("downloads.empty", systemImage: "arrow.down.circle")
                } else {
                    ForEach(manager.transfers) { transfer in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: transfer.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                Text(verbatim: transfer.title).lineLimit(1)
                                Spacer()
                                Text(LocalizedStringKey("downloads.state_\(transfer.state.rawValue)"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: transfer.progress)
                            HStack {
                                Text(verbatim: ByteCountFormatter.string(fromByteCount: transfer.transferredBytes, countStyle: .file))
                                Spacer()
                                controls(transfer)
                            }.font(.caption)
                            if let error = transfer.lastError { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("downloads.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("common.close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await manager.synchronize() } } label: { Image(systemName: "arrow.clockwise") } }
            }
            .task {
                await manager.reload()
                while !Task.isCancelled {
                    await musicSearch.reloadAcquisitions()
                    if musicSearch.acquisitionJobs.contains(where: { $0.state == "completed" }) {
                        await manager.synchronize()
                        await localLibrary.load()
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .confirmationDialog("downloads.remove_all_warning", isPresented: $confirmsCleanup, titleVisibility: .visible) {
                Button("downloads.remove_all", role: .destructive) {
                    Task {
                        await manager.removeAllDownloads()
                        await localLibrary.load()
                    }
                }
                Button("common.cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private func controls(_ transfer: MediaTransfer) -> some View {
        switch transfer.state {
        case .running: Button("downloads.pause") { Task { await manager.pause(transfer) } }
        case .paused: Button("downloads.resume") { Task { await manager.resume(transfer) } }
        case .failed: Button("sync.retry") { Task { await manager.retry(transfer) } }
        case .queued: ProgressView().controlSize(.small)
        case .completed, .cancelled: EmptyView()
        }
        if transfer.state != .completed && transfer.state != .cancelled {
            Button("downloads.cancel", role: .destructive) { Task { await manager.cancel(transfer) } }
        }
    }
}
