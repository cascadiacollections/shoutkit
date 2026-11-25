//
//  Adapted from AudioStreaming 1.4.5 (MIT), `IcycastHeadersProcessor.swift` and
//  `IcycastHeaderParser.swift`, which are `internal` there (DECISIONS.md,
//  2026-11-14). Changes: one value type, returning the parsed fields directly.
//
//  Original: Created by Dimitrios C on 14/02/2021.
//  Copyright © 2021 Decimal. All rights reserved.
//  Copyright (c) 2020 Dimitris C. Copyright (c) 2012-2014 Thong Nguyen.
//

import AudioToolbox
import Foundation

/// Old Shoutcast servers answer `ICY 200 OK` and put their headers at the start
/// of the body instead of in the HTTP response:
/// ```
/// ICY 200 OK
/// icy-metaint: 16000
/// content-type: audio/mpeg
///
/// <audio…>
/// ```
/// This reads them off the front of the stream and hands back what follows.
struct ICYInBodyHeaders {
    struct Fields: Equatable {
        let metadataStep: Int
        let fileType: AudioFileTypeID
    }

    /// Real ICY status blocks are a few hundred bytes. Past this the body is
    /// not a header, and holding it would pin the rest of the listening
    /// session: a stream that starts with `ICY ` or `HTTP` and never sends a
    /// blank line used to append every later byte.
    static let maximumHeaderBytes = 8 * 1024

    private static let icyPrefix = Data("ICY ".utf8)
    private static let httpPrefix = Data("HTTP".utf8)
    private static let crlfBlank = Data("\r\n\r\n".utf8)
    private static let lfBlank = Data("\n\n".utf8)

    private var collected = Data(capacity: 1024)
    private var searchComplete = false

    /// True once this reader will not hold further bytes. The stream source
    /// drops it then, instead of consulting it for the rest of the session.
    var isFinished: Bool {
        searchComplete
    }

    /// The header block, if `data` completes one, and the bytes after it.
    ///
    /// Bytes that might still be a header stay here until the block ends or
    /// it is clearly audio. `URLSession` delivers the body in whatever sizes
    /// it likes, so a block split across callbacks has to be assembled: the
    /// previous version played the first piece as audio and, when the blank
    /// line never arrived, retained every byte after it for the session.
    /// Audio that cannot be a header is returned immediately, including a
    /// single byte, so a normal stream is not delayed.
    mutating func process(_ data: Data) -> (fields: Fields?, remainder: Data) {
        guard searchComplete == false, data.isEmpty == false else { return (nil, data) }
        collected.append(data)
        switch Self.classification(of: collected) {
        case .needMore:
            return (nil, Data())
        case .notHeader:
            return passThrough()
        case .header:
            break
        }
        if let end = Self.headerEnd(in: collected) {
            searchComplete = true
            let header = Data(collected.prefix(end))
            let remainder = Data(collected.dropFirst(end))
            collected = Data()
            return (Self.parse(header), remainder)
        }
        guard collected.count <= Self.maximumHeaderBytes else { return passThrough() }
        return (nil, Data())
    }

    /// Bytes held while a block is still undecided. The stream source flushes
    /// these if the connection ends first, so a short body is not dropped.
    mutating func takeBuffered() -> Data {
        guard searchComplete == false else { return Data() }
        return passThrough().remainder
    }

    private mutating func passThrough() -> (fields: Fields?, remainder: Data) {
        searchComplete = true
        let remainder = collected
        collected = Data()
        return (nil, remainder)
    }

    private enum Classification {
        case needMore
        case header
        case notHeader
    }

    /// `ICY ` / `HTTP` means keep reading the block. A shorter prefix of
    /// either might still become one. Anything else is audio.
    private static func classification(of data: Data) -> Classification {
        if data.starts(with: icyPrefix) || data.starts(with: httpPrefix) {
            return .header
        }
        if icyPrefix.starts(with: data) || httpPrefix.starts(with: data) {
            return .needMore
        }
        return .notHeader
    }

    /// Index just past the blank line that ends the block, whichever line
    /// ending arrives first.
    private static func headerEnd(in data: Data) -> Int? {
        let crlf = data.range(of: crlfBlank)?.upperBound
        let lf = data.range(of: lfBlank)?.upperBound
        switch (crlf, lf) {
        case let (.some(crlfEnd), .some(lfEnd)):
            return min(crlfEnd, lfEnd)
        case let (.some(end), .none), let (.none, .some(end)):
            return end
        case (.none, .none):
            return nil
        }
    }

    static func parse(_ block: Data) -> Fields? {
        let text = ICYText.decode(block)
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\r\n")) where line.isEmpty == false {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            if let key = parts.first, let value = parts.last {
                fields[key.lowercased()] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        let step = Int(fields["icy-metaint"] ?? "") ?? 0
        let contentType = fields["content-type"] ?? "audio/mpeg"
        return Fields(metadataStep: step, fileType: AudioStreamFileType.from(mimeType: contentType))
    }
}
