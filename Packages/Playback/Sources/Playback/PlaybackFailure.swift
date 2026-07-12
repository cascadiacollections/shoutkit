import Foundation

enum PlaybackFailure: Equatable, Sendable {
    case noInternet
    case stationNotAvailable(errorCode: Int)
    case playback(message: String)

    var message: String {
        switch self {
        case .noInternet:
            return "No internet connection."
        case .stationNotAvailable:
            return "This station is not available right now."
        case let .playback(message):
            return message
        }
    }

    static func classify(playerError: (any Error)?, itemError: (any Error)?) -> PlaybackFailure {
        let errors = [playerError, itemError]

        if let classified = errors.lazy.compactMap(classifyKnownURLError).first {
            return classified
        }

        if let error = errors.compactMap({ $0 }).first {
            return .playback(message: error.localizedDescription)
        }

        return .playback(message: "Stream failed to load.")
    }

    private static func classifyKnownURLError(_ error: (any Error)?) -> PlaybackFailure? {
        guard let error, let nsError = error as? NSError, nsError.domain == NSURLErrorDomain else {
            return nil
        }

        switch nsError.code {
        case URLError.Code.notConnectedToInternet.rawValue:
            return .noInternet
        case URLError.Code.resourceUnavailable.rawValue,
             URLError.Code.fileDoesNotExist.rawValue:
            return .stationNotAvailable(errorCode: nsError.code)
        default:
            return nil
        }
    }
}
