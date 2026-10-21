import Combine
import Foundation
import Translation

// MARK: - 纯状态机（自检覆盖）

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

// MARK: - 超时

/// 系统长时间不返回时用来中止等待；不会中止系统已开始落盘的资产下载。
struct PreparationTimeout: LocalizedError {
    var errorDescription: String? { "系统长时间未完成语言包准备（超过 45 分钟）" }
}

// MARK: - 可行动的错误归因

struct PreparationFailure: Equatable {
    let title: String
    let advice: String
    let detail: String
    var retryable: Bool { true }
}

// MARK: - 可观察的准备控制器

/// Owns the six-direction preparation run, persists what has been verified, and turns
/// framework errors into actionable messages. All mutation happens on the main actor;
/// the `translationTask` callbacks are forwarded here via `Task { @MainActor in … }`.
@MainActor
final class PreparationModel: ObservableObject {
    static let verifiedKey = "preparedDirectionIDs"
    /// 单方向等待上限。GB 级下载在慢网下可能很久，但不能无限挂起。
    static let stepTimeout: TimeInterval = 45 * 60
    /// 下载 919 MB + 解压到 1.7 GB，留出余量。
    static let requiredFreeBytes: Int64 = 3_000_000_000

    @Published private(set) var plan = LanguagePreparation()
    @Published private(set) var verified: Set<String>
    @Published private(set) var lastFailure: PreparationFailure?
    @Published private(set) var startedAt: Date?
    @Published private(set) var freeSpaceBytes: Int64?
    @Published private(set) var checking = false
    @Published var activity = ""

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.verified = Set(defaults.stringArray(forKey: Self.verifiedKey) ?? [])
    }

    // MARK: 派生状态

    var isRunning: Bool { plan.isRunning }
    var phase: LanguagePreparation.Phase { plan.phase }
    var currentStep: LanguagePreparation.Step? { plan.current }
    var taskID: String { plan.taskID }
    var completed: Int { plan.completed }
    var readyCount: Int { LanguagePreparation.steps.filter { verified.contains($0.id) }.count }
    var allVerified: Bool { readyCount >= LanguagePreparation.steps.count }
    var remainingCount: Int { LanguagePreparation.steps.count - readyCount }

    var phaseText: String {
        switch plan.phase {
        case .idle: return "未检查"
        case .running: return "准备中（第 \(min(plan.completed + 1, 6))/6 步）"
        case .failed: return "已中断"
        case .paused: return "已暂停"
        case .ready: return "已就绪"
        }
    }

    // MARK: 动作

    /// 先做磁盘预检再启动；`skipDiskCheck` 仅供自检使用。
    func startPreparing(skipDiskCheck: Bool = false) {
        guard !plan.isRunning else { return }
        freeSpaceBytes = Self.availableSpace()
        if !skipDiskCheck, let bytes = freeSpaceBytes, bytes < Self.requiredFreeBytes {
            lastFailure = PreparationFailure(
                title: "磁盘空间不足",
                advice: "语言包需要约 3 GB 可用空间（当前 \(Self.gigabytes(bytes))）。清理后重试。",
                detail: "free=\(bytes)")
            return
        }
        lastFailure = nil
        activity = "正在检查语言包…"
        startedAt = Date()
        plan.start()
    }

    func pause() {
        guard plan.isRunning else { return }
        plan.cancel()
        activity = "已暂停"
    }

    func markActivity(_ text: String) {
        activity = text
    }

    /// `error` 为 nil 表示该方向验证成功。
    func finish(taskID: String, error: Error?) {
        guard plan.isRunning, taskID == plan.taskID else { return }
        if let error {
            if error is CancellationError { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            let failure = Self.failure(for: error)
            lastFailure = failure
            activity = ""
            plan.finish(taskID: taskID, error: failure.title)
            return
        }
        if let step = plan.current {
            verified.insert(step.id)
            save()
        }
        plan.finish(taskID: taskID)
        activity = ""
    }

    /// 仅查询可用性，不触发下载：用于启动/打开面板时恢复"已就绪 N/6"。
    func refresh() async {
        guard #available(macOS 26.0, *) else { return }
        checking = true
        defer { checking = false }
        let availability = LanguageAvailability()
        var installed = Set<String>()
        for step in LanguagePreparation.steps {
            if await availability.status(from: step.source.locale, to: step.target.locale) == .installed {
                installed.insert(step.id)
            }
        }
        let merged = verified.union(installed)
        if merged != verified {
            verified = merged
            save()
        }
    }

    func save() {
        defaults.set(Array(verified).sorted(), forKey: Self.verifiedKey)
    }

    // MARK: 诊断

    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let free = freeSpaceBytes.map { Self.gigabytes($0) } ?? "未知"
        var lines = [
            "WordAbove \(version) (build \(build))",
            "macOS: \(os)",
            "语言包: 已验证 \(readyCount)/6，阶段 \(phaseText)",
            "磁盘可用: \(free)"
        ]
        if let step = currentStep, isRunning { lines.append("当前方向: \(step.title)") }
        if let failure = lastFailure { lines.append("最近错误: \(failure.title) — \(failure.detail)") }
        return lines.joined(separator: "\n")
    }

    // MARK: 错误归因

    static func failure(for error: Error) -> PreparationFailure {
        let raw = "\(type(of: error)): \(error.localizedDescription)"
        if error is PreparationTimeout {
            return PreparationFailure(
                title: "准备超时",
                advice: "系统长时间没有返回。请检查网络后重试；已下载的语言包会保留。可在「系统设置 → 通用 → 语言和地区 → 翻译语言」查看系统级下载状态。",
                detail: raw)
        }
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return PreparationFailure(
                title: "网络连接失败",
                advice: "无法访问 Apple 的语言包服务器。请检查网络；若使用 VPN 或代理，尝试关闭或切换为全局模式后重试。已下载的部分会保留。",
                detail: raw)
        case NSPOSIXErrorDomain where nsError.code == 28,
             NSCocoaErrorDomain where nsError.code == NSFileWriteOutOfSpaceError:
            return PreparationFailure(
                title: "磁盘空间不足",
                advice: "语言包解压后约 1.7 GB，请至少保留 3 GB 可用空间后重试。",
                detail: raw)
        case "TranslationErrorDomain":
            return PreparationFailure(
                title: "系统翻译服务返回错误",
                advice: "可能是语言包下载被中断或系统确认未通过。可先在「系统设置 → 通用 → 语言和地区 → 翻译语言」确认语言已安装，再回来点「重试未完成部分」。",
                detail: raw)
        default:
            return PreparationFailure(
                title: "准备失败",
                advice: "请重试；若反复失败，点「复制诊断信息」把内容发给开发者。已下载的语言包不会丢失。",
                detail: raw)
        }
    }

    // MARK: 工具

    static func availableSpace() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return bytes
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let number = attrs[.systemFreeSize] as? NSNumber {
            return number.int64Value
        }
        return nil
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
