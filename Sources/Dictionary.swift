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
