import AppKit
import ApplicationServices

struct SpotlightSnapshot {
    let text: String
    let frame: CGRect // AppKit screen coordinates
}

final class SpotlightObserver {
    private var cachedPID: pid_t = 0
    private var element: AXUIElement?
    private var field: AXUIElement?

    private func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key, &value) == .success ? value : nil
    }
    private func findSearch(_ element: AXUIElement, depth: Int = 0, budget: inout Int) -> AXUIElement? {
        guard depth < 9, budget > 0 else { return nil }; budget -= 1
        if let id = attribute(element, kAXIdentifierAttribute as CFString) as? String, id == "SpotlightSearchField" { return element }
        let role = attribute(element, kAXRoleAttribute as CFString) as? String
        let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String
        if role == kAXTextFieldRole as String && subrole == kAXSearchFieldSubrole as String { return element }
        if let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children {
                if let found = findSearch(child, depth: depth+1, budget: &budget) { return found }
            }
        }
        return nil
    }
    func snapshot() -> SpotlightSnapshot? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first else { field = nil; return nil }
        // Window metadata only; no screenshots, keystrokes, or other apps' text are read.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames: [CGRect] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 250, rect.height >= 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return rect
        }
        guard let screenFrame = frames.min(by: { $0.minY < $1.minY }) else { field = nil; return nil }
        if cachedPID != app.processIdentifier || element == nil {
            cachedPID = app.processIdentifier
            element = AXUIElementCreateApplication(cachedPID)
            AXUIElementSetMessagingTimeout(element!, 0.15)
            field = nil
        }
        guard let element else { return nil }
        var raw: String?
        if let field { raw = attribute(field, kAXValueAttribute as CFString) as? String }
        if raw == nil {
            if let focused = attribute(element, kAXFocusedUIElementAttribute as CFString), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                var budget = 15
                field = findSearch(unsafeBitCast(focused, to: AXUIElement.self), budget: &budget)
            }
            if field == nil, let axWindows = attribute(element, kAXWindowsAttribute as CFString) as? [AXUIElement] {
                var budget = 90
                for window in axWindows {
                    if let found = findSearch(window, budget: &budget) { field = found; break }
                }
            }
            if let field { raw = attribute(field, kAXValueAttribute as CFString) as? String }
        }
        guard let raw else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = CGRect(x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width, height: screenFrame.height)
        return SpotlightSnapshot(text: raw, frame: frame)
    }
}

func cardFrame(above spotlight: CGRect, visible: CGRect) -> CGRect? {
    let gap: CGFloat = 12
    let y = spotlight.maxY + gap
    let available = visible.maxY - y - 8
    guard available >= 100 else { return nil }
    // Match both Spotlight edges; only constrain the width at a screen boundary.
    let width = min(spotlight.width, visible.width - 24)
    let height = min(206, available)
    let x = min(max(spotlight.midX - width / 2, visible.minX + 12), visible.maxX - width - 12)
    return CGRect(x: x, y: y, width: width, height: height)
}
