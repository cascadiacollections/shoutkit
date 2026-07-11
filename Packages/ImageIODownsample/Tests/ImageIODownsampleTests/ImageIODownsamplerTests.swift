import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ImageIODownsample

struct ImageIODownsamplerTests {
    /// Builds a solid-color PNG of the requested pixel size to use as decode
    /// input — avoids committing a binary fixture, and lets each test pick a
    /// source larger than the downsample ceiling it wants to exercise.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cgImage = try #require(context.makeImage())
        let encoded = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                encoded as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return encoded as Data
    }

    @Test func decodeReturnsNilForInvalidData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(ImageIODownsampler.decodeCGImage(garbage, maxPixelSize: 256) == nil)
    }

    @Test func encodeReturnsNilForInvalidData() {
        let garbage = Data("definitely not an image".utf8)
        #expect(ImageIODownsampler.encode(garbage, maxPixelSize: 256, outputType: .png) == nil)
    }

    @Test func decodeCapsLongerEdgeToMaxPixelSize() throws {
        let source = try makePNG(width: 200, height: 100)
        let decoded = try #require(ImageIODownsampler.decodeCGImage(source, maxPixelSize: 50))
        #expect(max(decoded.width, decoded.height) <= 50)
    }

    @Test func encodeProducesPNGSignature() throws {
        let source = try makePNG(width: 120, height: 120)
        let encoded = try #require(ImageIODownsampler.encode(source, maxPixelSize: 64, outputType: .png))
        // The 8-byte PNG magic number every PNG stream begins with.
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(encoded.prefix(pngSignature.count)) == pngSignature)
    }

    /// A `CGFloat` ceiling with a fractional part must be coerced to an integer
    /// pixel count rather than rejected or truncated past the cap.
    @Test func fractionalMaxPixelSizeIsCoerced() throws {
        let source = try makePNG(width: 200, height: 100)
        let decoded = try #require(ImageIODownsampler.decodeCGImage(source, maxPixelSize: 49.7))
        #expect(max(decoded.width, decoded.height) <= 50)
    }
}
