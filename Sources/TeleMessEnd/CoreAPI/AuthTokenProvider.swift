import Foundation

protocol AuthTokenProvider: Sendable {
    func token() throws -> String?
}

struct EmptyTokenProvider: AuthTokenProvider {
    func token() throws -> String? { nil }
}

struct FixedTokenProvider: AuthTokenProvider {
    var value: String?

    func token() throws -> String? {
        value
    }
}
