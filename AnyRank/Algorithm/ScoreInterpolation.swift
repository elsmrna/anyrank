import Foundation

/// Pure functions for computing scores from within-bucket rank position.
/// Spec § 4: within a bucket of N items, the i-th ranked item (1-indexed
/// from the top) gets a score of
///     bucketHigh - (bucketHigh - bucketLow) * ((i - 1) / max(N - 1, 1))
enum ScoreInterpolation {

    /// Score for the item at `rankIndex` (0-indexed) within a bucket of
    /// `count` items. `count` must be ≥ 1 and `rankIndex` must be in 0..<count.
    static func score(
        forRankIndex rankIndex: Int,
        bucketCount count: Int,
        bucket: Bucket
    ) -> Double {
        precondition(count >= 1, "bucketCount must be ≥ 1")
        precondition((0..<count).contains(rankIndex), "rankIndex out of range")

        let high = bucket.scoreRange.upperBound
        let low = bucket.scoreRange.lowerBound

        if count == 1 { return high }
        let denom = Double(count - 1)
        let t = Double(rankIndex) / denom
        return high - (high - low) * t
    }

    /// Recompute and assign scores for every item in `items`, where `items`
    /// is already sorted by within-bucket rank descending (best first).
    /// All items must share the same bucket.
    @MainActor
    static func renormalize(_ items: [RankItem], in bucket: Bucket) {
        let count = items.count
        for (index, item) in items.enumerated() {
            item.score = score(forRankIndex: index, bucketCount: count, bucket: bucket)
            if item.bucket != bucket {
                item.bucket = bucket
            }
        }
    }
}
