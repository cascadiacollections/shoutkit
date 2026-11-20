import Foundation
@testable import RadioDirectory
import Testing

/// `RadioDirectoryError` is the package's whole error vocabulary, and its three
/// mappings are what the UI reads instead of switching on cases. These pin the
/// grouping so a new case, or a case moved between groups, is a visible change.
struct RadioDirectoryErrorTests {
    static let networkLike: [RadioDirectoryError] = [.transport(nil), .transport("offline")]
    static let unavailable: [RadioDirectoryError] = [.emptyPlaylist, .httpStatus(503), .invalidResponse]
    static let configuration: [RadioDirectoryError] = [.invalidURL, .missingAPIKey, .parsingFailed("bad")]

    @Test(arguments: networkLike + unavailable)
    func `transient failures are retryable`(error: RadioDirectoryError) {
        #expect(error.isRetryable)
    }

    @Test(arguments: configuration)
    func `permanent failures are not retryable`(error: RadioDirectoryError) {
        #expect(error.isRetryable == false)
    }

    @Test(arguments: networkLike)
    func `network failures ask the listener to check their connection`(error: RadioDirectoryError) {
        #expect(error.userMessage == "Can't reach the station. Check your connection.")
        #expect(error.shortUserMessage == "No connection")
    }

    @Test(arguments: unavailable)
    func `server side failures say the station is unavailable`(error: RadioDirectoryError) {
        #expect(error.userMessage == "The station isn't available right now.")
        #expect(error.shortUserMessage == "Unavailable")
    }

    @Test(arguments: configuration)
    func `configuration failures say so`(error: RadioDirectoryError) {
        #expect(error.userMessage == "The station has a configuration problem.")
        #expect(error.shortUserMessage == "Station error")
    }

    @Test
    func `descriptions name each failure`() {
        #expect(RadioDirectoryError.emptyPlaylist.errorDescription == "The station did not return a playable stream.")
        #expect(RadioDirectoryError.httpStatus(503).errorDescription == "The station directory returned HTTP 503.")
        #expect(
            RadioDirectoryError.invalidResponse.errorDescription
                == "The station directory returned an invalid response.",
        )
        #expect(RadioDirectoryError.invalidURL.errorDescription == "The station directory URL could not be built.")
    }

    @Test
    func `missing key description does not leak the build setting`() throws {
        let description = try #require(RadioDirectoryError.missingAPIKey.errorDescription)

        #expect(description == "Live stations are unavailable right now.")
        #expect(description.contains("SHOUTCAST") == false)
    }

    @Test
    func `payload descriptions pass through`() {
        #expect(RadioDirectoryError.parsingFailed("Unexpected token").errorDescription == "Unexpected token")
        #expect(RadioDirectoryError.transport("The request timed out.").errorDescription == "The request timed out.")
    }

    @Test
    func `transport without a message falls back to a connection hint`() {
        #expect(
            RadioDirectoryError.transport(nil).errorDescription
                == "The station directory could not be reached. Check your connection.",
        )
    }

    @Test
    func `localized description comes from the error description`() {
        let error: any Error = RadioDirectoryError.httpStatus(404)

        #expect(error.localizedDescription == "The station directory returned HTTP 404.")
    }
}
