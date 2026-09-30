import Foundation

/// One of the four sentiment buckets. Each bucket has a fixed score range;
/// final item scores are interpolated within the bucket's range based on
/// within-bucket rank position. See `Spec.md` § 4.
enum Bucket: String, Codable, CaseIterable, Identifiable {
    case loved
    case liked
    case fine
    case didntLike

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loved: return "Loved"
        case .liked: return "Liked"
        case .fine: return "Fine"
        case .didntLike: return "Didn't like"
        }
    }

    /// Score range for this bucket. The item ranked highest within the bucket
    /// receives `upperBound`, the lowest receives `lowerBound`, with linear
    /// interpolation in between.
    var scoreRange: ClosedRange<Double> {
        switch self {
        case .loved: return 8.0...10.0
        case .liked: return 6.0...7.9
        case .fine: return 3.0...5.9
        case .didntLike: return 0.0...2.9
        }
    }

    // Visual styling (color, ink, symbol, blurb) lives in Design/Theme.swift.

    /// Buckets ordered from highest sentiment to lowest. Index 0 is "best".
    static var orderedHighToLow: [Bucket] { [.loved, .liked, .fine, .didntLike] }

    /// The bucket directly above this one in sentiment, or nil at the top.
    /// Used by the boundary-check step (Spec § 4): if a new item lands at the
    /// top of its bucket, we compare it against the bottom of `bucketAbove`.
    var bucketAbove: Bucket? {
        switch self {
        case .loved: return nil
        case .liked: return .loved
        case .fine: return .liked
        case .didntLike: return .fine
        }
    }

    /// The bucket directly below this one in sentiment, or nil at the bottom.
    /// Symmetrical use to `bucketAbove`: if a new item lands at the bottom of
    /// its bucket, we compare it against the top of `bucketBelow`.
    var bucketBelow: Bucket? {
        switch self {
        case .loved: return .liked
        case .liked: return .fine
        case .fine: return .didntLike
        case .didntLike: return nil
        }
    }
}
