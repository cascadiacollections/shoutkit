import Foundation
@testable import Playback
import Testing

struct PlaybackFailureTests {
    @Test func `known player URL error maps to no internet`() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.notConnectedToInternet.rawValue,
        )

        #expect(PlaybackFailure.classify(playerError: error, itemError: nil) == .noInternet)
    }

    @Test func `known item URL error maps to station not available`() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.fileDoesNotExist.rawValue,
        )

        #expect(
            PlaybackFailure.classify(playerError: nil, itemError: error)
                == .stationNotAvailable(errorCode: URLError.Code.fileDoesNotExist.rawValue),
        )
    }

    @Test func `known URL error wins across player and item sources`() {
        let playerError = NSError(
            domain: "AVFoundationErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The player failed."],
        )
        let itemError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.resourceUnavailable.rawValue,
        )

        #expect(
            PlaybackFailure.classify(playerError: playerError, itemError: itemError)
                == .stationNotAvailable(errorCode: URLError.Code.resourceUnavailable.rawValue),
        )
    }

    @Test func `unknown errors fall back to localized description`() {
        let error = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11800,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed."],
        )

        #expect(
            PlaybackFailure.classify(playerError: error, itemError: nil)
                == .playback(message: "The operation could not be completed."),
        )
    }

    @Test func `unknown errors prefer item description when both sources fail`() {
        let playerError = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11800,
            userInfo: [NSLocalizedDescriptionKey: "The player failed."],
        )
        let itemError = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11819,
            userInfo: [NSLocalizedDescriptionKey: "The item failed."],
        )

        #expect(
            PlaybackFailure.classify(playerError: playerError, itemError: itemError)
                == .playback(message: "The item failed."),
        )
    }
}
