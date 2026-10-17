import Foundation

func checkTranslationRouting() {
    let cases: [(String, LanguagePair, TranslationDirection, TranslationLanguage, TranslationLanguage)] = [
        ("你好", .chineseEnglish, .automatic, .chinese, .english),
        ("我今天很开心。", .chineseEnglish, .automatic, .chinese, .english),
        ("Hello, nice to meet you.", .chineseEnglish, .automatic, .english, .chinese),
        ("谢谢", .chineseJapanese, .automatic, .chinese, .japanese),
        ("ありがとうございます", .chineseJapanese, .automatic, .japanese, .chinese),
        ("学校", .chineseJapanese, .automatic, .chinese, .japanese),
        ("学校", .chineseJapanese, .reverse, .japanese, .chinese),
        ("Good morning", .englishJapanese, .automatic, .english, .japanese),
        ("おはようございます", .englishJapanese, .automatic, .japanese, .english),
        ("東京", .englishJapanese, .automatic, .japanese, .english),
        ("ｺﾝﾆﾁﾊ", .englishJapanese, .automatic, .japanese, .english),
        ("我用 Mac 学英语", .chineseEnglish, .automatic, .chinese, .english),
        ("你好", .chineseEnglish, .forward, .chinese, .english)
    ]
    for (text,pair,direction,source,target) in cases {
        let result = translationRequest(for: text, pair: pair, direction: direction)
        precondition(result?.source == source && result?.target == target, "Incorrect translation direction: \(text)")
    }
    for invalid in ["", "   ", "12345", "1+2", "https://example.com", "user@example.com", "/Users/me/file.txt", "www.example.com", "你好\nhello", String(repeating: "中", count: 401)] {
        precondition(translationRequest(for: invalid, pair: .chineseEnglish, direction: .automatic) == nil, "Unexpected translation: \(invalid.prefix(50))")
    }
    precondition(translationRequest(for: "こんにちは", pair: .chineseEnglish, direction: .automatic) == nil)
    precondition(translationRequest(for: "hello", pair: .chineseJapanese, direction: .automatic) == nil)
    precondition(translationRequest(for: "  Hello  ", pair: .chineseEnglish, direction: .automatic)?.text == "Hello")
    precondition(translationRequest(for: String(repeating: "中", count: 400), pair: .chineseEnglish, direction: .automatic) != nil)
    let a = translationRequest(for: "学校", pair: .chineseJapanese, direction: .automatic)!
    let b = translationRequest(for: "学校", pair: .chineseJapanese, direction: .reverse)!
    precondition(a != b, "Request identity must distinguish direction")
    print("PASS: all six translation directions, phrases, kana/Han ambiguity override, language-pair isolation, input exclusions and text length.")
}

func checkLanguagePreparation() {
    precondition(LanguagePreparation.steps.count == 6)
    precondition(Set(LanguagePreparation.steps.map(\.id)).count == 6)
    for source in TranslationLanguage.allCases {
        for target in TranslationLanguage.allCases where source != target {
            precondition(LanguagePreparation.steps.contains { $0.source == source && $0.target == target })
        }
    }
    var plan = LanguagePreparation()
    precondition(plan.current == nil)
    plan.start()
    let first = plan.taskID
    plan.start() // Repeated clicks must not restart an active run.
    precondition(plan.taskID == first)
    plan.finish(taskID: first)
    precondition(plan.completed == 1 && plan.isRunning)
    let failed = plan.taskID
    plan.finish(taskID: failed, error: "Network unavailable")
    precondition(plan.completed == 1 && !plan.isRunning)
    plan.start()
    precondition(plan.completed == 1 && plan.taskID != failed)
    plan.finish(taskID: failed) // Delayed completion from the previous attempt.
    precondition(plan.completed == 1)
    let cancelled = plan.taskID
    plan.cancel()
    plan.finish(taskID: cancelled)
    precondition(plan.phase == .paused && plan.completed == 1)
    plan.start()
    while plan.isRunning { plan.finish(taskID: plan.taskID) }
    precondition(plan.phase == .ready && plan.completed == 6 && plan.current == nil)
    plan.start()
    precondition(plan.completed == 0 && plan.isRunning)
    plan.finish(taskID: cancelled, error: "Old cancellation")
    precondition(plan.isRunning)
    print("PASS: six-direction preparation queue, failure/retry, cancellation, stale callbacks and recheck.")
}
