import SwiftUI

struct FaceRegionOverlay: View {
    let region: FaceRegion
    let imageSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var displayRect: CGRect {
        region.displayRect(in: imageSize)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Tappable background (invisible but captures taps)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.001)) // Nearly invisible but tappable
                .frame(width: displayRect.width, height: displayRect.height)

            // Border rectangle
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    borderColor,
                    lineWidth: isSelected ? 3 : 2
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
                .frame(width: displayRect.width, height: displayRect.height)

            // Cover type indicator
            VStack {
                HStack {
                    Spacer()
                    // Toggle button (X when enabled, checkmark when disabled)
                    Button(action: onToggle) {
                        Image(systemName: region.isEnabled ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, region.isEnabled ? .red : .green)
                            .shadow(radius: 2)
                    }
                    .offset(x: 8, y: -8)
                }
                Spacer()

                // Type indicator badge (only show when enabled)
                if region.isEnabled {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: region.coverType.iconName)
                                .font(.system(size: 12))
                            Text(region.coverType.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: displayRect.width, height: displayRect.height)
        }
        .contentShape(Rectangle()) // Makes entire area tappable
        .opacity(region.isEnabled ? 1.0 : 0.5)
        .position(x: displayRect.midX, y: displayRect.midY)
        .onTapGesture {
            onSelect()
        }
    }

    private var borderColor: Color {
        if !region.isEnabled {
            return Color.gray.opacity(0.6)
        }
        return isSelected ? Color.blue : Color.white.opacity(0.8)
    }

    private var backgroundColor: Color {
        if !region.isEnabled {
            return Color.gray.opacity(0.2)
        }
        return isSelected ? Color.blue.opacity(0.1) : Color.clear
    }
}
