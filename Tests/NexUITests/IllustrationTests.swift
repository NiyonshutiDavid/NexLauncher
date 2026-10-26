import Testing
import SwiftUI
import NexCore
@testable import NexUI

@MainActor
@Suite struct IllustrationTests {
    private func hasVisiblePixels(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: data.count, by: 4).contains { data[$0] > 0 }
    }

    @Test func everyIllustrationRendersInEveryThemeMode() {
        for kind in IllustrationKind.allCases {
            for theme in ThemeID.allCases {
                for dark in [false, true] {
                    for size in [48.0, 160.0, 320.0] {
                        let view = IllustrationView(kind)
                            .frame(width: size, height: size)
                            .environment(\.theme, Theme.resolve(theme, dark: dark))
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 1
                        guard let image = renderer.cgImage else { Issue.record("\(kind) \(theme) dark=\(dark) \(size): no image"); continue }
                        #expect(hasVisiblePixels(image), "\(kind) \(theme) dark=\(dark) \(size) is blank")
                    }
                }
            }
        }
    }

    @Test func thereAreEightIllustrations() {
        #expect(IllustrationKind.allCases.count == 8)
    }
}
