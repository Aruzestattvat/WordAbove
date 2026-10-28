import AppKit
import ApplicationServices

struct SpotlightSnapshot {
    let text: String
    let frame: CGRect // AppKit screen coordinates
}

enum SpotlightAccessState: String {
    case permission = "辅助功能未授权"
    case notRunning = "未检测到 Spotlight 搜索进程"
    case noWindow = "未找到聚焦窗口"
    case noSearchField = "无法读取聚焦搜索框"
    case noSpace = "搜索框上方空间不足，卡片无法显示"
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
