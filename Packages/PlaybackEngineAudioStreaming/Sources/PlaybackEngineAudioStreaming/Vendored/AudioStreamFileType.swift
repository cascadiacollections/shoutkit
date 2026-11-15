//
//  Adapted from AudioStreaming 1.4.5 (MIT), `AudioFileType.swift`, whose
//  lookup functions are `internal` there (DECISIONS.md, 2026-11-14). Changes:
//  namespaced, and the MIME type's parameters (`; charset=…`) are ignored.
//
//  Copyright (c) 2020 Dimitris C. Copyright (c) 2012-2014 Thong Nguyen.
//

import AudioToolbox
import Foundation

/// MIME type or file extension → the `AudioFileTypeID` hint the parser opens
/// the stream with. 0 means unknown, as in the original.
enum AudioStreamFileType {
    /// AudioStreaming's own Ogg type, `'ogg '`. It isn't an AudioToolbox constant:
    /// the library defines it, internally, and switches to its Vorbis decoder on
    /// exactly this value, so it must match `AudioFileType.swift:11` there.
    static let ogg: AudioFileTypeID = 0x6F67_6720

    static func from(mimeType: String) -> AudioFileTypeID {
        let bare = mimeType.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return byMimeType[bare] ?? 0
    }

    static func from(fileExtension: String) -> AudioFileTypeID {
        byExtension[fileExtension.lowercased()] ?? 0
    }

    /// MP4-family containers need AudioStreaming's own restructuring path,
    /// which only `play(url:)` takes.
    static func isMP4Family(_ type: AudioFileTypeID) -> Bool {
        type == kAudioFileMPEG4Type || type == kAudioFileM4AType
    }

    private static let byMimeType: [String: AudioFileTypeID] = [
        "audio/mp3": kAudioFileMP3Type,
        "audio/mpg": kAudioFileMP3Type,
        "audio/mpeg": kAudioFileMP3Type,
        "audio/wav": kAudioFileWAVEType,
        "audio/x-wav": kAudioFileWAVEType,
        "audio/vnd.wav": kAudioFileWAVEType,
        "audio/aifc": kAudioFileAIFCType,
        "audio/aiff": kAudioFileAIFFType,
        "audio/x-m4a": kAudioFileM4AType,
        "audio/x-mp4": kAudioFileMPEG4Type,
        "audio/m4a": kAudioFileM4AType,
        "audio/mp4": kAudioFileMPEG4Type,
        "video/mp4": kAudioFileMPEG4Type,
        "audio/caf": kAudioFileCAFType,
        "audio/x-caf": kAudioFileCAFType,
        "audio/aac": kAudioFileAAC_ADTSType,
        "audio/aacp": kAudioFileAAC_ADTSType,
        "audio/ac3": kAudioFileAC3Type,
        "audio/3gp": kAudioFile3GPType,
        "video/3gp": kAudioFile3GPType,
        "audio/3gpp": kAudioFile3GPType,
        "video/3gpp": kAudioFile3GPType,
        "audio/3gp2": kAudioFile3GP2Type,
        "video/3gp2": kAudioFile3GP2Type,
        "audio/flac": kAudioFileFLACType,
        "audio/ogg": AudioStreamFileType.ogg,
        "audio/vorbis": AudioStreamFileType.ogg,
        "application/ogg": AudioStreamFileType.ogg,
    ]

    private static let byExtension: [String: AudioFileTypeID] = [
        "mp3": kAudioFileMP3Type,
        "wav": kAudioFileWAVEType,
        "aifc": kAudioFileAIFCType,
        "aiff": kAudioFileAIFFType,
        "m4a": kAudioFileM4AType,
        "mp4": kAudioFileMPEG4Type,
        "caf": kAudioFileCAFType,
        "aac": kAudioFileAAC_ADTSType,
        "ac3": kAudioFileAC3Type,
        "3gp": kAudioFile3GPType,
        "flac": kAudioFileFLACType,
        "ogg": AudioStreamFileType.ogg,
        "oga": AudioStreamFileType.ogg,
    ]
}
