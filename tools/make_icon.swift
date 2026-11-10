import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.12, green: 0.14, blue: 0.30, alpha: 1), NSColor(red: 0.28, green: 0.12, blue: 0.42, alpha: 1)])!.draw(in: path, angle: -60)

// halka göstergesi
let center = NSPoint(x: 512, y: 512)
func arc(_ from: CGFloat, _ to: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: 290, startAngle: 90 - from * 360, endAngle: 90 - to * 360, clockwise: true)
    p.lineWidth = 64; p.lineCapStyle = .round
    color.setStroke(); p.stroke()
}
let track = NSBezierPath(ovalIn: NSRect(x: 222, y: 222, width: 580, height: 580)); track.lineWidth = 64
NSColor(white: 1, alpha: 0.08).setStroke(); track.stroke()
arc(0.00, 0.38, NSColor(red: 0.36, green: 0.58, blue: 1.0, alpha: 1))
arc(0.43, 0.58, NSColor(red: 1.0, green: 0.62, blue: 0.28, alpha: 1))
arc(0.63, 0.72, NSColor(red: 0.82, green: 0.42, blue: 0.98, alpha: 1))

if let sym = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 230, weight: .semibold).applying(.init(paletteColors: [.white]))) {
    let s = sym.size
    sym.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))
}
img.unlockFocus()

let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
