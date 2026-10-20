import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let bounds = NSRect(x: p * 0.07, y: p * 0.07, width: p * 0.86, height: p * 0.86)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: p * 0.20, yRadius: p * 0.20)
        let gradient = NSGradient(starting: NSColor(red: 0.38, green: 0.38, blue: 0.84, alpha: 1),
                                  ending: NSColor(red: 0.18, green: 0.18, blue: 0.43, alpha: 1))!
        gradient.draw(in: shape, angle: -60)
        for (index, height) in [0.16, 0.31, 0.48, 0.65, 0.40, 0.27, 0.13].enumerated() {
            let h = p * height
            let bar = NSBezierPath(roundedRect: NSRect(x: p * (0.23 + Double(index) * 0.079), y: (p - h) / 2, width: p * 0.044, height: h), xRadius: p * 0.022, yRadius: p * 0.022)
            (index > 3 ? NSColor(red: 0.56, green: 0.91, blue: 0.85, alpha: 1) : NSColor.white).setFill()
            bar.fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
