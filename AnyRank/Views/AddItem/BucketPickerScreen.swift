import SwiftUI

/// Phase 2 of add-item: the user picks a sentiment bucket. Four big tap
/// targets, one per bucket, color-coded to match the list view's accents.
struct BucketPickerScreen: View {
    let itemName: String
    let onPick: (Bucket) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(itemName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("How was it?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(Bucket.orderedHighToLow) { bucket in
                    BucketButton(bucket: bucket) {
                        onPick(bucket)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

private struct BucketButton: View {
    let bucket: Bucket
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(bucket.color)
                    .frame(width: 18, height: 18)
                Text(bucket.displayName)
                    .font(.title3.weight(.medium))
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(bucket.color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(bucket.color.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bucket: \(bucket.displayName)")
    }
}

#Preview {
    BucketPickerScreen(itemName: "Bestia", onPick: { _ in })
}
