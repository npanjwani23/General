import AppKit
import CoreImage

// Renders Clarity's 1024x1024 app icon: frosted lavender/indigo blobs with
// a wide, heavy "CLRTY" wordmark.
let size: CGFloat = 1024
let out = CommandLine.arguments[1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Base: soft vertical wash, light lavender to indigo.
let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [color(0x8B8AF0).cgColor, color(0x5B5BD6).cgColor, color(0x3D3BA8).cgColor] as CFArray,
                      locations: [0, 0.55, 1])!
cg.drawLinearGradient(base, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Blobs: radial glows that read as frosted color behind glass.
func blob(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                       colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                          endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
blob(color(0xC9C8F5, 0.95), 780, 820, 520)
blob(color(0xBFE3DC, 0.85), 170, 160, 480)
blob(color(0xA9A8FF, 0.55), 220, 760, 360)

// Frosted glass panel across the middle.
let panel = NSBezierPath(roundedRect: NSRect(x: 84, y: 332, width: size - 168, height: 360), xRadius: 96, yRadius: 96)
color(0xFFFFFF, 0.16).setFill()
panel.fill()
color(0xFFFFFF, 0.42).setStroke()
panel.lineWidth = 4
panel.stroke()

// Wordmark.
let font = NSFont.systemFont(ofSize: 164, weight: .black, width: .expanded)
let para = NSMutableParagraphStyle()
para.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = color(0x1C1B2E, 0.22)
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.shadowBlurRadius = 24
let attrs: [NSAttributedString.Key: Any] = [
    .font: font, .foregroundColor: NSColor.white, .kern: 14, .paragraphStyle: para, .shadow: shadow,
]
let text = NSAttributedString(string: "CLRTY", attributes: attrs)
let bounds = text.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
text.draw(in: NSRect(x: 0, y: (size - bounds.height) / 2 - 4, width: size, height: bounds.height))

NSGraphicsContext.restoreGraphicsState()

// App icons must have no alpha channel.
let ci = CIImage(bitmapImageRep: rep)!
let ciCtx = CIContext()
let flat = ciCtx.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, flat, [kCGImagePropertyHasAlpha: false] as CFDictionary)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
