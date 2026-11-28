import Foundation
import Nuke
import RadioDirectory

/// Loads artwork bytes through the existing transports so a maintenance-page
/// body is still a failed fetch (`ImagePayload`) and so prefetch keeps the
/// speculative session's Low Data Mode / cellular refusal.
///
/// The lane header is stripped before the request is sent. It only tells this
/// loader which of the two production sessions to use; Nuke coalesces the
/// underlying download by URL, so the header must not be part of what the
/// server sees.
nonisolated final class LaneArtworkDataLoader: DataLoading, @unchecked Sendable {
    static let header = "X-ShoutKit-Artwork-Lane"
    static let speculative = "speculative"

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void,
    ) -> any Cancellable {
        var outbound = request
        let useSpeculative = outbound.value(forHTTPHeaderField: Self.header) == Self.speculative
        outbound.setValue(nil, forHTTPHeaderField: Self.header)
        let transport: any HTTPTransporting = useSpeculative
            ? URLSessionHTTPTransport.speculative
            : URLSessionHTTPTransport.artwork
        return ArtworkDataLoad.perform(
            transport: transport,
            request: outbound,
            didReceiveData: didReceiveData,
            completion: completion,
        )
    }
}

/// Same validation as ``LaneArtworkDataLoader``, bound to one injected transport
/// so tests (and any non-production session) do not share the app's disk cache.
nonisolated final class TransportArtworkDataLoader: DataLoading, @unchecked Sendable {
    private let transport: any HTTPTransporting

    init(transport: any HTTPTransporting) {
        self.transport = transport
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void,
    ) -> any Cancellable {
        ArtworkDataLoad.perform(
            transport: transport,
            request: request,
            didReceiveData: didReceiveData,
            completion: completion,
        )
    }
}

nonisolated enum ArtworkDataLoad {
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

private nonisolated final class TaskDataCancel: Cancellable, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
