import SwiftUI
import AppKit
import NexCore

/// Circle avatar: the chosen photo, else initials on the chosen (or accent) colour.
public struct ProfileAvatar: View {
    @Environment(\.theme) private var theme
    let settings: AppSettings
    var size: CGFloat = 32

    public init(settings: AppSettings, size: CGFloat = 32) {
        self.settings = settings
        self.size = size
    }

    private var tint: Color {
        settings.avatarColorHex.map { let c = HexColor(hex: $0); return Color(red: c.red, green: c.green, blue: c.blue) } ?? theme.accent
    }

    public var body: some View {
        Group {
            if let path = settings.avatarPhotoPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    tint
                    Text(AppSettings.initials(from: settings.displayName))
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}
