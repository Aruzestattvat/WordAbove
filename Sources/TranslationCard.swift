import SwiftUI

struct TranslationCardContent {
    let request: TranslationRequest
    let text: String?
    let message: String?
}

struct TranslationCard: View {
    let content: TranslationCardContent
    let compact: Bool
    let tight: Bool
    let micro: Bool
    let copied: Bool
    let copyFeedbackAnimator: CopyFeedbackAnimator
    let onCopy: () -> Void
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
        }.padding(.horizontal, tight ? 16 : 20).padding(.vertical, micro ? 4 : (tight ? 6 : (compact ? 12 : 16)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
            .accessibilityElement(children: .combine)
    }
}
