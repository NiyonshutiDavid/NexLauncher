// Generates Resources/AppIcon.icns:  swift Resources/make-icon.swift
// Nexventures ember orange (nexventures.net: ember-400 #ff7440 → ember-700 #a8320b) with a white bolt.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)

    // drop shadow under the tile
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    color(0xcf3f0e).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // ember gradient
    NSGradient(colors: [color(0xff7440), color(0xf0561f), color(0xcf3f0e), color(0xa8320b)], atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)!
        .draw(in: path, angle: -60)

    // glassy top highlight
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // inner rim
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: s * 0.196, yRadius: s * 0.196)
    rim.lineWidth = s * 0.006
    NSColor.white.withAlphaComponent(0.25).setStroke(); rim.stroke()

    // white bolt with a soft shadow
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .bold).applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let w = sym.size.width, h = sym.size.height
        NSGraphicsContext.saveGraphicsState()
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = color(0x5f1d0c, 0.55)
        glyphShadow.shadowBlurRadius = s * 0.025
        glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.014)
        glyphShadow.set()
        sym.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = "Resources/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
