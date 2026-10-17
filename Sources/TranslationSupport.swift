import Foundation
import Translation

// These value types also drive the menu, request identity and regression checks.
enum TranslationLanguage: String, CaseIterable, Codable, Sendable {
    case chinese = "zh-Hans", english = "en", japanese = "ja"
    var title: String {
        switch self { case .chinese: return "中文"; case .english: return "英文"; case .japanese: return "日文" }
    }
    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
}

enum LanguagePair: String, CaseIterable, Sendable {
    case chineseEnglish, chineseJapanese, englishJapanese
    var languages: (TranslationLanguage, TranslationLanguage) {
        switch self {
        case .chineseEnglish: return (.chinese, .english)
        case .chineseJapanese: return (.chinese, .japanese)
        case .englishJapanese: return (.english, .japanese)
        }
    }
    var title: String { "\(languages.0.title) ↔ \(languages.1.title)" }
    func contains(_ language: TranslationLanguage) -> Bool { language == languages.0 || language == languages.1 }
}

enum TranslationDirection: String, CaseIterable, Sendable {
    case automatic, forward, reverse
    func title(for pair: LanguagePair) -> String {
        switch self {
        case .automatic: return "自动识别 · 双向互译"
        case .forward: return "\(pair.languages.0.title) → \(pair.languages.1.title)"
        case .reverse: return "\(pair.languages.1.title) → \(pair.languages.0.title)"
        }
    }
}

struct TranslationRequest: Hashable, Sendable {
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage
    var title: String { "\(source.title) → \(target.title)" }
}

func translationInput(_ raw: String) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    guard !text.isEmpty, text.count <= 400,
          !text.contains("@"), !text.contains("/"), !text.contains("\\"),
          !text.lowercased().hasPrefix("www."),
          text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    return text
}

func translationRequest(for raw: String, pair: LanguagePair, direction: TranslationDirection) -> TranslationRequest? {
    guard let text = translationInput(raw) else { return nil }
    var hasHan = false, hasKana = false, hasLatin = false
    for scalar in text.unicodeScalars {
        let code = scalar.value
        if (0x3400...0x9FFF).contains(code) || (0x20000...0x3134F).contains(code) { hasHan = true }
        if (0x3040...0x30FF).contains(code) || (0xFF66...0xFF9F).contains(code) { hasKana = true }
        if (65...90).contains(code) || (97...122).contains(code) { hasLatin = true }
    }
    guard hasHan || hasKana || hasLatin else { return nil }
    let inferred: TranslationLanguage
    if hasKana { inferred = .japanese }
    else if hasHan {
        // Han-only words have no reliable Chinese/Japanese distinction. In the
        // Chinese/Japanese pair default to Chinese; the menu can override it.
        inferred = pair.contains(.chinese) ? .chinese : .japanese
    } else { inferred = .english }
    let source: TranslationLanguage
    switch direction {
    case .automatic:
        guard pair.contains(inferred) else { return nil }
        source = inferred
    case .forward: source = pair.languages.0
    case .reverse: source = pair.languages.1
    }
    let target = source == pair.languages.0 ? pair.languages.1 : pair.languages.0
    return TranslationRequest(text: text, source: source, target: target)
}

enum LocalTranslationError: LocalizedError {
    case needsLanguages, unsupported, needsNewerSystem, emptyResponse
    var errorDescription: String? {
        switch self {
        case .needsLanguages: return "先在菜单栏选择「下载中英日语言包…」，点击「一键准备中英日」。"
        case .unsupported: return "系统暂不支持这组翻译语言。"
        case .needsNewerSystem: return "自动翻译需要 macOS 26 或更新版本；英文离线查词仍可使用。"
        case .emptyResponse: return "未取得译文，请从菜单栏选择「重试当前翻译」。"
        }
    }
}

actor LocalTranslator {
    private var cache: [TranslationRequest: String] = [:]
    private var order: [TranslationRequest] = []

    func translate(_ request: TranslationRequest) async throws -> String {
        try Task.checkCancellation()
        if let cached = cache[request] { return cached }
        guard #available(macOS 26.0, *) else { throw LocalTranslationError.needsNewerSystem }
        let availability = LanguageAvailability()
        switch await availability.status(from: request.source.locale, to: request.target.locale) {
        case .installed: break
        case .supported: throw LocalTranslationError.needsLanguages
        case .unsupported: throw LocalTranslationError.unsupported
        @unknown default: throw LocalTranslationError.unsupported
        }
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: request.source.locale, target: request.target.locale)
        // Each job owns its session: canceling stale text also releases the native
        // translation request without touching a newer request's session.
        let text = try await withTaskCancellationHandler {
            let response = try await session.translate(request.text)
            try Task.checkCancellation()
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        } onCancel: {
            session.cancel()
        }
        guard !text.isEmpty else { throw LocalTranslationError.emptyResponse }
        cache[request] = text
        order.append(request)
        if order.count > 100 { cache.removeValue(forKey: order.removeFirst()) }
        return text
    }
}
