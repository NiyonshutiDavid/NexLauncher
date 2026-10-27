import SwiftUI
import AppKit
import NexCore

/// Renders every illustration to transparent PNGs in light and dark (for the website).
@MainActor
public enum IllustrationExporter {
    public static func export(to directory: URL, theme: ThemeID = .ember, pointSize: CGFloat = 240, scale: CGFloat = 3) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for kind in IllustrationKind.allCases {
            for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let view = IllustrationView(kind)
                    .frame(width: pointSize, height: pointSize)
                    .nexTheme(theme, appearance: .system)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = scale
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: directory.appendingPathComponent("\(kind)-\(name).png"))
            }
        }
    }
}
