import Foundation
import Testing

// Deliberately not `@testable`: this exercises `PlaybackError.classifying` as the
// public API it is. It became public so the engine could move to the iOS-only
// `PlaybackEngineAudioStreaming` package (#122) while the classification table
// stayed here — which means the mapping is now a cross-package contract, and a
// plain `import` is what proves it is reachable as one.
import Playback

struct PlaybackErrorClassificationTests {
    @Test func noInternetURLErrorMapsToNoInternet() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.notConnectedToInternet.rawValue
        )

        #expect(PlaybackError.classifying(error) == .noInternet)
    }

    @Test func missingResourceMapsToStationNotAvailableCarryingItsCode() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.resourceUnavailable.rawValue
        )

        #expect(
            PlaybackError.classifying(error)
                == .stationNotAvailable(errorCode: URLError.Code.resourceUnavailable.rawValue)
        )
    }

    @Test func unrecognizedErrorsBecomeStreamFailedWithTheirDescription() {
        let error = NSError(
            domain: "AudioStreamingErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The stream could not be opened."]
        )

        #expect(
            PlaybackError.classifying(error) == .streamFailed("The stream could not be opened.")
        )
    }

    /// `.stationNotAvailable` is the one classification the bounded auto-reconnect
    /// must *not* retry — a 404 does not become a 200 on the third attempt. Worth
    /// asserting alongside the mapping, since the mapping is what decides it.
    @Test func retryabilityFollowsTheClassification() {
        let gone = NSError(domain: NSURLErrorDomain, code: URLError.Code.fileDoesNotExist.rawValue)
        let offline = NSError(domain: NSURLErrorDomain, code: URLError.Code.notConnectedToInternet.rawValue)

        #expect(PlaybackError.classifying(gone).isRetryable == false)
        #expect(PlaybackError.classifying(offline).isRetryable)
    }
}
