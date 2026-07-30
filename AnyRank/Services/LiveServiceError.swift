import Foundation

/// Shared error type raised by the Live* search services when something
/// goes wrong that we can surface to the UI. Historically this only carried
/// `.notImplemented` for the stubbed-service era; it's now also used by the
/// real TMDB and Places implementations for non-2xx HTTP responses and
/// unexpected empty payloads. Kept in a dedicated file so each `Live*Service`
/// can rely on it without owning the definition.
enum LiveServiceError: LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let message): return message
        }
    }
}
