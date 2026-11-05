import Foundation
import SQLite3

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

func englishTranslationHeadword(_ translation: String) -> String? {
    let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return normalizedWord(trimmed)
}

func displayPhonetic(_ raw: String) -> String? {
    for variant in raw.split(separator: ";", omittingEmptySubsequences: true) {
        let clean = String(variant)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/[]")))
            .replacingOccurrences(of: "'", with: "ˈ")
            .replacingOccurrences(of: ",", with: "ˌ")
            .replacingOccurrences(of: "ә", with: "ə")
            .replacingOccurrences(of: ":", with: "ː")
        guard !clean.isEmpty, clean.count <= 64,
              !clean.hasPrefix("-"), !clean.hasPrefix("‐"), !clean.hasPrefix("–"),
              !clean.hasSuffix("-"), !clean.hasSuffix("‐"), !clean.hasSuffix("–"),
              clean.rangeOfCharacter(from: CharacterSet(charactersIn: "/[]?@�^\\0123456789")) == nil,
              clean.rangeOfCharacter(from: .uppercaseLetters) == nil,
              !clean.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }),
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
        return "/" + clean + "/"
    }
    return nil
}

func firstDictionaryMeaning(_ translation: String) -> String? {
    let lines = translation.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard var line = lines.first(where: { !$0.hasPrefix("[") }) ?? lines.first else { return nil }
    // ECDICT usually starts with a part of speech, followed by comma- or
    // semicolon-separated meanings. The copy action keeps only the first one.
    line = line.replacingOccurrences(of: "^(?:(?:n|v|vt|vi|adj|adv|art|prep|pron|conj|interj|int|num|abbr|aux|a|pl)\\.\\s*)+",
                                     with: "", options: [.regularExpression, .caseInsensitive])
    line = line.replacingOccurrences(of: "^\\[[^]]+\\]\\s*", with: "", options: .regularExpression)
    let first = line.components(separatedBy: CharacterSet(charactersIn: ",，;；、"))
        .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return first.isEmpty ? nil : first
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
        let word = value(0)
        // ECDICT's notation for this entry is not IPA. Use the complete UK
        // pronunciation; online suffix-only variants are rejected above.
        let phonetic = word == "virtue" ? "/ˈvɜː.tʃuː/" : value(1)
        return Entry(word: word, phonetic: phonetic, translation: value(2), definition: value(3), example: value(4), source: value(5))
    }
}

struct APIEntry: Decodable {
    struct Phonetic: Decodable { let text: String?; let audio: String? }
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

func preferredOnlinePhonetic(_ results: [APIEntry]) -> String? {
    let phonetics = results.flatMap { $0.phonetics ?? [] }
    let candidates = phonetics.filter { !($0.audio ?? "").isEmpty }.compactMap(\.text)
        + phonetics.compactMap(\.text)
        + results.compactMap(\.phonetic)
    return candidates.first(where: { displayPhonetic($0) != nil })
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
            if let phonetic = preferredOnlinePhonetic(results) {
                updated.phonetic = phonetic
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
