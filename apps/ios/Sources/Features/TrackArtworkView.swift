import SwiftUI
import UIKit

struct TrackArtworkView: View {
    let artworkURL: URL?
    let fallbackName: String

    var body: some View {
        Group {
            if let artworkURL,
               let image = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image(fallbackName)
                    .resizable()
            }
        }
    }
}
