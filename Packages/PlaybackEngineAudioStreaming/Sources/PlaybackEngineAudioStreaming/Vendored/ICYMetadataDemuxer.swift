//
//  Adapted from AudioStreaming 1.4.5 (MIT), `MetadataStreamProcessor.swift` and
//  `MetadataParser.swift`, which are `internal` there and so can't be referenced
//  (DECISIONS.md, 2026-11-14). Changes: a value type with no delegate or
//  `AnyParser`, and parsed metadata returned instead of called back.
//
//  Original: Created by Dimitrios Chatzieleftheriou on 28-29/05/2020.
//  Copyright © 2020 Decimal. All rights reserved.
//  Copyright (c) 2020 Dimitris C. Copyright (c) 2012-2014 Thong Nguyen.
//

import Foundation

/// Splits a Shoutcast/Icecast stream into audio and in-band metadata.
///
/// With `icy-metaint: N`, every N audio bytes are followed by one length byte
/// (×16) and that many bytes of metadata (`StreamTitle='…';`):
/// ```
/// [ audio data ][byte][metadata][ audio data ]
/// ```
/// Reference: the SmackFu Shoutcast write-up, archived at
/// https://web.archive.org/web/20190521203350/https://www.smackfu.com/stuff/programming/shoutcast.html
struct ICYMetadataDemuxer {
    /// Audio bytes between metadata blocks; 0 means the stream carries none.
    private(set) var metadataStep = 0

    private var metadata = Data()
    private var metadataLength = 0
    private var audioBytesRead = 0

    var carriesMetadata: Bool {
        metadataStep > 0
    }

    mutating func setMetadataStep(_ step: Int) {
        metadataStep = max(0, step)
    }

    mutating func reset() {
        metadata = Data()
        metadataLength = 0
        audioBytesRead = 0
    }

    /// Returns the audio in `data`, and every metadata block completed by it.
    /// Blocks and the audio around them may be split across calls.
    mutating func process(_ data: Data) -> (audio: Data, metadata: [[String: String]]) {
        guard carriesMetadata, data.isEmpty == false else { return (data, []) }
        var audio = Data()
        audio.reserveCapacity(data.count)
        var parsed: [[String: String]] = []

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var bytesRead = 0
            while bytesRead < buffer.count {
                let remaining = buffer.count - bytesRead
                let pointer = base + bytesRead
                if metadataLength > 0 {
                    // Inside a metadata block: collect it, parse when complete.
                    let count = min(metadataLength - metadata.count, remaining)
                    metadata.append(pointer, count: count)
                    if metadata.count == metadataLength {
                        if let fields = Self.parse(metadata) {
                            parsed.append(fields)
                        }
                        metadata.removeAll(keepingCapacity: true)
                        metadataLength = 0
                        audioBytesRead = 0
                    }
                    bytesRead += count
                } else if audioBytesRead == metadataStep {
                    // The length byte; zero means no metadata this interval.
                    let length = Int(pointer.pointee) * 16
                    if length > 0 {
                        metadataLength = length
                    } else {
                        audioBytesRead = 0
                    }
                    bytesRead += 1
                } else {
                    let count = min(metadataStep - audioBytesRead, remaining)
                    audio.append(pointer, count: count)
                    audioBytesRead += count
                    bytesRead += count
                }
            }
        }
        return (audio, parsed)
    }

    /// `StreamTitle='Artist - Title';StreamUrl='…';` → `["StreamTitle": "Artist - Title", …]`.
    /// `nil` for undecodable or empty blocks, as the original's `.failure` cases.
    static func parse(_ block: Data) -> [String: String]? {
        let string = ICYText.decode(block)
        let pairs = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).components(separatedBy: ";")
        let fields = pairs.reduce(into: [String: String]()) { result, pair in
            let split = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            if let key = split.first, key.isEmpty == false,
               let value = split.last?.replacingOccurrences(of: "'", with: "") {
                result[key] = value
            }
        }
        return fields.isEmpty ? nil : fields
    }
}
