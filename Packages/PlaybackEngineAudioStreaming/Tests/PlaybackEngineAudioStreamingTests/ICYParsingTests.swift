import AudioToolbox
import Foundation
@testable import PlaybackEngineAudioStreaming
import Testing

/// Builds an ICY stream: `audio` cut every `step` bytes, with `titles` as the
/// metadata blocks (an empty title becomes a zero-length block).
private func icyStream(step: Int, audio: Data, titles: [String]) -> Data {
    var out = Data()
    var offset = 0
    var titleIndex = 0
    // As a server sends it: after every `step` audio bytes comes a length
    // byte, zero when there is no title this interval.
    while offset < audio.count {
        let end = min(offset + step, audio.count)
        out.append(audio[offset ..< end])
        offset = end
        guard offset % step == 0 else { continue }
        let title = titleIndex < titles.count ? titles[titleIndex] : ""
        titleIndex += 1
        if title.isEmpty {
            out.append(0)
        } else {
            var block = Data("StreamTitle='\(title)';".utf8)
            let padded = (block.count + 15) / 16 * 16
            block.append(Data(count: padded - block.count))
            out.append(UInt8(padded / 16))
            out.append(block)
        }
    }
    return out
}

struct ICYMetadataDemuxerTests {
    private let audio = Data((0 ..< 64).map { UInt8($0) })

    @Test func `without a metaint, data passes through untouched`() {
        var demuxer = ICYMetadataDemuxer()
        let result = demuxer.process(audio)
        #expect(result.audio == audio)
        #expect(result.metadata.isEmpty)
    }

    @Test func `audio and metadata separate, whatever the chunking`() {
        let stream = icyStream(step: 16, audio: audio, titles: ["Artist - One", "", "Artist - Two"])
        for chunkSize in [1, 3, 7, 16, 17, stream.count] {
            var demuxer = ICYMetadataDemuxer()
            demuxer.setMetadataStep(16)
            var gotAudio = Data()
            var titles: [String] = []
            var offset = 0
            while offset < stream.count {
                let end = min(offset + chunkSize, stream.count)
                let result = demuxer.process(stream[offset ..< end])
                gotAudio.append(result.audio)
                titles += result.metadata.compactMap { $0["StreamTitle"] }
                offset = end
            }
            #expect(gotAudio == audio, "chunk size \(chunkSize)")
            #expect(titles == ["Artist - One", "Artist - Two"], "chunk size \(chunkSize)")
        }
    }

    @Test func `titles may contain equals signs`() {
        let fields = ICYMetadataDemuxer.parse(Data("StreamTitle='A=B - C';StreamUrl='';\0\0".utf8))
        #expect(fields?["StreamTitle"] == "A=B - C")
    }

    /// KEXP sends Latin-1: "Kælan Mikla - Sólstöður" showed as "K�lan Mikla - S�lst��ur".
    @Test func `latin-1 titles decode instead of becoming replacement characters`() throws {
        let block = try #require("StreamTitle='Kælan Mikla - Sólstöður';\0\0".data(using: .isoLatin1))
        #expect(ICYMetadataDemuxer.parse(block)?["StreamTitle"] == "Kælan Mikla - Sólstöður")
    }

    @Test func `UTF-8 titles still decode as UTF-8`() {
        let block = Data("StreamTitle='Kælan Mikla - Sólstöður';\0\0".utf8)
        #expect(ICYMetadataDemuxer.parse(block)?["StreamTitle"] == "Kælan Mikla - Sólstöður")
    }

    @Test func `an empty block parses to nothing`() {
        #expect(ICYMetadataDemuxer.parse(Data(count: 16)) == nil)
    }
}

struct ICYInBodyHeadersTests {
    @Test func `reads an ICY 200 header block and returns the audio after it`() {
        let header = "ICY 200 OK\r\nicy-metaint: 8192\r\ncontent-type: audio/aacp\r\n\r\n"
        let audio = Data([1, 2, 3])
        var reader = ICYInBodyHeaders()
        let result = reader.process(Data(header.utf8) + audio)
        #expect(result.fields == .init(metadataStep: 8192, fileType: kAudioFileAAC_ADTSType))
        #expect(result.remainder == audio)
    }

    @Test func `a body that isn't a header block passes through`() {
        var reader = ICYInBodyHeaders()
        let audio = Data([0xFF, 0xF1, 0x50, 0x80, 0x00])
        let result = reader.process(audio)
        #expect(result.fields == nil)
        #expect(result.remainder == audio)
        #expect(reader.isFinished)
    }

    @Test func `one audio byte is not held while a header is ruled out`() {
        var reader = ICYInBodyHeaders()
        #expect(reader.process(Data([0xFF])).remainder == Data([0xFF]))
        let more = Data([0xF1, 0x50])
        #expect(reader.process(more).remainder == more)
    }

    @Test func `a header split across chunks is assembled, not played`() {
        let header = Data("ICY 200 OK\r\nicy-metaint: 8192\r\ncontent-type: audio/aacp\r\n\r\n".utf8)
        let audio = Data([1, 2, 3])
        let body = header + audio
        var reader = ICYInBodyHeaders()

        let first = reader.process(body.prefix(10))
        #expect(first.fields == nil)
        #expect(first.remainder.isEmpty)

        let second = reader.process(body.dropFirst(10))
        #expect(second.fields == .init(metadataStep: 8192, fileType: kAudioFileAAC_ADTSType))
        #expect(second.remainder == audio)
        #expect(reader.isFinished)
    }

    @Test func `a line-feed blank line ends the block`() {
        let header = Data("ICY 200 OK\nicy-metaint: 16\ncontent-type: audio/mpeg\n\n".utf8)
        let audio = Data([9])
        var reader = ICYInBodyHeaders()
        let result = reader.process(header + audio)
        #expect(result.fields?.metadataStep == 16)
        #expect(result.remainder == audio)
    }

    @Test func `a prefix that is not a header is released with the deciding bytes`() {
        var reader = ICYInBodyHeaders()
        #expect(reader.process(Data("IC".utf8)).remainder.isEmpty)
        #expect(reader.process(Data("X audio".utf8)).remainder == Data("ICX audio".utf8))
    }

    @Test func `a header followed by more than the cap of audio still parses`() {
        let header = Data("ICY 200 OK\r\nicy-metaint: 16000\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        let audio = Data(repeating: 0xFF, count: ICYInBodyHeaders.maximumHeaderBytes)
        var reader = ICYInBodyHeaders()
        let result = reader.process(header + audio)
        #expect(result.fields?.metadataStep == 16000)
        #expect(result.remainder == audio)
    }

    @Test func `a block that never ends is released, and later audio is not retained`() {
        var reader = ICYInBodyHeaders()
        #expect(reader.process(Data("ICY ".utf8)).remainder.isEmpty)

        let chunk = Data(repeating: 0x11, count: 1024)
        var released = Data()
        for _ in 0 ..< 20 {
            let result = reader.process(chunk)
            if result.remainder.isEmpty == false {
                released = result.remainder
                break
            }
        }

        #expect(released.isEmpty == false)
        #expect(released.count <= ICYInBodyHeaders.maximumHeaderBytes + chunk.count)
        #expect(reader.isFinished)
        let tail = Data([1, 2, 3, 4])
        let next = reader.process(tail)
        #expect(next.fields == nil)
        #expect(next.remainder == tail)
    }

    @Test func `bytes held when the stream ends can be flushed`() {
        var reader = ICYInBodyHeaders()
        #expect(reader.process(Data("HT".utf8)).remainder.isEmpty)
        #expect(reader.takeBuffered() == Data("HT".utf8))
        #expect(reader.takeBuffered().isEmpty)
        #expect(reader.isFinished)
    }
}

struct AudioStreamFileTypeTests {
    @Test(arguments: [
        ("audio/aacp", kAudioFileAAC_ADTSType),
        ("audio/mpeg", kAudioFileMP3Type),
        ("Audio/MPEG; charset=utf-8", kAudioFileMP3Type),
        ("application/ogg", AudioStreamFileType.ogg),
        ("audio/mp4", kAudioFileMPEG4Type),
        ("text/html", 0),
    ])
    func `MIME types map like AudioStreaming's table`(mime: String, expected: AudioFileTypeID) {
        #expect(AudioStreamFileType.from(mimeType: mime) == expected)
    }

    /// Must equal AudioStreaming's internal `kAudioFileOggType`, or Ogg streams
    /// would go to Core Audio's parser instead of the Vorbis decoder.
    @Test func `the Ogg hint matches AudioStreaming's`() {
        #expect(AudioStreamFileType.ogg == 0x6F67_6720)
    }

    @Test func `only http(s) URLs that aren't MP4 files use the single-request source`() throws {
        let kexp = try #require(URL(string: "https://kexp.streamguys1.com/kexp160.aac"))
        #expect(SingleRequestStreamSource.canStream(kexp))
        #expect(try SingleRequestStreamSource.canStream(#require(URL(string: "http://example.com/stream"))))
        #expect(try SingleRequestStreamSource.canStream(#require(URL(string: "https://example.com/show.m4a"))) == false)
        #expect(try SingleRequestStreamSource.canStream(#require(URL(string: "file:///tmp/a.mp3"))) == false)
    }
}
