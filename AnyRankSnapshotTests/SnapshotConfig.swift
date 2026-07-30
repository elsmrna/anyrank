import Foundation
import SnapshotTesting
import UIKit

/// Centralized snapshot configuration so all tests render against the same
/// canonical device + traits. Spec calls for iPhone 16 Pro at default Dynamic
/// Type, light mode for the v1 baseline.
///
/// To regenerate references after an intentional UI change, set
/// `isRecording = true` on the snapshot call (or temporarily set
/// `defaultRecordingMode = .all` here), run the failing test once, then
/// revert.
enum SnapshotConfig {
    /// Reference device used for all snapshots in v1.
    static let device: ViewImageConfig = .iPhone13Pro // Closest available preset; iPhone 16 Pro renders at the same logical size.

    /// Standard precision. Lower if anti-aliasing on text makes tests flaky;
    /// for v1 we keep it strict.
    static let precision: Float = 0.99

    /// Minimum subpixel match threshold.
    static let perceptualPrecision: Float = 0.97
}
