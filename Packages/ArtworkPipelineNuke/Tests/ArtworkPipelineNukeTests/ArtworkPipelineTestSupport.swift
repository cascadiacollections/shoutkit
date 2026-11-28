import CoreGraphics
import Foundation
import ImageIO
import os
import RadioDirectory
import UniformTypeIdentifiers

// Fakes and helpers for ArtworkPipelineTests, split out for `file_length`.

/// Polls `condition` for up to two seconds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

func png(side: Int) -> Data {
    let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    )
    context?.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let data = NSMutableData()
    guard let image = context?.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return Data() }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func response(for request: URLRequest, mimeType: String) throws -> HTTPURLResponse {
    let url = request.url ?? URL(fileURLWithPath: "/artwork")
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": mimeType],
    ) else {
        throw URLError(.badServerResponse)
    }
    return response
}

// MARK: - Transports

actor ScriptedImageTransport: HTTPTransporting {
    private var body: Data
    private let mimeType: String
    private var failure: URLError?
    private(set) var sends = 0

    init(body: Data, mimeType: String = "image/png") {
        self.body = body
        self.mimeType = mimeType
    }

    func setFailure(_ failure: URLError?) {
        self.failure = failure
    }

    func setBody(_ body: Data) {
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        sends += 1
        if let failure {
            throw failure
        }
        return try (body, response(for: request, mimeType: mimeType))
    }
}

/// Blocks inside `send` so a test can observe how many fetches started before
/// letting them finish. With `failAfterRelease`, released fetches fail the way
/// the speculative session refuses on cellular.
actor HoldingImageTransport: HTTPTransporting {
    private let body: Data
    private let failAfterRelease: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var sends = 0

    init(body: Data, failAfterRelease: Bool = false) {
        self.body = body
        self.failAfterRelease = failAfterRelease
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        sends += 1
        if released == false {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        if failAfterRelease {
            throw URLError(.dataNotAllowed)
        }
        return try (body, response(for: request, mimeType: "image/png"))
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

actor UnusedTransport: HTTPTransporting {
    func send(_: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.unsupportedURL)
    }
}

final class SendCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var value: Int {
        count.withLock { $0 }
    }

    func increment() {
        count.withLock { $0 += 1 }
    }
}

final class WeakReference: @unchecked Sendable {
    weak var object: AnyObject?
}

/// A value-type transport: no identity for the store to key on.
struct ValueTransport: HTTPTransporting {
    let body: Data?
    let counter = SendCounter()

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        counter.increment()
        guard let body else {
            throw URLError(.cannotConnectToHost)
        }
        return try (body, response(for: request, mimeType: "image/png"))
    }
}
