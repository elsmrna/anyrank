import SwiftUI

// MARK: - Surfaces

extension View {
    /// Standard card: white/espresso surface, hairline border, soft shadow.
    func card(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius))
    }

    /// Paper background behind a whole screen, extending under the bars.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Hides a `List`/`Form`'s default grouped background so the paper
    /// background shows through, and applies the standard row surface.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .screenBackground()
    }
}

private struct CardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline.opacity(colorScheme == .dark ? 1 : 0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.045), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Button styles

/// Gentle press-down scale for any tappable surface (cards, tiles).
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Full-width terracotta capsule for the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Quiet companion to `PrimaryButtonStyle`.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(Theme.surfaceMuted, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Labels

/// Small uppercase tracked label used above groups of content.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Icons & artwork

/// Rounded square holding a category's SF Symbol, tinted per category.
struct CategoryIconTile: View {
    let category: Category
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(category.tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.systemIconName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(category.tint)
            }
            .accessibilityHidden(true)
    }
}

/// Cover art / poster thumbnail with a calm category placeholder while
/// loading or when there's no image. Fades the image in once loaded.
struct ArtworkView: View {
    let urlString: String?
    let category: Category
    var width: CGFloat = 44
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    init(urlString: String?, category: Category, width: CGFloat = 44, cornerRadius: CGFloat = 8) {
        self.urlString = urlString
        self.category = category
        self.width = width
        self.cornerRadius = cornerRadius
        // Draw already-loaded artwork on the first frame, so rows scrolling
        // back into view don't flash the placeholder.
        _image = State(initialValue: urlString.flatMap(URL.init(string:)).flatMap(ArtworkCache.cachedImage(for:)))
    }

    private var height: CGFloat { width / category.artworkAspectRatio }

    /// Waits between attempts after a transient failure (throttling, a
    /// dropped connection). The task ends when the view goes away.
    private static let retryDelays: [Duration] = [.seconds(2), .seconds(6), .seconds(20)]

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let urlString, let url = URL(string: urlString) else {
            image = nil
            return
        }
        if let cached = ArtworkCache.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        for attempt in 0...Self.retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(for: Self.retryDelays[attempt - 1])
                if Task.isCancelled { return }
            }
            switch await ArtworkCache.shared.load(url) {
            case .image(let loaded):
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                return
            case .missing:
                return
            case .failed:
                continue
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            category.tint.opacity(0.12)
            Image(systemName: category.systemIconName)
                .font(.system(size: min(width, height) * 0.38, weight: .medium))
                .foregroundStyle(category.tint.opacity(0.7))
        }
    }
}

// MARK: - Buckets & scores

/// Score (when meaningful) or bucket glyph in a bucket-tinted capsule.
struct ScoreBadge: View {
    let bucket: Bucket
    /// Nil hides the number and shows the bucket glyph instead.
    let score: Double?
    var large: Bool = false

    var body: some View {
        Group {
            if let score {
                Text(String(format: "%.1f", score))
                    .font(.score(large ? .title3 : .subheadline, weight: .bold))
            } else {
                Image(systemName: bucket.symbolName)
                    .font(.system(size: large ? 15 : 11, weight: .bold))
            }
        }
        .foregroundStyle(bucket.ink)
        .frame(minWidth: large ? 60 : 44, minHeight: large ? 36 : 28)
        .padding(.horizontal, score == nil ? 0 : 4)
        .background(bucket.color.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\(bucket.displayName), score \(String(format: "%.1f", $0))" } ?? bucket.displayName)
    }
}

/// Bucket name with its glyph, tinted — used as a small tag.
struct BucketTag: View {
    let bucket: Bucket

    var body: some View {
        Label(bucket.displayName, systemImage: bucket.symbolName)
            .font(.caption.weight(.semibold))
            .labelStyle(TightLabelStyle())
            .foregroundStyle(bucket.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bucket.color.opacity(0.16), in: Capsule())
    }
}

/// Icon + title with a compact gap, for pills and capsule buttons.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Proportional capsule showing how a list's items split across buckets.
struct BucketDistributionBar: View {
    let counts: [Bucket: Int]
    var height: CGFloat = 6

    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: total > 0 ? 2 : 0) {
                if total == 0 {
                    Capsule().fill(Theme.hairline)
                } else {
                    ForEach(Bucket.orderedHighToLow) { bucket in
                        let count = counts[bucket] ?? 0
                        if count > 0 {
                            Capsule()
                                .fill(bucket.color)
                                .frame(width: max(height, segmentWidth(count, in: geo.size.width)))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func segmentWidth(_ count: Int, in width: CGFloat) -> CGFloat {
        let nonEmpty = counts.values.filter { $0 > 0 }.count
        let spacing = CGFloat(max(nonEmpty - 1, 0)) * 2
        return (width - spacing) * CGFloat(count) / CGFloat(total)
    }

    private var accessibilitySummary: String {
        Bucket.orderedHighToLow
            .compactMap { b in counts[b].flatMap { $0 > 0 ? "\($0) \(b.displayName)" : nil } }
            .joined(separator: ", ")
    }
}

extension RankList {
    /// Item counts per bucket, for `BucketDistributionBar`.
    var bucketCounts: [Bucket: Int] {
        Dictionary(grouping: items, by: \.bucket).mapValues(\.count)
    }
}

// MARK: - Search field

/// Rounded search field with a clear button and an inline activity
/// indicator — results stay on screen while a new query loads.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var isLoading: Bool = false
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField(prompt, text: $text)
                .focused(focus)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Theme.textPrimary)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: isLoading)
    }
}
