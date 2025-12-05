import Foundation
import UIKit

enum ProcessingState: Equatable {
    case idle
    case processing(progress: Double)
    case completed
    case error(message: String)

    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.processing(let p1), .processing(let p2)):
            return p1 == p2
        case (.completed, .completed):
            return true
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

enum MediaType {
    case photo
    case video
}

struct ProcessedPhoto {
    let original: UIImage
    let blurred: UIImage
    let facesDetected: Int
}

struct ProcessedVideo {
    let originalURL: URL
    let processedURL: URL
    let facesDetected: Int
}
