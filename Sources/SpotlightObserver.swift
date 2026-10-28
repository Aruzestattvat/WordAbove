import AppKit
import ApplicationServices

struct SpotlightSnapshot {
    let text: String
    let frame: CGRect // Search window in AppKit screen coordinates
    let searchFieldFrame: CGRect?
}

enum SpotlightAccessState: String {
    case permission = "辅助功能未授权"
    case notRunning = "未检测到 Spotlight 搜索进程"
    case noWindow = "未找到聚焦窗口"
    case noSearchField = "无法读取聚焦搜索框"
    case noSpace = "屏幕空间不足，卡片无法显示"
    case ignoredInput = "当前语言对未匹配输入内容"
    case empty = "聚焦搜索框为空"
    case ready = "已读取聚焦搜索框"
}

func spotlightHostBundleIDs(macOSMajor: Int) -> [String] {
    // The Command-Space overlay moved to Siri AI (Campo) in macOS 27.
    // Classic Spotlight can still be enabled on that system, so keep both.
    macOSMajor >= 27 ? ["com.apple.campo", "com.apple.Spotlight"] : ["com.apple.Spotlight"]
}

func mayReadSpotlightHost(bundleID: String, isActive: Bool, macOSMajor: Int) -> Bool {
    guard spotlightHostBundleIDs(macOSMajor: macOSMajor).contains(bundleID) else { return false }
    // Campo also owns the normal Siri chat window. The Command-Space overlay
    // is hosted by Campo while it is not the frontmost app; never read its chat.
    return bundleID != "com.apple.campo" || !isActive
}

final class SpotlightObserver {
    private(set) var state: SpotlightAccessState = .notRunning
    private(set) var recentSearchWindowOwners: [String] = []
    private(set) var recentGeometry: String?
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
    private func focusedTextField(_ element: AXUIElement) -> AXUIElement? {
        guard let role = attribute(element, kAXRoleAttribute as CFString) as? String,
              role == kAXTextFieldRole as String,
              attribute(element, kAXValueAttribute as CFString) is String else { return nil }
        return element
    }
    private func findTextField(_ element: AXUIElement, depth: Int = 0, budget: inout Int) -> AXUIElement? {
        guard depth < 9, budget > 0 else { return nil }; budget -= 1
        if let field = focusedTextField(element) { return field }
        if let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children {
                if let found = findTextField(child, depth: depth + 1, budget: &budget) { return found }
            }
        }
        return nil
    }
    private func frameOfSearchField(_ field: AXUIElement) -> CGRect? {
        guard let position = attribute(field, kAXPositionAttribute as CFString),
              let size = attribute(field, kAXSizeAttribute as CFString),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width >= 150, dimensions.height >= 20, dimensions.height <= 160 else { return nil }
        // Accessibility uses a top-left origin; AppKit uses bottom-left.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: point.x, y: primaryTop - point.y - dimensions.height,
                      width: dimensions.width, height: dimensions.height)
    }
    func snapshot() -> SpotlightSnapshot? {
        guard AXIsProcessTrusted() else { state = .permission; field = nil; return nil }
        // Window owner metadata helps diagnose macOS versions that move the
        // search UI to a different process. Never record a window title or text.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let searchOwners = Set(windows.compactMap { info -> String? in
            guard let name = info[kCGWindowOwnerName as String] as? String,
                  name.localizedCaseInsensitiveContains("Spotlight") || name.localizedCaseInsensitiveContains("Siri"),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 250, rect.height >= 40 else { return nil }
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "未知"
            return "\(name) [\(bundle)]"
        })
        if !searchOwners.isEmpty { recentSearchWindowOwners = searchOwners.sorted() }
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let hosts = spotlightHostBundleIDs(macOSMajor: major).flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }.filter {
            mayReadSpotlightHost(bundleID: $0.bundleIdentifier ?? "", isActive: $0.isActive, macOSMajor: major)
        }
        guard !hosts.isEmpty else {
            state = .notRunning; field = nil; return nil
        }
        // Window metadata only; no screenshots, keystrokes, or other apps' text are read.
        let visibleHosts: [(NSRunningApplication, CGRect)] = hosts.compactMap { app in
            let frames: [CGRect] = windows.compactMap { info in
                guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 250, rect.height >= 40,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
                return rect
            }
            guard let frame = frames.min(by: { $0.minY < $1.minY }) else { return nil }
            return (app, frame)
        }
        guard let (app, screenFrame) = visibleHosts.first else {
            state = .noWindow; field = nil; return nil
        }
        if cachedPID != app.processIdentifier || element == nil {
            cachedPID = app.processIdentifier
            element = AXUIElementCreateApplication(cachedPID)
            AXUIElementSetMessagingTimeout(element!, 0.15)
            field = nil
        }
        guard let element else { state = .noSearchField; return nil }
        var raw: String?
        if let field { raw = attribute(field, kAXValueAttribute as CFString) as? String }
        if raw == nil {
            if let focused = attribute(element, kAXFocusedUIElementAttribute as CFString), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                var budget = 15
                let focusedField = unsafeBitCast(focused, to: AXUIElement.self)
                // Older/newer Spotlight versions may omit the search subrole.
                // This fallback only inspects the focused field of Spotlight itself.
                field = findSearch(focusedField, budget: &budget) ?? focusedTextField(focusedField)
            }
            if field == nil, let axWindows = attribute(element, kAXWindowsAttribute as CFString) as? [AXUIElement] {
                var budget = 90
                for window in axWindows {
                    if let found = findSearch(window, budget: &budget) { field = found; break }
                }
                if field == nil && app.bundleIdentifier != "com.apple.campo" {
                    // Spotlight has used different AX identifiers/subroles across
                    // macOS versions. Campo's separate Siri chat must not use
                    // this broad fallback.
                    budget = 90
                    for window in axWindows {
                        if let found = findTextField(window, budget: &budget) { field = found; break }
                    }
                }
            }
            if let field { raw = attribute(field, kAXValueAttribute as CFString) as? String }
        }
        guard let raw else { state = .noSearchField; return nil }
        state = raw.isEmpty ? .empty : .ready
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = CGRect(x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width, height: screenFrame.height)
        let searchFieldFrame = field.flatMap(frameOfSearchField)
        func description(_ rect: CGRect) -> String {
            "x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))"
        }
        recentGeometry = "窗口(\(description(frame)))；输入框(\(searchFieldFrame.map(description) ?? "位置不可读"))"
        return SpotlightSnapshot(text: raw, frame: frame, searchFieldFrame: searchFieldFrame)
    }
}

func cardFrame(above spotlight: CGRect, visible: CGRect) -> CGRect? {
    cardFrame(above: spotlight, visible: visible, gap: 12, topInset: 8,
              minimumHeight: 100, maximumHeight: 206)
}

private func cardFrame(above spotlight: CGRect, visible: CGRect,
                       gap: CGFloat, topInset: CGFloat,
                       minimumHeight: CGFloat, maximumHeight: CGFloat) -> CGRect? {
    let y = spotlight.maxY + gap
    let available = visible.maxY - y - topInset
    guard spotlight.intersects(visible), available >= minimumHeight else { return nil }
    // Match both Spotlight edges; only constrain the width at a screen boundary.
    let width = min(spotlight.width, visible.width - 24)
    let height = min(maximumHeight, available)
    let x = min(max(spotlight.midX - width / 2, visible.minX + 12), visible.maxX - width - 12)
    return CGRect(x: x, y: y, width: width, height: height)
}

func cardFrame(around window: CGRect, searchField: CGRect?, visible: CGRect) -> CGRect? {
    if let aboveWindow = cardFrame(above: window, visible: visible) { return aboveWindow }
    // Campo's result window reaches almost to the menu bar on macOS 27.
    // Keep the card above its input and reduce its height to the room available.
    // This intentionally has no side or below fallback.
    return cardFrame(above: searchField ?? window, visible: visible,
                     gap: 8, topInset: 4, minimumHeight: 72, maximumHeight: 90)
}
