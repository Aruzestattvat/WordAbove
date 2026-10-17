import SwiftUI
@preconcurrency import Translation

@available(macOS 26.0, *)
struct LanguageSetupView: View {
    @ObservedObject var model: Model
    let changed: () -> Void
    @State private var preparation = LanguagePreparation()
    @State private var activity = ""

    init(model: Model, changed: @escaping () -> Void, preparation: LanguagePreparation = LanguagePreparation()) {
        self.model = model
        self.changed = changed
        _preparation = State(initialValue: preparation)
    }

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
            Text("一次准备，三种语言").font(.headline)
            Text("自动下载缺少的中文、英文、日文语言包，并验证全部六个翻译方向。已安装的语言包直接复用，无需逐组选择。")
                .font(.system(size: 13)).lineSpacing(4)
            HStack {
                Button(buttonTitle) { activity = "正在检查语言包…"; preparation.start() }
                    .buttonStyle(.borderedProminent).disabled(preparation.isRunning)
                if preparation.isRunning {
                    ProgressView().controlSize(.small)
                    Button("取消") { preparation.cancel() }
                }
            }
            Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("语言包由 macOS 下载，系统可能要求确认。下载后可离线翻译；语言包不随本应用分发。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .padding(28).frame(width: 490, height: 500, alignment: .topLeading)
        .onChange(of: model.pair) { model.direction = .automatic; changed() }
        .onChange(of: model.direction) { changed() }
        .onDisappear { preparation.cancel() }
        .background {
            if let step = preparation.current {
                let taskID = preparation.taskID
                LanguagePreparationTask(step: step, progress: { message in
                    guard preparation.isRunning, preparation.taskID == taskID else { return }
                    activity = message
                }, finished: { error in
                    guard preparation.isRunning, preparation.taskID == taskID else { return }
                    preparation.finish(taskID: taskID, error: error)
                    if preparation.phase == .ready {
                        model.translationRevision += 1; changed()
                    }
                }).id(taskID)
            }
        }
    }
    private var buttonTitle: String {
        switch preparation.phase {
        case .idle: return "一键准备中英日"
        case .running: return "正在准备…"
        case .failed: return "重试未完成部分"
        case .paused: return "继续准备"
        case .ready: return "重新检查语言包"
        }
    }
    private var status: String {
        switch preparation.phase {
        case .idle: return "首次使用请点击上方按钮，并按系统提示允许下载。"
        case .running: return "\(preparation.completed + 1)/6 · \(preparation.current!.title)\n\(activity)"
        case .failed(let message): return "已验证 \(preparation.completed)/6 · 尚未完成\n\(message)\n可重试，已下载的语言包会保留。"
        case .paused: return "已暂停，已验证 \(preparation.completed)/6。再次点击即可继续。"
        case .ready: return "中英日已就绪 · 6/6\n按 ⌘ 空格输入文字，即可使用所选语言对。"
        }
    }
}

/// A separate view gives every direction its own SwiftUI-managed session lifetime.
@available(macOS 26.0, *)
private struct LanguagePreparationTask: View {
    let step: LanguagePreparation.Step
    let progress: (String) -> Void
    let finished: (String?) -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(.init(source: step.source.locale, target: step.target.locale)) { session in
                do {
                    try await withTaskCancellationHandler {
                        let availability = await LanguageAvailability().status(from: step.source.locale, to: step.target.locale)
                        try Task.checkCancellation()
                        switch availability {
                        case .installed:
                            progress("语言包已安装，正在验证翻译…")
                        case .supported:
                            progress("正在准备语言包，请按系统提示允许下载…")
                            try await session.prepareTranslation()
                        case .unsupported:
                            throw LocalTranslationError.unsupported
                        @unknown default:
                            throw LocalTranslationError.unsupported
                        }
                        // Preparation may return before downloading completes. A real
                        // translation ensures the model is usable before advancing.
                        let response = try await session.translate(step.sample)
                        try Task.checkCancellation()
                        guard !response.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw LocalTranslationError.emptyResponse
                        }
                    } onCancel: { session.cancel() }
                    finished(nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    finished(error.localizedDescription)
                }
            }
    }
}
