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

final class DictionaryStore {
    private var db: OpaquePointer?
    init(path: String) { sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) }
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
            if updated.phonetic.isEmpty { updated.phonetic = results.compactMap(\.phonetic).first ?? results.flatMap { $0.phonetics ?? [] }.compactMap(\.text).first ?? "" }
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

// MARK: - 源自 Sources/SpotlightObserver.swift（仅取与窗口定位有关的部分）

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
