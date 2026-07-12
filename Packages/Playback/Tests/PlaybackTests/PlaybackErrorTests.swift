import Foundation
import RadioDirectory
import Testing

@testable import Playback

struct PlaybackErrorTests {
    // MARK: - userMessage

    @Test func noInternetUserMessage() {
        #expect(
            PlaybackError.noInternet.userMessage
                == "No internet connection. Check your network and try again."
        )
    }

    @Test func stationNotAvailableUserMessage() {
        #expect(
            PlaybackError.stationNotAvailable(errorCode: 404).userMessage
                == "This station isn't available right now. Try again later."
        )
    }

    @Test func streamFailedUserMessage() {
        #expect(
            PlaybackError.streamFailed("AVFoundation error").userMessage
                == "The stream stopped unexpectedly. Tap to retry."
        )
    }

    @Test func directoryTransportUserMessage() {
        #expect(
            PlaybackError.directory(.transport(nil)).userMessage
                == "Can't reach the station. Check your connection."
        )
    }

    @Test func directoryEmptyPlaylistUserMessage() {
        #expect(
            PlaybackError.directory(.emptyPlaylist).userMessage
                == "The station isn't available right now."
        )
    }

    @Test func directoryHttpStatusUserMessage() {
        #expect(
            PlaybackError.directory(.httpStatus(503)).userMessage
                == "The station isn't available right now."
        )
    }

    @Test func directoryConfigurationProblemUserMessage() {
        #expect(
            PlaybackError.directory(.invalidURL).userMessage
                == "The station has a configuration problem."
        )
    }

    // MARK: - shortUserMessage

    @Test func noInternetShortUserMessage() {
        #expect(PlaybackError.noInternet.shortUserMessage == "No connection")
    }

    @Test func stationNotAvailableShortUserMessage() {
        #expect(PlaybackError.stationNotAvailable(errorCode: 404).shortUserMessage == "Unavailable")
    }

    @Test func streamFailedShortUserMessage() {
        #expect(PlaybackError.streamFailed("AVFoundation error").shortUserMessage == "Stream error")
    }

    @Test func directoryTransportShortUserMessage() {
        #expect(PlaybackError.directory(.transport(nil)).shortUserMessage == "No connection")
    }

    @Test func directoryUnavailableShortUserMessage() {
        #expect(PlaybackError.directory(.emptyPlaylist).shortUserMessage == "Unavailable")
        #expect(PlaybackError.directory(.httpStatus(503)).shortUserMessage == "Unavailable")
        #expect(PlaybackError.directory(.invalidResponse).shortUserMessage == "Unavailable")
    }

    @Test func directoryConfigurationShortUserMessage() {
        #expect(PlaybackError.directory(.invalidURL).shortUserMessage == "Station error")
        #expect(PlaybackError.directory(.missingAPIKey).shortUserMessage == "Station error")
        #expect(PlaybackError.directory(.parsingFailed("msg")).shortUserMessage == "Station error")
    }

    // MARK: - isRetryable

    @Test func noInternetIsRetryable() {
        #expect(PlaybackError.noInternet.isRetryable == true)
    }

    @Test func stationNotAvailableIsNotRetryable() {
        #expect(PlaybackError.stationNotAvailable(errorCode: 404).isRetryable == false)
    }

    @Test func streamFailedIsRetryable() {
        #expect(PlaybackError.streamFailed("AVFoundation error").isRetryable == true)
    }
}
