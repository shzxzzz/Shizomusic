import CoreImage
import SwiftUI
import UIKit

struct ArtworkPalette: Equatable, Sendable {
    struct Component: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }

        func vivid(minimumBrightness: Double) -> Component {
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let targetSaturation = min(max(saturation, 0.34), 0.82)
            let targetBrightness = min(max(maximum, minimumBrightness), 0.82)
            guard maximum > 0, saturation > 0.01 else {
                return Component(red: targetBrightness * 0.78, green: targetBrightness * 0.86, blue: targetBrightness)
            }
            let scale = targetBrightness / maximum
            let liftedMinimum = targetBrightness * (1 - targetSaturation)
            func channel(_ value: Double) -> Double {
                liftedMinimum + (value - minimum) * scale * targetSaturation / saturation
            }
            return Component(red: min(channel(red), 1), green: min(channel(green), 1), blue: min(channel(blue), 1))
        }
    }

    let base: Component
    let primary: Component
    let secondary: Component

    static let fallback = ArtworkPalette(
        base: .init(red: 0.08, green: 0.11, blue: 0.15),
        primary: .init(red: 0.24, green: 0.40, blue: 0.52),
        secondary: .init(red: 0.30, green: 0.22, blue: 0.48)
    )
}

enum ArtworkPaletteExtractor {
    static func palette(artworkURL: URL?, fallbackName: String) async -> ArtworkPalette {
        await Task.detached(priority: .userInitiated, operation: {
            let image = artworkURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(named: fallbackName)
            guard let ciImage = image.flatMap({ CIImage(image: $0) }) else { return .fallback }
            let extent = ciImage.extent
            let regions = [
                extent,
                CGRect(x: extent.minX, y: extent.midY, width: extent.width / 2, height: extent.height / 2),
                CGRect(x: extent.midX, y: extent.midY, width: extent.width / 2, height: extent.height / 2),
                CGRect(x: extent.minX, y: extent.minY, width: extent.width / 2, height: extent.height / 2),
                CGRect(x: extent.midX, y: extent.minY, width: extent.width / 2, height: extent.height / 2)
            ]
            let context = CIContext()
            let samples = regions.compactMap { averageColor(of: ciImage, region: $0, context: context) }
            guard let average = samples.first else { return .fallback }
            let accents = Array(samples.dropFirst()).sorted { colorfulness($0) > colorfulness($1) }
            return ArtworkPalette(
                base: average.vivid(minimumBrightness: 0.18),
                primary: (accents.first ?? average).vivid(minimumBrightness: 0.38),
                secondary: (accents.dropFirst().first ?? average).vivid(minimumBrightness: 0.30)
            )
        }).value
    }

    private static func averageColor(of image: CIImage, region: CGRect, context: CIContext) -> ArtworkPalette.Component? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: region), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return .init(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
    }

    private static func colorfulness(_ color: ArtworkPalette.Component) -> Double {
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        return (maximum - minimum) * 1.7 + maximum * 0.3
    }
}
