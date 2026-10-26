import SwiftUI

struct CTACardView: View {
    @Environment(\.theme) private var theme
    let cta: CTA
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(cta.headline).font(.title3.weight(.bold)).foregroundStyle(theme.fg).fixedSize(horizontal: false, vertical: true)
                    Text(cta.body).font(.callout).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Pill(cta.button, action: onAction)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IllustrationView(cta.illustration).frame(width: 130, height: 130)
            }
            .padding(20)
            IconButton("xmark", help: "Dismiss", action: onDismiss).padding(10)
        }
        .frame(width: 440, height: 190)
        .background(
            LinearGradient(colors: [theme.accentSoft, theme.surface], startPoint: .topTrailing, endPoint: .bottomLeading),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(theme.line.opacity(theme.dark ? 1 : 0.6), lineWidth: 1))
        .shadow(color: .black.opacity(theme.dark ? 0 : 0.06), radius: 12, y: 4)
    }
}

struct CTAShelf: View {
    @Bindable var model: AppModel

    var body: some View {
        let items = model.visibleCTAs
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(items) { cta in
                        CTACardView(cta: cta,
                                    onAction: { Task { await model.perform(cta.id) } },
                                    onDismiss: { withAnimation { model.dismiss(cta.id) } })
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }
}
