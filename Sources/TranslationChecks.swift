import Foundation

func checkTranslationRouting() {
    precondition(spotlightHostBundleIDs(macOSMajor: 26) == ["com.apple.Spotlight"])
    precondition(spotlightHostBundleIDs(macOSMajor: 27) == ["com.apple.campo", "com.apple.Spotlight"])
    precondition(mayReadSpotlightHost(bundleID: "com.apple.campo", isActive: false, macOSMajor: 27))
    precondition(!mayReadSpotlightHost(bundleID: "com.apple.campo", isActive: true, macOSMajor: 27))
    precondition(!mayReadSpotlightHost(bundleID: "com.apple.campo", isActive: false, macOSMajor: 26))
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

@MainActor
func checkPreparationModel() {
    let suite = "WordAboveSelfTest"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let model = PreparationModel(defaults: defaults)
    precondition(!model.allVerified && model.readyCount == 0 && model.currentStep == nil)

    model.startPreparing(skipDiskCheck: true)
    precondition(model.isRunning && model.currentStep != nil && model.completed == 0)
    let firstTask = model.taskID
    model.markActivity("checking")
    model.finish(taskID: firstTask, error: nil)
    precondition(model.completed == 1 && model.readyCount == 1)
    precondition(defaults.stringArray(forKey: PreparationModel.verifiedKey)?.count == 1)

    // Verified directions survive a relaunch.
    let reloaded = PreparationModel(defaults: defaults)
    precondition(reloaded.readyCount == 1)

    // Stale callbacks from a previous run must be ignored.
    model.finish(taskID: "bogus", error: nil)
    precondition(model.completed == 1 && model.readyCount == 1)

    // Pause keeps progress; resume continues from the same step.
    model.pause()
    precondition(model.phase == .paused)
    let pausedTask = model.taskID
    model.finish(taskID: pausedTask, error: nil)
    precondition(model.completed == 1)
    model.startPreparing(skipDiskCheck: true)
    precondition(model.isRunning && model.completed == 1)

    // A network failure must be classified and must keep earlier progress.
    model.finish(taskID: model.taskID, error: URLError(.notConnectedToInternet))
    precondition(!model.isRunning && model.readyCount == 1)
    precondition(model.lastFailure?.title.contains("网络") == true)
    precondition(model.diagnostics().contains("语言包"))

    precondition(PreparationModel.failure(for: PreparationTimeout()).title.contains("超时"))
    precondition(PreparationModel.failure(for: NSError(domain: NSPOSIXErrorDomain, code: 28)).title.contains("磁盘"))
    precondition(PreparationModel.failure(for: URLError(.timedOut)).title.contains("网络"))
    precondition(PreparationModel.failure(for: NSError(domain: "TranslationErrorDomain", code: 1)).title.contains("翻译"))

    defaults.removePersistentDomain(forName: suite)
    print("PASS: preparation persistence, error classification, stale callbacks, pause/resume.")
}
