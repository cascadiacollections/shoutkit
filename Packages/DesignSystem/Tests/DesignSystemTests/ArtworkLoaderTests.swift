import CoreGraphics
import Testing
import UIKit

@testable import DesignSystem

struct ArtworkLoaderTests {
    @Test
    func paletteSamplesPreserveTopLeftRowMajorOrder() throws {
        let image = try #require(makeImage(colors: [
            .red, .green, .blue,
            .yellow, .magenta, .cyan,
            .white, .gray, .black
        ]))
        let samples = ArtworkLoader.paletteHSBSamples(from: image)

        #expect(samples.count == 9)
        #expect(samples[0].saturation > 0.9)
        #expect(samples[0].brightness > 0.9)
        #expect(samples[2].hue > 0.55 && samples[2].hue < 0.75) // blue
        #expect(samples[6].saturation < 0.05) // white
        #expect(samples[8].brightness < 0.05) // black
    }

    private func makeImage(colors: [UIColor]) -> CGImage? {
        let side = 3
        var pixels: [UInt8] = []
        pixels.reserveCapacity(colors.count * 4)

        for color in colors {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            pixels.append(UInt8(red * 255))
            pixels.append(UInt8(green * 255))
            pixels.append(UInt8(blue * 255))
            pixels.append(255)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
