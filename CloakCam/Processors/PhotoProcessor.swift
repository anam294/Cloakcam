import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

final class PhotoProcessor {
    private let context = CIContext()

    func processImage(_ image: UIImage) async throws -> ProcessedPhoto {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.invalidImage
        }

        let ciImage = CIImage(cgImage: cgImage)
        let faceRects = try await detectFaces(in: cgImage)

        if faceRects.isEmpty {
            return ProcessedPhoto(original: image, blurred: image, facesDetected: 0)
        }

        let blurredCIImage = applyBlurToFaces(
            image: ciImage,
            faceRects: faceRects,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        guard let outputCGImage = context.createCGImage(blurredCIImage, from: blurredCIImage.extent) else {
            throw ProcessingError.renderingFailed
        }

        let blurredImage = UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)

        return ProcessedPhoto(original: image, blurred: blurredImage, facesDetected: faceRects.count)
    }

    private func detectFaces(in cgImage: CGImage) async throws -> [CGRect] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let rects = observations.map { $0.boundingBox }
                continuation.resume(returning: rects)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func applyBlurToFaces(image: CIImage, faceRects: [CGRect], imageSize: CGSize) -> CIImage {
        var result = image

        for normalizedRect in faceRects {
            // Convert normalized Vision coordinates to image coordinates
            // Vision uses bottom-left origin, which matches CIImage
            let faceRect = CGRect(
                x: normalizedRect.origin.x * imageSize.width,
                y: normalizedRect.origin.y * imageSize.height,
                width: normalizedRect.width * imageSize.width,
                height: normalizedRect.height * imageSize.height
            )

            // Expand the rect significantly to ensure full face coverage including forehead and chin
            let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.4, dy: -faceRect.height * 0.5)

            result = blurRegion(in: result, rect: expandedRect)
        }

        return result
    }

    private func blurRegion(in image: CIImage, rect: CGRect) -> CIImage {
        // Create blurred version of the entire image
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = image
        blurFilter.radius = 30

        guard let blurredImage = blurFilter.outputImage else {
            return image
        }

        // Create an ellipse mask for the face region (more natural than rectangle)
        let maskGenerator = CIFilter.radialGradient()
        maskGenerator.center = CGPoint(x: rect.midX, y: rect.midY)
        maskGenerator.radius0 = Float(min(rect.width, rect.height) * 0.4)
        maskGenerator.radius1 = Float(max(rect.width, rect.height) * 0.6)
        maskGenerator.color0 = CIColor.white
        maskGenerator.color1 = CIColor.clear

        guard let maskImage = maskGenerator.outputImage else {
            return image
        }

        // Blend blurred and original using the mask
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = blurredImage
        blendFilter.backgroundImage = image
        blendFilter.maskImage = maskImage

        return blendFilter.outputImage ?? image
    }
}

enum ProcessingError: LocalizedError {
    case invalidImage
    case renderingFailed
    case videoLoadFailed
    case videoWriteFailed
    case noVideoTrack
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Unable to process the image."
        case .renderingFailed:
            return "Failed to render the processed image."
        case .videoLoadFailed:
            return "Failed to load the video."
        case .videoWriteFailed:
            return "Failed to write the processed video."
        case .noVideoTrack:
            return "No video track found in the file."
        case .cancelled:
            return "Processing was cancelled."
        }
    }
}
