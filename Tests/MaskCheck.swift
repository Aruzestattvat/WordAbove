import AppKit

@main struct MaskCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let mask = RoundedMaterialView.materialMask()
        precondition(mask.capInsets.left == 28 && mask.resizingMode == .stretch)
        for size in [NSSize(width: 640, height: 130), NSSize(width: 960, height: 206)] {
            let view = RoundedMaterialView(frame: NSRect(origin: .zero, size: size))
            precondition(view.maskImage != nil && !view.isOpaque)
            precondition(view.layer?.masksToBounds == true)
            // Rasterize the same alpha mask used by the material compositor.
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.clear.setFill(); NSRect(origin: .zero, size: size).fill(using: .copy)
            mask.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            let w = Int(size.width), h = Int(size.height)
            for (x,y) in [(0,0), (w-1,0), (0,h-1), (w-1,h-1)] {
                precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.01, "Nontransparent corner")
            }
            precondition(bitmap.colorAt(x: w/2, y: h/2)!.alphaComponent > 0.99)
            print("PASS: \(w)×\(h) material mask, four transparent corners, opaque center, child layer clipping")
        }
    }
}
