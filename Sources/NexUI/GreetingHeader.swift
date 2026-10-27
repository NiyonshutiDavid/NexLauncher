import SwiftUI
import NexApp

struct GreetingHeader: View {
    @Environment(\.theme) private var theme
    let greeting: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(theme.fg3)
            Text(greeting)
                .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
            Text(subtitle).font(.title3).foregroundStyle(theme.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
