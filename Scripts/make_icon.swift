import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let inset = CGFloat(size) * 0.05
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size)-2*inset, height: CGFloat(size)-2*inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size)*0.21, yRadius: CGFloat(size)*0.21)
    NSGradient(starting: NSColor(calibratedRed: 0.33, green: 0.64, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.82, alpha: 1))!.draw(in: shape, angle: -90)
    let symbol = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: CGFloat(size)*0.49, weight: .medium))!
    let symbolRect = NSRect(x: CGFloat(size)*0.24, y: CGFloat(size)*0.22, width: CGFloat(size)*0.52, height: CGFloat(size)*0.56)
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: symbol.size).fill(); symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1); tinted.unlockFocus()
    tinted.draw(in: symbolRect)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: folder + "/icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: URL(fileURLWithPath: folder + "/icon_\(size/2)x\(size/2)@2x.png")) }
}
