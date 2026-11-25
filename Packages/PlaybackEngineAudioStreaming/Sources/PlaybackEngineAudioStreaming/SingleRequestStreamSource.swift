import AudioStreaming
import AudioToolbox
import Foundation
import Synchronization

/// A live-stream source that opens **one** HTTP request.
///
/// AudioStreaming's own `RemoteAudioSource` opens every stream from offset 0
/// with a probe first (`Range: bytes=0-1`, to detect MP4), then cancels it and
/// requests the stream again. A live server ignores the range and starts
/// streaming, so cancelling discards that connection, and the second request
/// pays for TCP, TLS and the server's own first-byte delay a second time: about
/// 1.4 s of a ~3.4 s tap-to-audio on KEXP (DECISIONS.md, 2026-11-14).
///
/// This source goes through the player's public `play(source:entryId:format:)`,
/// so decoding, buffering, rendering and the engine's taps are untouched. It
/// does what the probe was for from the real response: `Content-Type` gives the
/// parser its file-type hint, which AudioStreaming reads lazily at the first
/// `dataAvailable`, and an MP4-family response, which needs AudioStreaming's
/// restructuring path, triggers `onFallback` instead of being played.
///
/// `onFallback` also fires when the request fails before any audio arrived, so
/// the engine can retry once through `play(url:)`. After the first audio byte,
/// failures go to the player as usual and the controller's reconnect owns them.
final class SingleRequestStreamSource: NSObject, CoreAudioStreamSource, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case httpStatus(Int)
    }

    /// Set by `AudioEntry`. Weak, as `RemoteAudioSource` keeps it.
    weak var delegate: AudioStreamSourceDelegate?

    let underlyingQueue: DispatchQueue

    private let url: URL
    private let configuration: URLSessionConfiguration
    private let onFallback: @Sendable () -> Void
    private let state = Mutex(State())

    private struct State {
        var session: URLSession?
        var task: URLSessionDataTask?
        var fileHint: AudioFileTypeID = 0
        var demuxer = ICYMetadataDemuxer()
        var inBodyHeaders: ICYInBodyHeaders?
        var bytesDelivered = 0
        var hasDeliveredAudio = false
        var isSuspended = false
        var pending: [Data] = []
        var didFallBack = false
        var isClosed = false
    }

    /// Whether this source should handle `url`: http(s), and not a file
    /// extension that is MP4 family, which only `play(url:)` can restructure.
    static func canStream(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return AudioStreamFileType.isMP4Family(AudioStreamFileType.from(fileExtension: url.pathExtension)) == false
    }

    /// AudioStreaming's own session settings for streaming (`NetworkingClient`),
    /// minus `shouldUseExtendedBackgroundIdleMode`, deprecated as "Not
    /// supported" since iOS 18.4.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    init(
        url: URL,
        underlyingQueue: DispatchQueue,
        configuration: URLSessionConfiguration = SingleRequestStreamSource.makeConfiguration(),
        onFallback: @escaping @Sendable () -> Void,
    ) {
        self.url = url
        self.underlyingQueue = underlyingQueue
        self.configuration = configuration
        self.onFallback = onFallback
        super.init()
    }

    // MARK: - CoreAudioStreamSource

    var position: Int {
        state.withLock { $0.bytesDelivered }
    }

    /// Live streams have no length; 0 is what `RemoteAudioSource` reports too.
    var length: Int {
        0
    }

    var audioFileHint: AudioFileTypeID {
        let hint = state.withLock { $0.fileHint }
        if hint != 0 {
            return hint
        }
        let byExtension = AudioStreamFileType.from(fileExtension: url.pathExtension)
        return byExtension != 0 ? byExtension : kAudioFileMP3Type
    }

    /// Opens (or reopens) the stream. Live streams can't seek, so the offset is
    /// ignored and the request always starts at the live edge.
    func seek(at _: Int) {
        let request = makeRequest()
        let queue = OperationQueue()
        queue.underlyingQueue = underlyingQueue
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: request)

        let previous = state.withLock { state -> (URLSession?, URLSessionDataTask?) in
            let old = (state.session, state.task)
            state = State()
            state.session = session
            state.task = task
            return old
        }
        previous.1?.cancel()
        previous.0?.invalidateAndCancel()
        task.resume()
    }

    func close() {
        let (session, task) = state.withLock { state -> (URLSession?, URLSessionDataTask?) in
            state.isClosed = true
            state.pending.removeAll()
            defer {
                state.session = nil
                state.task = nil
            }
            return (state.session, state.task)
        }
        task?.cancel()
        session?.invalidateAndCancel()
    }

    /// Backpressure from the player when its buffer is full: stop reading, and
    /// hold anything already in flight until `resume()`.
    func suspend() {
        let task = state.withLock { state -> URLSessionDataTask? in
            state.isSuspended = true
            return state.task
        }
        task?.suspend()
    }

    func resume() {
        let task = state.withLock { state -> URLSessionDataTask? in
            state.isSuspended = false
            return state.task
        }
        underlyingQueue.async { [weak self] in
            self?.flushPending()
        }
        task?.resume()
    }

    // MARK: - Private

    private func makeRequest() -> URLRequest {
        // Matches RemoteAudioSource.buildUrlRequest, minus the probe.
        var request = URLRequest(url: url)
        request.networkServiceType = .avStreaming
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        request.addValue("*/*", forHTTPHeaderField: "Accept")
        request.addValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.addValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private func isCurrent(_ task: URLSessionTask) -> Bool {
        state.withLock { $0.task === task && $0.isClosed == false }
    }

    /// Hands the stream back to the engine once, and stops this source.
    private func fallBack() {
        let shouldFire = state.withLock { state -> Bool in
            guard state.didFallBack == false else { return false }
            state.didFallBack = true
            return true
        }
        guard shouldFire else { return }
        close()
        onFallback()
    }

    private func flushPending() {
        let chunks = state.withLock { state -> [Data] in
            guard state.isSuspended == false else { return [] }
            defer { state.pending.removeAll() }
            return state.pending
        }
        for chunk in chunks {
            deliver(chunk)
        }
    }

    /// Strips in-body ICY headers and metadata, then passes the audio on.
    /// Always on `underlyingQueue`, where AudioStreaming expects source callbacks.
    private func deliver(_ data: Data) {
        let (audio, metadata) = state.withLock { state -> (Data, [[String: String]]) in
            var remainder = data
            if var reader = state.inBodyHeaders {
                let result = reader.process(data)
                remainder = result.remainder
                if let fields = result.fields {
                    state.inBodyHeaders = nil
                    state.demuxer.setMetadataStep(fields.metadataStep)
                    if state.fileHint == 0 {
                        state.fileHint = fields.fileType
                    }
                } else if reader.isFinished {
                    // Not a header, or the block overran the cap. Drop the
                    // reader so later audio chunks skip it.
                    state.inBodyHeaders = nil
                } else {
                    state.inBodyHeaders = reader
                }
            }
            let split = state.demuxer.process(remainder)
            state.bytesDelivered += split.audio.count
            if split.audio.isEmpty == false {
                state.hasDeliveredAudio = true
            }
            return (split.audio, split.metadata)
        }
        guard let delegate else {
            // The player that owned this source is gone; stop streaming.
            close()
            return
        }
        for fields in metadata {
            delegate.metadataReceived(data: fields)
        }
        if audio.isEmpty == false {
            delegate.dataAvailable(source: self, data: audio)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension SingleRequestStreamSource: URLSessionDataDelegate {
    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void,
    ) {
        guard isCurrent(dataTask) else {
            completionHandler(.cancel)
            return
        }
        let http = response as? HTTPURLResponse
        if let http, http.statusCode >= 300 {
            completionHandler(.cancel)
            fallBack()
            return
        }

        let hint = response.mimeType.map(AudioStreamFileType.from(mimeType:)) ?? 0
        if AudioStreamFileType.isMP4Family(hint) {
            completionHandler(.cancel)
            fallBack()
            return
        }

        let metaint = http?.value(forHTTPHeaderField: "icy-metaint").flatMap { Int($0) } ?? 0
        // Same rule as AudioStreaming's HTTPHeaderParser: a response with two
        // headers or fewer is an old Shoutcast server, whose real headers are
        // at the start of the body.
        let headerCount = http?.allHeaderFields.count ?? 0
        state.withLock { state in
            state.fileHint = hint
            state.demuxer.setMetadataStep(metaint)
            state.inBodyHeaders = headerCount > 2 ? nil : ICYInBodyHeaders()
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard isCurrent(dataTask) else { return }
        let held = state.withLock { state -> Bool in
            guard state.isSuspended else { return false }
            state.pending.append(data)
            return true
        }
        if held == false {
            deliver(data)
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard isCurrent(task) else { return }
        // A body shorter than the header prefix ("IC", "HT") is held until the
        // next bytes prove what it is. The connection ending is that proof:
        // hand the bytes on, or a tiny response is dropped and a longer one
        // that died mid-header loses the audio already withheld.
        let undecided = state.withLock { state -> Data in
            guard var reader = state.inBodyHeaders else { return Data() }
            let buffered = reader.takeBuffered()
            state.inBodyHeaders = nil
            return buffered
        }
        if undecided.isEmpty == false {
            deliver(undecided)
        }
        let deliveredAudio = state.withLock { $0.hasDeliveredAudio }
        if let error {
            if (error as? URLError)?.code == .cancelled {
                return
            }
            if deliveredAudio == false {
                fallBack()
                return
            }
            delegate?.errorOccurred(source: self, error: error)
        } else {
            delegate?.endOfFileOccurred(source: self)
        }
    }
}
