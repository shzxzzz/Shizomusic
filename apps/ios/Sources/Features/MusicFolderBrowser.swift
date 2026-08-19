import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct MusicFolderBrowser: UIViewControllerRepresentable {
    let directoryURL: URL
    let onSelect: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audio],
            asCopy: false
        )
        picker.directoryURL = directoryURL
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelect: ([URL]) -> Void

        init(onSelect: @escaping ([URL]) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onSelect(urls)
        }
    }
}
