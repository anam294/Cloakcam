import SwiftUI

struct EmojiPicker: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss

    private let emojis: [[String]] = [
        // Faces
        ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂"],
        ["🙂", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗"],
        ["😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔"],
        ["😎", "🤓", "🧐", "🥳", "🤯", "😱", "😨", "😰"],
        ["😈", "👿", "💀", "☠️", "👻", "👽", "🤖", "🎃"],
        // Animals
        ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼"],
        ["🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🙈"],
        // Objects & Symbols
        ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
        ["⭐", "🌟", "✨", "💫", "🔥", "💥", "❄️", "🌈"],
        ["🎭", "🎪", "🎨", "🎬", "🎤", "🎧", "🎮", "🎯"]
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(emojis.flatMap { $0 }, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
                                .frame(width: 44, height: 44)
                                .background(
                                    selectedEmoji == emoji ?
                                    Color.blue.opacity(0.2) :
                                    Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
