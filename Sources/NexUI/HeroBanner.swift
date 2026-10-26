import SwiftUI
import NexCore

/// An illustration that gently floats, used where something is happening or inviting action.
struct AnimatedIllustration: View {
    let kind: IllustrationKind
    var amplitude: CGFloat = 5
    @State private var up = false

    var body: some View {
        IllustrationView(kind)
            .offset(y: up ? -amplitude : amplitude)
            .rotationEffect(.degrees(up ? -2 : 2))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

struct HeroAction: Identifiable {
    let id = UUID()
    let title: String
    var systemImage: String? = nil
    var style: PillStyle = .prominent
    let action: () -> Void
}

/// The call-to-action banner at the top of a page: eyebrow, headline, a line of copy, actions and an illustration.
struct HeroBanner: View {
    @Environment(\.theme) private var theme
    let eyebrow: String
    let title: String
    let subtitle: String
    let illustration: IllustrationKind
    var actions: [HeroAction] = []

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(1).foregroundStyle(theme.accent)
                Text(title).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.title3).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true)
                if !actions.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(actions) { a in Pill(a.title, style: a.style, systemImage: a.systemImage, action: a.action) }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AnimatedIllustration(kind: illustration).frame(width: 170, height: 170)
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .background {
            ZStack {
                LinearGradient(colors: [theme.accent.opacity(theme.dark ? 0.30 : 0.16), theme.accentSoft, theme.surface],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle().fill(theme.accent.opacity(theme.dark ? 0.18 : 0.10)).frame(width: 280).blur(radius: 50).offset(x: 260, y: -90)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(theme.line.opacity(theme.dark ? 1 : 0.7), lineWidth: 1))
        .shadow(color: .black.opacity(theme.dark ? 0 : 0.05), radius: 14, y: 6)
    }
}

/// Shown while projects are being scanned.
struct ScanningBanner: View {
    @Environment(\.theme) private var theme
    @State private var sweep = false

    var body: some View {
        HStack(spacing: 18) {
            AnimatedIllustration(kind: .telescope, amplitude: 4).frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scanning your projects…").font(.title3.weight(.semibold)).foregroundStyle(theme.fg)
                Text("Reading manifests to work out how each project runs.").foregroundStyle(theme.fg2)
                Capsule().fill(theme.accentSoft).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(theme.accent).frame(width: geo.size.width * 0.3)
                                .offset(x: sweep ? geo.size.width * 0.7 : 0)
                        }
                    }
                    .clipShape(Capsule())
                    .frame(maxWidth: 320)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: sweep)
            }
            Spacer()
        }
        .padding(20)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(theme.line))
        .onAppear { sweep = true }
    }
}

/// A shimmering placeholder card while the first scan runs.
struct SkeletonCard: View {
    @Environment(\.theme) private var theme
    @State private var glow = false

    var body: some View {
        CardSurface {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.line).frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(theme.line).frame(width: 150, height: 12)
                    Capsule().fill(theme.line.opacity(0.7)).frame(width: 100, height: 10)
                }
                Spacer()
                Capsule().fill(theme.accentSoft).frame(width: 90, height: 26)
            }
            .padding(18)
            .opacity(glow ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
        }
        .onAppear { glow = true }
    }
}
