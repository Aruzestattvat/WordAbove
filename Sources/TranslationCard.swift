import SwiftUI

struct TranslationCardContent {
    let request: TranslationRequest
    let text: String?
    let message: String?
    let dictionaryEntry: Entry?
}

struct TranslationCard: View {
    let content: TranslationCardContent
    let compact: Bool
    let tight: Bool
    let micro: Bool
    let copied: Bool
    let copyFeedbackAnimator: CopyFeedbackAnimator
    let onCopy: () -> Void
    let expanded: Bool
    let onToggleExpanded: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: tight ? 8 : 14) {
            Button(action: onCopy) {
                CopyFeedbackIcon(animator: copyFeedbackAnimator, tight: tight)
            }
            .buttonStyle(.plain)
            .disabled(content.text == nil)
            .help(copied ? "已复制译文" : "复制译文")
            .accessibilityLabel(copied ? "已复制译文" : "复制译文")
            VStack(alignment: .leading, spacing: micro ? 2 : (tight ? 3 : 8)) {
                if let entry = content.dictionaryEntry, !entry.translation.isEmpty, let translation = content.text {
                    if !micro {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(content.request.text)
                                .font(.system(size: tight ? 11 : 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if !tight {
                                Text(content.request.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: tight ? 7 : 10) {
                        Text(translation)
                            .font(.system(size: tight ? 17 : (compact ? 21 : 23), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if let phonetic = displayPhonetic(entry.phonetic) {
                            Text(phonetic)
                                .font(.system(size: tight ? 12 : 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button(action: onToggleExpanded) {
                            HStack(spacing: 4) {
                                if !tight { Text(expanded ? "收起" : "完整释义") }
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            }
                            .font(.system(size: tight ? 10 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(expanded ? "收起完整释义" : "查看完整释义")
                        .accessibilityLabel(expanded ? "收起完整释义" : "查看完整释义")
                    }
                    if expanded {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: tight ? 4 : 7) {
                                ForEach(Array(dictionaryLines(entry.translation).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: tight ? 12 : 14))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.automatic)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("词典释义")
                                .font(.system(size: tight ? 10 : 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                            Text(dictionaryLines(entry.translation).prefix(2).joined(separator: " · "))
                                .font(.system(size: tight ? 11 : 13))
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(compact ? 1 : 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    if tight && !micro {
                        Text(content.request.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(content.request.text)
                            .font(.system(size: tight ? 12 : 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(compact ? 1 : 2)
                        Spacer(minLength: 8)
                        if !tight {
                            Text(content.request.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if let translation = content.text {
                        Text(translation)
                            .font(.system(size: tight ? 16 : (compact ? 21 : 22), weight: .semibold))
                            .lineSpacing(tight ? 0 : 3)
                            .lineLimit(tight ? 1 : (compact ? 2 : 3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let message = content.message {
                        Text(message).font(.system(size: tight ? 11 : 12)).foregroundStyle(.secondary)
                            .lineLimit(tight ? 1 : (compact ? 2 : 3))
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在翻译…").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    if !compact {
                        Text("Apple 本机翻译").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
        }.padding(.horizontal, tight ? 16 : 20).padding(.vertical, micro ? 4 : (tight ? 6 : (compact ? 12 : 16)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
            .accessibilityElement(children: .contain)
            .transaction { $0.disablesAnimations = true }
    }

    private func dictionaryLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
