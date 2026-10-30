// WordAbove — 被测代码的测试副本。
//
// 为什么需要这个文件：
//   Sources/App.swift 带 @main，Tests/ 下的检查也各自带 @main，直接一起编译会冲突；
//   把 Sources/*.swift 整体编成库再链接则受 internal 访问级别限制。
//   因此这里原样搬运被测符号（不修改实现），仅做两处删减：
//     · 去掉 App.swift 的 @main 入口与 AppDelegate（检查不涉及）
//     · 去掉 SpotlightObserver（依赖 ApplicationServices 与真实 Spotlight，检查不涉及）
//   实现正文与 Sources/ 保持一致；上游改动时请同步本文件。
//
// 本文件包含：cardFrame / normalizedWord / Entry / DictionaryStore / RoundedMaterialView

import AppKit
import Foundation
import SQLite3

// MARK: - 源自 Sources/Dictionary.swift

struct Entry: Codable {
    let word: String
    var phonetic: String
    let translation: String
    let definition: String
    var example: String
    var source: String
    var sourceURL: String?
    var license: String?
}

func normalizedWord(_ raw: String) -> String? {
    let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard word.count <= 48, word.range(of: "^[a-z]+(?:[-'][a-z]+)*$", options: .regularExpression) != nil else { return nil }
    return word
}

func displayPhonetic(_ raw: String) -> String? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/[]")))
        .replacingOccurrences(of: "'", with: "ˈ")
        .replacingOccurrences(of: ",", with: "ˌ")
        .replacingOccurrences(of: "ә", with: "ə")
    guard !clean.isEmpty, clean.count <= 64,
          !clean.contains("?"), !clean.contains("�"),
          !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    return "/" + clean + "/"
}

final class DictionaryStore {
    private var db: OpaquePointer?
    let isReady: Bool
    init(path: String) {
        let opened = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
        var statement: OpaquePointer?
        isReady = opened && sqlite3_prepare_v2(db, "SELECT 1 FROM words LIMIT 1", -1, &statement, nil) == SQLITE_OK
            && sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
    }
    deinit { sqlite3_close(db) }
    func lookup(_ word: String) -> Entry? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT word, phonetic, translation, definition, example, example_source FROM words WHERE word=?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, word, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        func value(_ column: Int32) -> String {
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
        return Entry(word: value(0), phonetic: value(1), translation: value(2), definition: value(3), example: value(4), source: value(5))
    }
}

struct APIEntry: Decodable {
    struct Phonetic: Decodable { let text: String? }
    struct Meaning: Decodable {
        struct Definition: Decodable { let example: String? }
        let definitions: [Definition]
    }
    struct License: Decodable { let name: String? }
    let phonetic: String?
    let phonetics: [Phonetic]?
    let meanings: [Meaning]
    let sourceUrls: [String]?
    let license: License?
}

actor ExampleService {
    private var cache: [String: Entry] = [:]
    private var attempted = Set<String>()
    func supplement(_ entry: Entry) async -> Entry {
        if let cached = cache[entry.word] { return cached }
        guard !attempted.contains(entry.word), let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/" + entry.word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { return entry }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { attempted.insert(entry.word); return entry }
            let results = try JSONDecoder().decode([APIEntry].self, from: data)
            var updated = entry
            if displayPhonetic(updated.phonetic) == nil {
                let candidates = results.compactMap(\.phonetic) + results.flatMap { $0.phonetics ?? [] }.compactMap(\.text)
                updated.phonetic = candidates.first(where: { displayPhonetic($0) != nil }) ?? ""
            }
            outer: for result in results {
                for definition in result.meanings.flatMap(\.definitions) {
                    if let example = definition.example, !example.isEmpty, example.count <= 400 {
                        updated.example = example
                        updated.source = "Wiktionary"
                        updated.sourceURL = result.sourceUrls?.first
                        updated.license = result.license?.name
                        break outer
                    }
                }
            }
            cache[entry.word] = updated
            attempted.insert(entry.word)
            return updated
        } catch { return entry }
    }
}

// MARK: - 源自 Sources/SpotlightObserver.swift（显示器适配与窗口定位）

enum DisplaySizeClass: String {
    case inch13 = "13 寸内屏"
    case inch14 = "14 寸内屏"
    case inch16 = "16 寸内屏"
    case other = "其他显示器"
}

func displaySizeClass(diagonalInches: CGFloat?, isBuiltIn: Bool) -> DisplaySizeClass {
    guard isBuiltIn, let diagonalInches else { return .other }
    switch diagonalInches {
    case 12.5..<14: return .inch13
    case 14..<15: return .inch14
    case 15.5..<17.5: return .inch16
    default: return .other
    }
}

func displaySizeClass(for screen: NSScreen) -> DisplaySizeClass {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return .other }
    let id = CGDirectDisplayID(number.uint32Value)
    let size = CGDisplayScreenSize(id)
    let diagonal = hypot(size.width, size.height) / 25.4
    return displaySizeClass(diagonalInches: diagonal.isFinite ? diagonal : nil,
                            isBuiltIn: CGDisplayIsBuiltin(id) != 0)
}

func preferredCompactCardHeight(fieldHeight: CGFloat, display: DisplaySizeClass) -> CGFloat {
    let ratio: CGFloat
    switch display {
    case .inch13: ratio = 1.25
    case .inch14: ratio = 1.35
    case .inch16: ratio = 1.45
    case .other: ratio = 1.35
    }
    return min(96, max(72, (fieldHeight * ratio).rounded()))
}

func preferredSearchPanelFrame(_ frames: [CGRect], field: CGRect, visible: CGRect) -> CGRect? {
    let desiredWidth = field.width + 80
    return frames.filter { frame in
        frame.width >= field.width + 24 &&
        frame.width <= min(field.width + 250, visible.width * 0.95) &&
        frame.minX <= field.minX + 8 && frame.maxX >= field.maxX - 8 &&
        frame.minY <= field.minY + 12 && frame.maxY >= field.maxY - 12
    }.min { abs($0.width - desiredWidth) < abs($1.width - desiredWidth) }
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

func cardFrame(around window: CGRect, searchField: CGRect?, visible: CGRect,
               display: DisplaySizeClass = .other, campo: Bool = false) -> CGRect? {
    if campo {
        guard let field = searchField else { return nil }
        // Campo changes its CG window while suggestions expand. The field
        // supplies the vertical anchor; the outer search panel supplies both edges.
        let shell: CGRect
        if let panel = preferredSearchPanelFrame([window], field: field, visible: visible) {
            shell = panel
        } else {
            let leftInset = min(64, max(40, field.height * 1.05))
            let rightInset = min(24, max(18, field.height * 0.35))
            shell = CGRect(x: field.minX - leftInset, y: field.minY,
                           width: field.width + leftInset + rightInset, height: field.height)
        }
        let anchor = CGRect(x: shell.minX, y: field.minY, width: shell.width, height: field.height)
        return cardFrame(above: anchor, visible: visible, gap: 8, topInset: 4,
                         minimumHeight: 72,
                         maximumHeight: preferredCompactCardHeight(fieldHeight: field.height, display: display))
    }
    if let aboveWindow = cardFrame(above: window, visible: visible) { return aboveWindow }
    // Campo's result window reaches almost to the menu bar on macOS 27.
    // Keep the card above its input and reduce its height to the room available.
    // This intentionally has no side or below fallback.
    let field = searchField ?? window
    return cardFrame(above: field, visible: visible, gap: 8, topInset: 4,
                     minimumHeight: 72,
                     maximumHeight: preferredCompactCardHeight(fieldHeight: field.height, display: display))
}

func stabilizedCardFrame(_ proposed: CGRect, previous: CGRect?, visible: CGRect,
                         campo: Bool) -> CGRect {
    guard campo, let previous, visible.contains(previous),
          abs(previous.midX - proposed.midX) < 60,
          abs(previous.minY - proposed.minY) < 20 else { return proposed }
    return previous
}

// MARK: - 源自 Sources/RoundedMaterialView.swift

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
