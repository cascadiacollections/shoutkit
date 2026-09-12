import Foundation
@testable import Playback
import RadioDirectory
import Testing

struct PlaybackErrorTests {
    // MARK: - userMessage

    @Test func `no internet user message`() {
        #expect(
            PlaybackError.noInternet.userMessage
                == "No internet connection. Check your network and try again.",
        )
    }

    @Test func `station not available user message`() {
        #expect(
            PlaybackError.stationNotAvailable(errorCode: 404).userMessage
                == "This station isn't available right now. Try again later.",
        )
    }

    @Test func `stream failed user message`() {
        #expect(
            PlaybackError.streamFailed("AVFoundation error").userMessage
                == "The stream stopped unexpectedly. Tap to retry.",
        )
    }

    @Test func `directory transport user message`() {
        #expect(
            PlaybackError.directory(.transport(nil)).userMessage
                == "Can't reach the station. Check your connection.",
        )
    }

    @Test func `directory empty playlist user message`() {
        #expect(
            PlaybackError.directory(.emptyPlaylist).userMessage
                == "The station isn't available right now.",
        )
    }

    @Test func `directory http status user message`() {
        #expect(
            PlaybackError.directory(.httpStatus(503)).userMessage
                == "The station isn't available right now.",
        )
    }

    @Test func `directory configuration problem user message`() {
        #expect(
            PlaybackError.directory(.invalidURL).userMessage
                == "The station has a configuration problem.",
        )
    }

    // MARK: - shortUserMessage

    @Test func `no internet short user message`() {
        #expect(PlaybackError.noInternet.shortUserMessage == "No connection")
    }

    @Test func `station not available short user message`() {
        #expect(PlaybackError.stationNotAvailable(errorCode: 404).shortUserMessage == "Unavailable")
    }

    @Test func `stream failed short user message`() {
        #expect(PlaybackError.streamFailed("AVFoundation error").shortUserMessage == "Stream error")
    }

    @Test func `directory transport short user message`() {
        #expect(PlaybackError.directory(.transport(nil)).shortUserMessage == "No connection")
    }

    @Test func `directory unavailable short user message`() {
        #expect(PlaybackError.directory(.emptyPlaylist).shortUserMessage == "Unavailable")
        #expect(PlaybackError.directory(.httpStatus(503)).shortUserMessage == "Unavailable")
        #expect(PlaybackError.directory(.invalidResponse).shortUserMessage == "Unavailable")
    }

    @Test func `directory configuration short user message`() {
        #expect(PlaybackError.directory(.invalidURL).shortUserMessage == "Station error")
        #expect(PlaybackError.directory(.missingAPIKey).shortUserMessage == "Station error")
        #expect(PlaybackError.directory(.parsingFailed("msg")).shortUserMessage == "Station error")
    }

    // MARK: - isRetryable

    @Test func `no internet is retryable`() {
        #expect(PlaybackError.noInternet.isRetryable == true)
    }

    @Test func `station not available is not retryable`() {
        #expect(PlaybackError.stationNotAvailable(errorCode: 404).isRetryable == false)
    }

    @Test func `stream failed is retryable`() {
        #expect(PlaybackError.streamFailed("AVFoundation error").isRetryable == true)
    }
}
