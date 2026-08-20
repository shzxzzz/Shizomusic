import SwiftUI
import UIKit

struct TrackArtworkView: View {
    let artworkURL: URL?
    let fallbackName: String

    var body: some View {
        Group {
            if let artworkURL, artworkURL.isFileURL,
               let image = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: image)
                    .resizable()
            } else if let artworkURL, artworkURL.scheme?.hasPrefix("http") == true {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image { image.resizable() }
                    else { Image(fallbackName).resizable() }
                }
            } else {
                Image(fallbackName)
                    .resizable()
            }
        }
    }
}
