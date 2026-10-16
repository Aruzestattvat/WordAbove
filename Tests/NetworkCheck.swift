import Foundation

/// 联网补充检查。需要一个可读的 dictionary.sqlite，按以下顺序取路径：
///   1) 环境变量 WORDABOVE_DICTIONARY
///   2) 第一个命令行参数
///   3) /Applications/词在上.app/Contents/Resources/dictionary.sqlite
@main struct NetworkCheck {
    static func main() async {
        let path = ProcessInfo.processInfo.environment["WORDABOVE_DICTIONARY"]
            ?? CommandLine.arguments.dropFirst().first
            ?? "/Applications/词在上.app/Contents/Resources/dictionary.sqlite"
        let store = DictionaryStore(path: path)
        guard var entry = store.lookup("test") else {
            fatalError("词库中没有 test 词条，或路径不可读：\(path) —— 请用 WORDABOVE_DICTIONARY 指定 dictionary.sqlite")
        }
        entry.example = ""
        let result = await ExampleService().supplement(entry)
        precondition(!result.example.isEmpty, "Live API returned no example for test")
        precondition(result.source == "Wiktionary")
        precondition(result.sourceURL?.hasPrefix("https://") == true)
        print("PASS: HTTPS example lookup, JSON parsing, source URL, license: \(result.license ?? "none")")
        print(result.example)
    }
}
