import Foundation
import Observation

/// Append-only log of pairwise comparison outcomes. Persisted to a sibling
/// `<list-id>_comparisons.csv` file (and the matching `_comparisons` tab in
/// the synced spreadsheet). Provides audit history; not consumed by the
/// runtime algorithm.
@Observable
@MainActor
final class ComparisonRecord: Identifiable {

    let id: UUID
    var winnerItemID: UUID
    var loserItemID: UUID
    var kindRaw: String
    var timestamp: Date

    var kind: ComparisonKind {
        get { ComparisonKind(rawValue: kindRaw) ?? .binarySearch }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        winnerItemID: UUID,
        loserItemID: UUID,
        kind: ComparisonKind,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.winnerItemID = winnerItemID
        self.loserItemID = loserItemID
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
    }
}

enum ComparisonKind: String, Codable, Sendable {
    case binarySearch
    case boundaryCheck
    case tieBreak
    case rerank
}
