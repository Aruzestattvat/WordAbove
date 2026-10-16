import AppKit
import SwiftUI
import ApplicationServices
import ServiceManagement

@MainActor final class Model: ObservableObject {
    @Published var entry: Entry?
    @Published var trusted = AXIsProcessTrusted()
    @Published var loading = false
    @Published var online: Bool = UserDefaults.standard.object(forKey: "online") as? Bool ?? true {
        didSet { UserDefaults.standard.set(online, forKey: "online") }
    }
    @Published var enabled = true
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var note = ""
}

struct DictionaryCard: View {
    @ObservedObject var model: Model
    var body: some View {
        GeometryReader { geo in
            if let entry = model.entry {
                let compact = geo.size.height < 170
                VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.word).font(.system(size: compact ? 23 : 27, weight: .semibold, design: .rounded)).lineLimit(1)
                        if !entry.phonetic.isEmpty {
                            Text(phonetic(entry.phonetic)).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "character.book.closed").font(.system(size: 16, weight: .regular)).foregroundStyle(.tertiary)
                    }
                    Text(meaning(entry.translation))
                        .font(.system(size: 15)).lineSpacing(3).foregroundStyle(.primary)
                        .lineLimit(compact ? 1 : 2).frame(maxWidth: .infinity, alignment: .leading)
                    if geo.size.height >= 140 { Divider().opacity(0.65) }
                    if !entry.example.isEmpty {
                        Text(entry.example).font(.system(size: 13.5)).foregroundStyle(.secondary)
                            .lineSpacing(3).lineLimit(compact ? 2 : 3).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(model.loading ? "正在补充例句…" : "该词暂无可用例句")
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if !compact {
                        HStack {
                            Text("英汉词典")
                            Spacer()
                            Text(entry.source.isEmpty ? "离线释义 · ECDICT" : "ECDICT · " + entry.source + (entry.license.map { " · " + $0 } ?? ""))
                        }.font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, compact ? 12 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            }
        }
    }
    private func phonetic(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "/[]"))
            .replacingOccurrences(of: "'", with: "ˈ").replacingOccurrences(of: ",", with: "ˌ").replacingOccurrences(of: "ә", with: "ə")
        return "/" + clean + "/"
    }
    private func meaning(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let regular = lines.filter { !$0.hasPrefix("[") }
        return (regular.isEmpty ? lines : regular).prefix(3).joined(separator: "  ·  ")
    }
}

struct SetupView: View {
    @ObservedObject var model: Model
    let preview: () -> Void
    let permission: () -> Void
    let loginChanged: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "character.book.closed.fill").font(.system(size: 30)).foregroundStyle(.blue)
                    .frame(width: 62, height: 62).background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("词在上 · WordAbove").font(.system(size: 23, weight: .semibold))
                    Text("搜索照常，词义在上。").foregroundStyle(.secondary)
                }
            }
            Text("按 ⌘ 空格打开 Spotlight，输入英文单词。中文释义、音标和例句会出现在搜索框上方的独立卡片里。")
                .font(.system(size: 14)).lineSpacing(5)
            VStack(alignment: .leading, spacing: 12) {
                Label(model.trusted ? "辅助功能已授权" : "需要一次辅助功能授权", systemImage: model.trusted ? "checkmark.circle.fill" : "lock.circle")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(model.trusted ? .green : .primary)
                Text("用于读取 Spotlight 搜索词和窗口位置。应用不记录键盘，不读取其他应用文本，不保存搜索历史。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                if !model.trusted {
                    Button("打开辅助功能设置", action: permission).buttonStyle(.borderedProminent)
                    Text("在系统设置中打开「词在上」的开关；列表中没有时，点 + 添加此应用。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Toggle("缺少例句时联网补充", isOn: $model.online)
                Text("仅把当前已识别的英文单词发给 api.dictionaryapi.dev。关闭后仅使用离线词库；部分单词没有例句。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
                Toggle("登录时启动", isOn: Binding(get: { model.login }, set: loginChanged))
            }.toggleStyle(.checkbox).font(.system(size: 13))
            if !model.note.isEmpty { Text(model.note).font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack {
                Button("预览卡片", action: preview)
                Spacer()
                Text("状态栏菜单可暂停或退出").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }.padding(28).frame(width: 490).fixedSize(horizontal: false, vertical: true)
    }
}

class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    let observer = SpotlightObserver()
    let examples = ExampleService()
    lazy var dictionary = DictionaryStore(path: Bundle.main.path(forResource: "dictionary", ofType: "sqlite") ?? "")
    var statusItem: NSStatusItem!
    var panel: PassivePanel!
    var setup: NSWindow?
    var previewWindow: NSWindow?
    var timer: Timer?
    var lookupTask: Task<Void, Never>?
    var currentWord: String?
    var lastFrame: CGRect?
    var tickCount = 0
    var lastOnline = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "词在上")
        statusItem.button?.toolTip = "词在上 · Spotlight 英汉词典"
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.04
        if !model.trusted || CommandLine.arguments.contains("--settings") { showSetup() }
        if CommandLine.arguments.contains("--preview") { showPreview() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSetup(); return true }
    func applicationWillTerminate(_ notification: Notification) { lookupTask?.cancel(); timer?.invalidate() }
    func createPanel() {
        panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 206), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "词在上 · 单词释义"
        panel.level = .init(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = cardContent(model)
    }
    func cardContent(_ model: Model) -> NSView {
        let effect = RoundedMaterialView(frame: NSRect(x: 0, y: 0, width: 640, height: 206))
        let hosting = NSHostingView(rootView: DictionaryCard(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor), hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }
    func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "词在上 · WordAbove", action: nil, keyEquivalent: "")
        menu.addItem(title); menu.addItem(.separator())
        let toggle = NSMenuItem(title: model.enabled ? "暂停自动查词" : "恢复自动查词", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        for (title, selector) in [("设置…", #selector(showSetup)), ("预览卡片", #selector(showPreview)), ("词库来源与许可", #selector(showLicenses))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出词在上", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func toggleEnabled() { model.enabled.toggle(); hide(); rebuildMenu() }
    @objc func showLicenses() {
        if let url = Bundle.main.url(forResource: "Sources", withExtension: "html") { NSWorkspace.shared.open(url) }
    }
    @objc func showSetup() {
        if setup == nil {
            let view = SetupView(model: model, preview: { [weak self] in self?.showPreview() }, permission: { [weak self] in self?.openPermission() }, loginChanged: { [weak self] value in self?.setLogin(value) })
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "词在上"; window.contentView = hosting; window.isReleasedWhenClosed = false
            window.setContentSize(hosting.fittingSize); window.center(); setup = window
        }
        NSApp.activate(ignoringOtherApps: true); setup?.makeKeyAndOrderFront(nil)
    }
    func openPermission() {
        // Only called by a deliberate click in the app's setup screen.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.login = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { model.note = "请在系统设置 → 通用 → 登录项中允许词在上。" }
        } catch { model.note = "无法修改登录项：\(error.localizedDescription)" }
    }
    @objc func showPreview() {
        let sample = Model(); sample.entry = dictionary.lookup("serendipity")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 206), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "词在上 · 卡片预览"; window.contentView = cardContent(sample)
        window.isReleasedWhenClosed = false; window.center()
        previewWindow?.close(); previewWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func hide() {
        panel.orderOut(nil); lookupTask?.cancel(); lookupTask = nil
        currentWord = nil; lastFrame = nil; model.entry = nil; model.loading = false
    }
    func tick() {
        tickCount += 1
        if tickCount % 5 == 0 {
            let trusted = AXIsProcessTrusted()
            if model.trusted != trusted { model.trusted = trusted }
        }
        guard model.enabled, model.trusted else { if currentWord != nil { hide() }; return }
        guard let snapshot = observer.snapshot(), let word = normalizedWord(snapshot.text) else { if currentWord != nil { hide() }; return }
        guard let screen = NSScreen.screens.max(by: { $0.frame.intersection(snapshot.frame).area < $1.frame.intersection(snapshot.frame).area }),
              let frame = cardFrame(above: snapshot.frame, visible: screen.visibleFrame) else {
            if currentWord != nil { hide() }
            return
        }
        if lastFrame != frame { panel.setFrame(frame, display: true); lastFrame = frame }
        if lastOnline != model.online { lastOnline = model.online; currentWord = nil; lookupTask?.cancel() }
        guard currentWord != word else { return }
        currentWord = word
        lookupTask?.cancel(); model.loading = false; model.entry = nil; panel.orderOut(nil)
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, self.currentWord == word, let entry = self.dictionary.lookup(word) else { return }
            self.model.entry = entry
            self.panel.orderFrontRegardless()
            if self.model.online && (entry.example.isEmpty || entry.phonetic.isEmpty) {
                self.model.loading = true
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, self.currentWord == word else { return }
                let supplemented = await self.examples.supplement(entry)
                guard !Task.isCancelled, self.currentWord == word else { return }
                self.model.entry = supplemented; self.model.loading = false
            }
        }
    }
}

extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

@main struct WordAboveMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { selfTest(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    static func selfTest() {
        let store = DictionaryStore(path: Bundle.main.path(forResource: "dictionary", ofType: "sqlite") ?? "")
        for word in ["hello", "serendipity", "focus", "apple", "resilience", "beautiful", "dictionary"] {
            guard let entry = store.lookup(word), !entry.translation.isEmpty, !entry.phonetic.isEmpty, !entry.example.isEmpty else { fatalError("Missing entry: \(word)") }
        }
        precondition(normalizedWord("  Hello \n") == "hello")
        precondition(normalizedWord("user@example.com") == nil)
        precondition(normalizedWord("two words") == nil)
        precondition(normalizedWord("你好") == nil)
        precondition(normalizedWord("can't") == "can't")
        precondition(store.lookup("zzzzthisisnotaword") == nil)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let search = CGRect(x: 370, y: 300, width: 700, height: 300)
        let card = cardFrame(above: search, visible: screen)!
        precondition(card.minY > search.maxY && card.maxY < screen.maxY)
        precondition(card.minX == search.minX && card.maxX == search.maxX)
        let widerSearch = CGRect(x: 240, y: 300, width: 960, height: 300)
        let widerCard = cardFrame(above: widerSearch, visible: screen)!
        precondition(widerCard.minX == widerSearch.minX && widerCard.maxX == widerSearch.maxX)
        precondition(cardFrame(above: CGRect(x: 0, y: 800, width: 680, height: 60), visible: screen) == nil)
        let secondary = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        let secondaryCard = cardFrame(above: CGRect(x: -1000, y: 100, width: 680, height: 300), visible: secondary)!
        precondition(secondary.contains(secondaryCard))
        print("PASS: offline entries, IPA, Chinese meanings, examples, input filtering, missing words, above-window placement, screen edges, secondary display.")
    }
}
