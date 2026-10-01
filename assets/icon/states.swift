// Run: swift assets/icon/states.swift
// Draws the five menu bar states for the README from menuBarTemplate@2x.png.
// Mirrors menubar.js: same 18 pt image, mark as the button title, off is drawn dimmed.
import AppKit

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
guard let rep = NSImageRep(contentsOf: directory.appendingPathComponent("menuBarTemplate@2x.png")) else {
    fatalError("Cannot read menuBarTemplate@2x.png")
}
let scale: CGFloat = 2   // Retina; the README shows each image at half its pixel width
let icon = 18 * scale, height = 22 * scale
let font = NSFont.menuBarFont(ofSize: 0).withSize(NSFont.menuBarFont(ofSize: 0).pointSize * scale)
let states = [("on", ""), ("check", " ✓"), ("warn", " !"), ("wait", " …"), ("off", "")]
// One width for all states so the table column lines up.
let width = ceil((icon + states.map { ($0.1 as NSString).size(withAttributes: [.font: font]).width }.max()!) / 2) * 2

for (state, mark) in states {
    for (suffix, color) in [("", NSColor.black), ("-white", NSColor.white)] {
        let shade = state == "off" ? color.withAlphaComponent(0.3) : color   // appearsDisabled
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            fatalError("Cannot allocate image")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // Template image: keep its alpha, paint it in the text color.
        let glyph = NSRect(x: 0, y: (height - icon) / 2, width: icon, height: icon)
        rep.draw(in: glyph)
        shade.setFill()
        glyph.fill(using: .sourceIn)
        let text = NSAttributedString(string: mark, attributes: [.font: font, .foregroundColor: shade])
        text.draw(at: NSPoint(x: icon, y: (height - text.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: width / scale, height: height / scale)   // 144 dpi
        let name = "state-\(state)\(suffix).png"
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode \(name)") }
        try! data.write(to: directory.appendingPathComponent(name))
        print("Saved \(name): \(Int(width)) × \(Int(height)) px")
    }
}
