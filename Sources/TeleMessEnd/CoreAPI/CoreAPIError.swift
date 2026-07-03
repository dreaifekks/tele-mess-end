import Foundation

enum CoreAPIError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int, String)
    case missingProfile
    case missingToken
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            "Invalid core URL: \(value)"
        case .invalidResponse:
            "Core returned a non-HTTP response."
        case .httpStatus(let status, let message):
            "Core request failed (\(status)): \(message)"
        case .missingProfile:
            "Select or create a core profile first."
        case .missingToken:
            "This profile has no saved API token."
        case .transport(let message):
            message
        }
    }
}
