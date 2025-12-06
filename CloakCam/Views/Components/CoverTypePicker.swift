import SwiftUI

struct CoverTypePicker: View {
    @Binding var selectedType: CoverType
    @Binding var selectedEmoji: String
    let onEmojiPickerTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(CoverType.allCases) { type in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedType = type
                    }
                    if type == .emoji {
                        onEmojiPickerTap()
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(selectedType == type ? Color.blue : Color.gray.opacity(0.2))
                                .frame(width: 50, height: 50)

                            if type == .emoji {
                                Text(selectedEmoji)
                                    .font(.system(size: 24))
                            } else {
                                Image(systemName: type.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedType == type ? .white : .primary)
                            }
                        }

                        Text(type.rawValue)
                            .font(.caption)
                            .fontWeight(selectedType == type ? .semibold : .regular)
                            .foregroundColor(selectedType == type ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
