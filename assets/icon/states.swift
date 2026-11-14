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

// Each image is a light menu bar chip so it reads the same in light and dark README themes.
let pad = 4 * scale, chipWidth = width + 2 * pad

for (state, mark) in states {
    let shade = state == "off" ? NSColor.black.withAlphaComponent(0.3) : NSColor.black   // appearsDisabled
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(chipWidth), pixelsHigh: Int(height),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("Cannot allocate image")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // Template image: keep its alpha, paint it in the text color. Drawn alone first so .sourceIn
    // tints only the glyph, then the chip goes behind it.
    let glyph = NSRect(x: pad, y: (height - icon) / 2, width: icon, height: icon)
    rep.draw(in: glyph)
    shade.setFill()
    glyph.fill(using: .sourceIn)
    let edge = scale / 2
    let chip = NSBezierPath(roundedRect: NSRect(x: edge / 2, y: edge / 2, width: chipWidth - edge, height: height - edge),
                            xRadius: 5 * scale, yRadius: 5 * scale)
    NSGraphicsContext.current?.compositingOperation = .destinationOver
    NSColor(white: 0.93, alpha: 1).setFill()
    chip.fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1).setStroke()
    chip.lineWidth = edge
    chip.stroke()
    let text = NSAttributedString(string: mark, attributes: [.font: font, .foregroundColor: shade])
    text.draw(at: NSPoint(x: pad + icon, y: (height - text.size().height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: chipWidth / scale, height: height / scale)   // 144 dpi
    let name = "state-\(state).png"
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode \(name)") }
    try! data.write(to: directory.appendingPathComponent(name))
    print("Saved \(name): \(Int(chipWidth)) × \(Int(height)) px")
}
