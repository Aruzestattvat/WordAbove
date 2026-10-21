import AppKit
import SwiftUI
@preconcurrency import Translation

@available(macOS 26.0, *)
struct LanguageSetupView: View {
    @ObservedObject var model: Model
    @ObservedObject var preparation: PreparationModel
    let changed: () -> Void

    private static let languageSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自动互译").font(.system(size: 24, weight: .semibold))
            Text("选择两种语言，输入其中一种，卡片自动译成另一种。")
                .foregroundStyle(.secondary)
            Picker("翻译语言", selection: $model.pair) {
                ForEach(LanguagePair.allCases, id: \.self) { pair in Text(pair.title).tag(pair) }
            }
            Picker("翻译方向", selection: $model.direction) {
                ForEach(TranslationDirection.allCases, id: \.self) { direction in
                    Text(direction.title(for: model.pair)).tag(direction)
                }
            }
            Text("中日互译时，仅含汉字的词默认按中文处理。需要译成中文时，可以在菜单栏指定「日文 → 中文」。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)

            Divider()

            // MARK: 语言包
            HStack(alignment: .firstTextBaseline) {
                Text("中英日语言包").font(.headline)
                Spacer()
                Text(preparation.allVerified ? "已就绪 \(preparation.readyCount)/6"
                                             : "已就绪 \(preparation.readyCount)/6 · 还差 \(preparation.remainingCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(preparation.allVerified ? Color.green : .secondary)
            }
            ProgressView(value: Double(preparation.readyCount), total: 6)
                .progressViewStyle(.linear)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(LanguagePreparation.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(index: index, step: step)
                }
            }
            .padding(.vertical, 2)

            statusSection

            HStack(spacing: 10) {
                Button(primaryTitle) { preparation.startPreparing() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preparation.isRunning || preparation.checking)
                if preparation.isRunning {
                    Button("取消") { preparation.pause() }
                }
                Button("打开语言设置") { openLanguageSettings() }
                if preparation.lastFailure != nil {
                    Button("复制诊断信息") { copyDiagnostics() }
                }
                Spacer()
            }

            Text("语言包由 macOS 下载与保管，首次约 0.9 GB（含系统语音模型），慢网可能需要 10–30 分钟。下载期间请保持此窗口打开；系统不提供下载百分比，可在「语言设置 → 翻译语言」查看系统进度。下载后可离线翻译，语言包不随本应用分发。")
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.pair) { model.direction = .automatic; changed() }
        .onChange(of: model.direction) { changed() }
        .onChange(of: preparation.phase) { _, phase in
            guard phase == .ready else { return }
            model.translationRevision += 1
            changed()
        }
        .task { await preparation.refresh() }
        .background {
            if let step = preparation.currentStep {
                let taskID = preparation.taskID
                PreparationStepTask(
                    step: step,
                    timeout: PreparationModel.stepTimeout,
                    progress: { message in
                        Task { @MainActor in
                            guard preparation.taskID == taskID, preparation.isRunning else { return }
                            preparation.markActivity(message)
                        }
                    },
                    finished: { error in
                        Task { @MainActor in
                            preparation.finish(taskID: taskID, error: error)
                        }
                    }
                )
                .id(taskID)
            }
        }
    }

    // MARK: 子视图

    @ViewBuilder
    private func stepRow(index: Int, step: LanguagePreparation.Step) -> some View {
        let done = preparation.verified.contains(step.id)
        let active = preparation.isRunning && preparation.completed == index
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle").foregroundStyle(.quaternary)
            }
            Text(step.title).font(.system(size: 12))
                .foregroundStyle(done || active ? .primary : .secondary)
            Spacer()
            if done { Text("已验证").font(.system(size: 10)).foregroundStyle(.tertiary) }
            else if active { Text("进行中").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if preparation.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = preparation.startedAt.map { Int(context.date.timeIntervalSince($0)) } ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(min(preparation.completed + 1, 6))/6 步 · \(preparation.currentStep?.title ?? "") · 已用 \(elapsed / 60) 分 \(elapsed % 60) 秒")
                        .font(.system(size: 12, weight: .medium))
                    Text(preparation.activity.isEmpty ? "正在等待系统返回…" : preparation.activity)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let hint = timeoutHint(seconds: elapsed) {
                        Text(hint).font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let failure = preparation.lastFailure {
            VStack(alignment: .leading, spacing: 5) {
                Label(failure.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text(failure.advice).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if preparation.allVerified {
            Label("中英日已就绪 · 6/6，按 ⌘ 空格输入文字即可使用", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        } else {
            Text("首次使用请点上方按钮。应用会请求 macOS 下载缺少的语言包，并逐一验证六个翻译方向。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 文案与动作

    private var primaryTitle: String {
        if preparation.isRunning { return "正在准备…" }
        if preparation.allVerified { return "重新检查语言包" }
        if preparation.lastFailure != nil { return "重试未完成部分" }
        if preparation.phase == .paused { return "继续准备" }
        return "一键准备中英日"
    }

    private func timeoutHint(seconds: Int) -> String? {
        if seconds >= 600 {
            return "已等待超过 10 分钟：多为网络较慢或系统下载/确认被遮挡。可继续等待，或稍后重试（已下载部分会保留）。"
        }
        if seconds >= 180 {
            return "仍在等待系统下载或确认。若系统弹出下载提示，请点击允许。"
        }
        return nil
    }

    private func openLanguageSettings() {
        guard let url = Self.languageSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyDiagnostics() {
        let text = preparation.diagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        preparation.markActivity("诊断信息已复制")
    }
}

/// 每步独立会话；超时由 `withTimeout` 中止等待（不删除系统已落盘资产）。
@available(macOS 26.0, *)
private struct PreparationStepTask: View {
    let step: LanguagePreparation.Step
    let timeout: TimeInterval
    let progress: (String) -> Void
    let finished: (Error?) -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(.init(source: step.source.locale, target: step.target.locale)) { session in
                do {
                    try await withTimeout(seconds: timeout) {
                        let availability = await LanguageAvailability()
                            .status(from: step.source.locale, to: step.target.locale)
                        try Task.checkCancellation()
                        switch availability {
                        case .installed:
                            progress("语言包已安装，正在验证翻译…")
                        case .supported:
                            progress("正在请求系统下载语言包；如弹出确认请点「允许」。")
                            try await session.prepareTranslation()
                        case .unsupported:
                            throw LocalTranslationError.unsupported
                        @unknown default:
                            throw LocalTranslationError.unsupported
                        }
                        // prepareTranslation may return before assets are usable.
                        try Task.checkCancellation()
                        progress("正在验证翻译…")
                        let response = try await session.translate(step.sample)
                        try Task.checkCancellation()
                        let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { throw LocalTranslationError.emptyResponse }
                    }
                    finished(nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    finished(error)
                }
            }
    }
}

/// 让 `prepareTranslation()` / `translate()` 不会无限挂起。
func withTimeout<T>(seconds: TimeInterval, _ body: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PreparationTimeout()
        }
        guard let result = try await group.next() else { throw PreparationTimeout() }
        group.cancelAll()
        return result
    }
}
