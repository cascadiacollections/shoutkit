import AudioStreaming
import AudioToolbox
import Foundation
@testable import PlaybackEngineAudioStreaming
import Synchronization
import Testing

/// Serves canned responses to `SingleRequestStreamSource`'s session and records
/// every request it was asked for.
final class StubStreamProtocol: URLProtocol {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        var failure: URLError.Code?
    }

    static let reply = Mutex(Reply())
    static let requests = Mutex([URLRequest]())

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let reply = Self.reply.withLock { $0 }
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers,
              )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if let failure = reply.failure {
            // A beat later, as a dropped connection is: failing in the same
            // turn lets the loader discard data it hasn't handed on yet.
            nonisolated(unsafe) let loader = self
            let client = client
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                client?.urlProtocol(loader, didFailWithError: URLError(failure))
            }
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Records what the source tells the player.
final class RecordingSourceDelegate: AudioStreamSourceDelegate, @unchecked Sendable {
    let audio = Mutex(Data())
    let titles = Mutex([String]())
    let errors = Mutex(0)
    let endOfFile = Mutex(false)
    let wrongQueue = Mutex(false)
    var expectedQueue: DispatchQueue?

    func dataAvailable(source _: CoreAudioStreamSource, data: Data) {
        if let expectedQueue {
            checkQueue(expectedQueue)
        }
        audio.withLock { $0.append(data) }
    }

    func errorOccurred(source _: CoreAudioStreamSource, error _: Error) {
        errors.withLock { $0 += 1 }
    }

    func endOfFileOccurred(source _: CoreAudioStreamSource) {
        endOfFile.withLock { $0 = true }
    }

    func metadataReceived(data: [String: String]) {
        if let title = data["StreamTitle"] {
            titles.withLock { $0.append(title) }
        }
    }

    private func checkQueue(_ queue: DispatchQueue) {
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        if DispatchQueue.getSpecific(key: key) != true {
            wrongQueue.withLock { $0 = true }
        }
    }
}

/// Counts fallbacks. A class around the Mutex, which is noncopyable and so
/// can't be passed as an optional parameter.
final class FallbackCounter: Sendable {
    let count = Mutex(0)
}

/// Enough headers (more than two) to read as a normal HTTP response.
private func headers(_ contentType: String) -> [String: String] {
    ["Content-Type": contentType, "Server": "x", "Date": "y"]
}

private func eventually(_ condition: () -> Bool) async {
    for _ in 0 ..< 200 where condition() == false {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// Serialized: the stub's reply and request log are shared.
@Suite(.serialized)
struct SingleRequestStreamSourceTests {
    private let url = URL(string: "https://radio.example/live.aac")!

    private func makeSource(
        queue: DispatchQueue,
        fallbacks: FallbackCounter? = nil,
    ) -> SingleRequestStreamSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubStreamProtocol.self]
        return SingleRequestStreamSource(url: url, underlyingQueue: queue, configuration: configuration) {
            fallbacks?.count.withLock { $0 += 1 }
        }
    }

    private func prepare(_ reply: StubStreamProtocol.Reply) {
        StubStreamProtocol.reply.withLock { $0 = reply }
        StubStreamProtocol.requests.withLock { $0.removeAll() }
    }

    @Test func `one request, with the streaming headers, and no probe`() async {
        prepare(.init(headers: ["Content-Type": "audio/aacp", "Server": "x", "Date": "y"], chunks: [Data([1, 2, 3])]))
        let queue = DispatchQueue(label: "test.source")
        let delegate = RecordingSourceDelegate()
        let source = makeSource(queue: queue)
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { delegate.endOfFile.withLock { $0 } }

        let requests = StubStreamProtocol.requests.withLock { $0 }
        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Icy-MetaData") == "1")
        #expect(requests.first?.value(forHTTPHeaderField: "Range") == nil)
        #expect(source.audioFileHint == kAudioFileAAC_ADTSType)
        #expect(delegate.audio.withLock { $0 } == Data([1, 2, 3]))
    }

    @Test func `audio and titles reach the player on its queue`() async {
        var block = Data("StreamTitle='Artist - Song';".utf8)
        block.append(Data(count: 32 - block.count))
        let body = Data([1, 2, 3, 4]) + Data([2]) + block + Data([5, 6])
        prepare(.init(headers: ["Content-Type": "audio/mpeg", "icy-metaint": "4", "Server": "x"], chunks: [body]))
        let queue = DispatchQueue(label: "test.source")
        let delegate = RecordingSourceDelegate()
        delegate.expectedQueue = queue
        let source = makeSource(queue: queue)
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { delegate.endOfFile.withLock { $0 } }

        #expect(delegate.audio.withLock { $0 } == Data([1, 2, 3, 4, 5, 6]))
        #expect(delegate.titles.withLock { $0 } == ["Artist - Song"])
        #expect(delegate.wrongQueue.withLock { $0 } == false)
    }

    @Test(arguments: [
        StubStreamProtocol.Reply(headers: headers("audio/mp4"), chunks: [Data([1])]),
        StubStreamProtocol.Reply(status: 404, headers: ["Server": "x", "Date": "y", "A": "b"]),
        StubStreamProtocol.Reply(headers: headers("audio/mpeg"), failure: .timedOut),
    ])
    func `MP4, an HTTP error, or a failure before audio hands the stream back once`(
        reply: StubStreamProtocol.Reply,
    ) async {
        prepare(reply)
        let fallbacks = FallbackCounter()
        let delegate = RecordingSourceDelegate()
        let source = makeSource(queue: DispatchQueue(label: "test.source"), fallbacks: fallbacks)
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { fallbacks.count.withLock { $0 } > 0 }

        #expect(fallbacks.count.withLock { $0 } == 1)
        #expect(delegate.audio.withLock { $0 }.isEmpty)
        #expect(delegate.errors.withLock { $0 } == 0)
    }

    @Test func `a failure after audio goes to the player, not the fallback`() async {
        prepare(.init(headers: headers("audio/mpeg"), chunks: [Data([1, 2])], failure: .networkConnectionLost))
        let fallbacks = FallbackCounter()
        let delegate = RecordingSourceDelegate()
        let source = makeSource(queue: DispatchQueue(label: "test.source"), fallbacks: fallbacks)
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { delegate.errors.withLock { $0 } > 0 }

        #expect(delegate.errors.withLock { $0 } == 1)
        #expect(fallbacks.count.withLock { $0 } == 0)
    }

    /// Two response headers is the old-Shoutcast signal that the real headers
    /// are at the start of the body. A body chunk smaller than that block used
    /// to be played as audio.
    @Test func `an ICY header split across body chunks is not delivered as audio`() async {
        let header = Data("ICY 200 OK\r\nicy-metaint: 8192\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        let audio = Data([1, 2, 3])
        prepare(.init(
            headers: ["Server": "old", "Date": "y"],
            chunks: [Data(header.prefix(8)), Data(header.dropFirst(8)) + audio],
        ))
        let delegate = RecordingSourceDelegate()
        let source = makeSource(queue: DispatchQueue(label: "test.source.split"))
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { delegate.endOfFile.withLock { $0 } }

        #expect(delegate.audio.withLock { $0 } == audio)
    }

    @Test func `a short body that might be a header is delivered when the stream ends`() async {
        let body = Data("IC".utf8)
        prepare(.init(headers: ["Server": "old", "Date": "y"], chunks: [body]))
        let delegate = RecordingSourceDelegate()
        let source = makeSource(queue: DispatchQueue(label: "test.source.short"))
        source.delegate = delegate
        source.seek(at: 0)
        await eventually { delegate.endOfFile.withLock { $0 } }

        #expect(delegate.audio.withLock { $0 } == body)
        #expect(delegate.endOfFile.withLock { $0 })
    }
}
