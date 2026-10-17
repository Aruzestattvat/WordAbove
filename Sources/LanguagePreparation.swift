import Foundation

/// A run owns each callback so cancellation/retry cannot accept a stale result.
struct LanguagePreparation {
    struct Step: Identifiable {
        let source: TranslationLanguage
        let target: TranslationLanguage
        var id: String { source.rawValue + ":" + target.rawValue }
        var title: String { "\(source.title) → \(target.title)" }
        var sample: String {
            switch source {
            case .chinese: return "你好"
            case .english: return "Hello"
            case .japanese: return "こんにちは"
            }
        }
    }
    enum Phase: Equatable { case idle, running, failed(String), paused, ready }
    static let steps: [Step] = [
        .init(source: .chinese, target: .english), .init(source: .english, target: .chinese),
        .init(source: .english, target: .japanese), .init(source: .japanese, target: .english),
        .init(source: .chinese, target: .japanese), .init(source: .japanese, target: .chinese)
    ]
    private(set) var phase: Phase = .idle
    private(set) var completed = 0
    private(set) var run = UUID()
    var isRunning: Bool { phase == .running }
    var current: Step? { isRunning ? Self.steps[completed] : nil }
    var taskID: String { "\(run.uuidString):\(completed)" }

    mutating func start() {
        guard !isRunning else { return }
        if phase == .ready { completed = 0 }
        run = UUID(); phase = .running
    }
    mutating func finish(taskID: String, error: String? = nil) {
        guard isRunning, taskID == self.taskID else { return }
        if let error { phase = .failed(error); return }
        completed += 1
        if completed == Self.steps.count { phase = .ready }
    }
    mutating func cancel() {
        guard isRunning else { return }
        run = UUID(); phase = .paused
    }
}
