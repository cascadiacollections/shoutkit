import Foundation
import Testing

@testable import Playback

struct PlaybackFailureTests {
    @Test func knownPlayerURLErrorMapsToNoInternet() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.notConnectedToInternet.rawValue
        )

        #expect(PlaybackFailure.classify(playerError: error, itemError: nil) == .noInternet)
    }

    @Test func knownItemURLErrorMapsToStationNotAvailable() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.fileDoesNotExist.rawValue
        )

        #expect(
            PlaybackFailure.classify(playerError: nil, itemError: error)
                == .stationNotAvailable(errorCode: URLError.Code.fileDoesNotExist.rawValue)
        )
    }

    @Test func knownURLErrorWinsAcrossPlayerAndItemSources() {
        let playerError = NSError(
            domain: "AVFoundationErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The player failed."]
        )
        let itemError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.resourceUnavailable.rawValue
        )

        #expect(
            PlaybackFailure.classify(playerError: playerError, itemError: itemError)
                == .stationNotAvailable(errorCode: URLError.Code.resourceUnavailable.rawValue)
        )
    }

    @Test func unknownErrorsFallBackToLocalizedDescription() {
        let error = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11800,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed."]
        )

        #expect(
            PlaybackFailure.classify(playerError: error, itemError: nil)
                == .playback(message: "The operation could not be completed.")
        )
    }
}
