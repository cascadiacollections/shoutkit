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

    private var collected = Data(capacity: 1024)
    private var searchComplete = false

    /// The header block, if `data` completes one, and the bytes after it. Data
    /// that doesn't start with `ICY ` or `HTTP` is passed through untouched.
    mutating func process(_ data: Data) -> (fields: Fields?, remainder: Data) {
        guard searchComplete == false, data.isEmpty == false else { return (nil, data) }
        let terminators: [[UInt8]] = [Array("\n\n".utf8), Array("\r\n\r\n".utf8)]
        let prefixes: [[UInt8]] = [Array("ICY ".utf8), Array("HTTP".utf8)]
        var found = false
        var consumed = 0

        for byte in data {
            collected.append(byte)
            consumed += 1
            if terminators.contains(where: { collected.suffix($0.count).elementsEqual($0) }) {
                found = true
                searchComplete = true
                break
            }
            if collected.count >= 4, prefixes.contains(where: { collected.prefix(4).elementsEqual($0) }) == false {
                searchComplete = true
                break
            }
        }

        guard found else {
            // Not a header block, or not complete yet. The original passed the
            // whole chunk on in both cases; incomplete header blocks spanning
            // chunks are rare enough that it never handled them either.
            return (nil, data)
        }
        return (Self.parse(collected), Data(data.dropFirst(consumed)))
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
