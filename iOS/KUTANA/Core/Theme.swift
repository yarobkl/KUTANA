import SwiftUI

enum KutanaTheme {
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

/// Shared interaction language: restrained motion, responsive touch and full
/// accessibility support. No perpetual animation or custom navigation overlay.
enum KutanaMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let reveal = Animation.spring(response: 0.36, dampingFraction: 0.88)
}

struct KutanaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : KutanaMotion.quick, value: configuration.isPressed)
    }
}

/// A neutral native placeholder avoids a flash of empty content on slow networks.
/// Intentionally static: a perpetual shimmer consumes energy and adds visual noise.
struct KutanaLoadingRow: View {
    var withThumbnail = false
    var body: some View {
        HStack(spacing: 14) {
            if withThumbnail {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 84, height: 84)
            }
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemFill))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemFill))
                    .frame(maxWidth: 170).frame(height: 12)
                RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemFill))
                    .frame(maxWidth: 115).frame(height: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement du contenu")
    }
}

/// Image presentation is native and cached according to URLSession/HTTP headers.
/// A stable placeholder keeps list rows from jumping during image downloads.
struct KutanaListingPhoto: View {
    let url: URL?
    var width: CGFloat = 84
    var height: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : KutanaMotion.reveal)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
                    .transition(reduceMotion ? .identity : .opacity)
            case .empty:
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            case .failure:
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Photo de l'annonce")
    }
}

struct KutanaPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(KutanaTheme.blue)
        .controlSize(.large)
    }
}

/// A restrained, one-time reveal for each main tab. The native TabView keeps its stacks.
struct KutanaTabEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0.93)
            .offset(y: visible || reduceMotion ? 0 : 6)
            .onAppear {
                if reduceMotion { visible = true }
                else { withAnimation(.easeOut(duration: 0.24)) { visible = true } }
            }
            .onDisappear { visible = false }
    }
}

struct KutanaFeatureHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [KutanaTheme.blue, Color(red: 0.055, green: 0.22, blue: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.17), lineWidth: 1)
                .frame(width: 190, height: 190).offset(x: 225, y: -68)
            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                .frame(width: 140, height: 140).offset(x: 230, y: 70)
            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.8)
                    .foregroundStyle(.white.opacity(0.8))
                Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.5).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(revealed || reduceMotion ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 12)
        }
        .frame(minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion { revealed = true }
            else { withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.07)) { revealed = true } }
        }
        .onDisappear { revealed = false }
    }
}
