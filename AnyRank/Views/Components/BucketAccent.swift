import SwiftUI

/// Small colored bar shown on the leading edge of an item row to indicate
/// its bucket. Score-on-color is the alternate explicit treatment, but
/// per the spec the list view uses color-only.
struct BucketAccent: View {
    let bucket: Bucket
    var width: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(bucket.color)
            .frame(width: width)
            .accessibilityLabel(bucket.displayName)
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(Bucket.orderedHighToLow) { bucket in
            VStack {
                BucketAccent(bucket: bucket)
                    .frame(height: 40)
                Text(bucket.displayName).font(.caption)
            }
        }
    }
    .padding()
}
