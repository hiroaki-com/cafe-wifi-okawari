// Run: swift assets/icon/prepare.swift
// Uses macOS frameworks only. Does not modify the selected source or app code.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let sourceURL = directory.appendingPathComponent("source.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let input = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read source.png")
}
let width = input.width, height = input.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: colorSpace, bitmapInfo: bitmapInfo),
      let memory = context.data else { fatalError("Cannot allocate image") }
context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = memory.bindMemory(to: UInt8.self, capacity: width * height * 4)
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        // Template silhouettes use alpha only. Preserve every original alpha value.
        pixels[i] = 0
        pixels[i + 1] = 0
        pixels[i + 2] = 0
        if pixels[i + 3] > 0 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX >= minX, maxY >= minY,
      let template = context.makeImage(),
      let cropped = template.cropping(to: CGRect(x: minX, y: minY,
                                                width: maxX - minX + 1,
                                                height: maxY - minY + 1)) else {
    fatalError("Source has no visible silhouette")
}

for (name, size, dpi, tile) in [("icon.png", 1024, 72, false),
                                 ("icon-readme.png", 1024, 72, true),
                                 ("menuBarTemplate.png", 18, 72, false),
                                 ("menuBarTemplate@2x.png", 36, 144, false)] {
    guard let output = CGContext(data: nil, width: size, height: size,
                                 bitsPerComponent: 8, bytesPerRow: size * 4,
                                 space: colorSpace, bitmapInfo: bitmapInfo) else {
        fatalError("Cannot allocate output")
    }
    // One logical point of padding on an 18-point canvas; preserve aspect ratio.
    // The README tile leaves more room so the glyph sits inside the rounded square.
    let padding = CGFloat(size) / (tile ? 6 : 18)
    if tile {
        // README in any theme: black glyph on a white rounded square with a thin grey edge.
        // The page theme and the OS appearance can differ, so no <picture> switch is used.
        let edge = CGFloat(size) / 128
        let rect = CGRect(x: edge / 2, y: edge / 2, width: CGFloat(size) - edge, height: CGFloat(size) - edge)
        let radius = CGFloat(size) * 0.225
        output.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        output.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        output.setStrokeColor(CGColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
        output.setLineWidth(edge)
        output.drawPath(using: .fillStroke)
    }
    let scale = (CGFloat(size) - 2 * padding) / CGFloat(max(cropped.width, cropped.height))
    let w = CGFloat(cropped.width) * scale, h = CGFloat(cropped.height) * scale
    output.interpolationQuality = .high
    output.draw(cropped, in: CGRect(x: (CGFloat(size) - w) / 2,
                                   y: (CGFloat(size) - h) / 2, width: w, height: h))
    guard let image = output.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            directory.appendingPathComponent(name) as CFURL,
            UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create \(name)")
    }
    CGImageDestinationAddImage(destination, image,
                              [kCGImagePropertyDPIWidth: dpi,
                               kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save \(name)") }
    print("Saved \(name): \(size) × \(size) px")
}
