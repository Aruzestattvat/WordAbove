import AppKit

/// Masks the WindowServer material as well as the ordinary content layer.
/// A CALayer cornerRadius alone leaves behind-window blur visible in the corners.
final class RoundedMaterialView: NSVisualEffectView {
    static let radius: CGFloat = 28

    static func materialMask() -> NSImage {
        let radius = Self.radius
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.materialMask()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = Self.radius
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }
}
