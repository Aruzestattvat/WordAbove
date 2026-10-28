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
    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 3 : (compact ? 7 : 10)) {
            HStack {
                Text(content.request.title).font(.system(size: tight ? 10 : 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !tight { Image(systemName: "character.bubble").foregroundStyle(.tertiary) }
            }
            Text(content.request.text).font(.system(size: tight ? 12 : (compact ? 13 : 14)))
                .foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
            if let translation = content.text {
                Text(translation).font(.system(size: tight ? 15 : (compact ? 17 : 20), weight: .medium))
                    .lineSpacing(tight ? 0 : 4).lineLimit(tight ? 1 : (compact ? 2 : 3))
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
            Spacer(minLength: 0)
            if !compact {
                Text("Apple 本机翻译").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, tight ? 16 : 20).padding(.vertical, tight ? 6 : (compact ? 12 : 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
}
