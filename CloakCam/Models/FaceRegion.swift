import Foundation
import CoreGraphics

enum CoverType: String, CaseIterable, Identifiable {
    case blur = "Blur"
    case pixelate = "Pixelate"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        }
    }
}

struct FaceRegion: Identifiable, Equatable {
    let id: UUID
    var normalizedRect: CGRect  // Vision coordinates (0-1, bottom-left origin)
    var coverType: CoverType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        normalizedRect: CGRect,
        coverType: CoverType = .blur,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.normalizedRect = normalizedRect
        self.coverType = coverType
        self.isEnabled = isEnabled
    }

    // Get display rect for SwiftUI (top-left origin, flipped Y)
    func displayRect(in size: CGSize) -> CGRect {
        let x = normalizedRect.origin.x * size.width
        let y = (1 - normalizedRect.origin.y - normalizedRect.height) * size.height
        let width = normalizedRect.width * size.width
        let height = normalizedRect.height * size.height

        // Expand rect for better coverage
        let expandedWidth = width * 1.8
        let expandedHeight = height * 2.0

        return CGRect(
            x: x - (expandedWidth - width) / 2,
            y: y - (expandedHeight - height) / 2,
            width: expandedWidth,
            height: expandedHeight
        )
    }
}

// For passing to processors
struct FaceRegionConfig {
    let normalizedRect: CGRect
    let coverType: CoverType
}
