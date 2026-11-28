import Foundation
import ImageIO
import Nuke
import RadioDirectory

/// Loads artwork bytes through the production transports so a maintenance-page
/// body is still a failed fetch (`ImagePayload`) and so prefetch keeps the
/// speculative session's Low Data Mode / cellular refusal.
///
/// The lane header is stripped before the request is sent. It only tells this
/// loader which of the two sessions to use. It is not what keeps the lanes
/// apart inside Nuke — Nuke coalesces downloads on URL, cache policy, and
/// `allowsCellularAccess`, never on headers — so ``ArtworkLane`` also gives the
/// speculative request its own cache policy (see ``ArtworkLane/cachePolicy``).
final class LaneArtworkDataLoader: DataLoading, @unchecked Sendable {
    static let header = "X-ShoutKit-Artwork-Lane"
    static let speculative = "speculative"

    private let visibleTransport: any HTTPTransporting
    private let speculativeTransport: any HTTPTransporting

    init(visible: any HTTPTransporting, speculative: any HTTPTransporting) {
        visibleTransport = visible
        speculativeTransport = speculative
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void,
    ) -> any Cancellable {
        var outbound = request
        let useSpeculative = outbound.value(forHTTPHeaderField: Self.header) == Self.speculative
        outbound.setValue(nil, forHTTPHeaderField: Self.header)
        // Both lanes go out with the same policy; the speculative one differs
        // only so Nuke keys its download separately.
        outbound.cachePolicy = ArtworkLane.visible.cachePolicy
        return ArtworkDataLoad.perform(
            transport: useSpeculative ? speculativeTransport : visibleTransport,
            request: outbound,
            didReceiveData: didReceiveData,
            completion: completion,
        )
    }
}

/// Same validation as ``LaneArtworkDataLoader``, bound to one caller-supplied
/// transport (tests, previews, any non-production session).
///
/// A class transport is held weakly: the store keeps this loader's pipeline
/// only as long as the transport lives, and a strong reference here would keep
/// the transport — and so the pipeline — alive for the rest of the process.
final class TransportArtworkDataLoader: DataLoading, @unchecked Sendable {
    private let strongTransport: any HTTPTransporting?
    private weak var weakTransport: AnyObject?

    init(retaining transport: any HTTPTransporting) {
        strongTransport = transport
    }

    init(weaklyReferencing transport: any HTTPTransporting & AnyObject) {
        strongTransport = nil
        weakTransport = transport
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void,
    ) -> any Cancellable {
        guard let transport = strongTransport ?? (weakTransport as? any HTTPTransporting) else {
            completion(CancellationError())
            return NoopCancel()
        }
        return ArtworkDataLoad.perform(
            transport: transport,
            request: request,
            didReceiveData: didReceiveData,
            completion: completion,
        )
    }
}

enum ArtworkDataLoad {
    static func perform(
        transport: any HTTPTransporting,
        request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void,
    ) -> any Cancellable {
        let task = Task {
            do {
                let data = try await transport.imageData(for: request)
                guard Task.isCancelled == false else {
                    completion(CancellationError())
                    return
                }
                // Nuke writes the original bytes to its disk cache *before*
                // decoding them (`dataCachePolicy = .storeOriginalData`), and
                // nothing revalidates a disk hit. A 200 body that passed the
                // HTML sniff but is not an image would otherwise be served
                // from disk, undecodable, until eviction.
                guard isDecodableImage(data) else {
                    completion(URLError(.cannotDecodeContentData))
                    return
                }
                guard let response = httpResponse(for: request) else {
                    completion(URLError(.badURL))
                    return
                }
                didReceiveData(data, response)
                completion(nil)
            } catch {
                completion(error)
            }
        }
        return TaskDataCancel(task)
    }

    /// ImageIO recognizes a container and finds at least one image in it.
    /// Cheap: it reads headers, not pixels.
    static func isDecodableImage(_ data: Data) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetType(source) != nil
        else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Nuke wants a response alongside the bytes. `imageData` already rejected
    /// non-2xx and HTML, so a synthetic 200 is an honest description of what
    /// reached the decoder. ImageIO sniffs the bytes; the content type is only
    /// a hint.
    private static func httpResponse(for request: URLRequest) -> HTTPURLResponse? {
        guard let url = request.url else { return nil }
        return HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"],
        )
    }
}

private final class TaskDataCancel: Cancellable, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

private final class NoopCancel: Cancellable, Sendable {
    func cancel() {}
}
