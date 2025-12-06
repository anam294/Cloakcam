import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

final class PhotoProcessor {
    private let context: CIContext

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        } else {
            context = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    // MARK: - Face Detection Only
    func detectFaces(in image: UIImage) async throws -> [FaceRegion] {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.invalidImage
        }

        let normalizedRects = try await detectFaceRects(in: cgImage)

        return normalizedRects.map { rect in
            FaceRegion(normalizedRect: rect)
        }
    }

    // MARK: - Apply Effects with Custom Regions
    func applyEffects(to image: UIImage, regions: [FaceRegion]) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.invalidImage
        }

        let enabledRegions = regions.filter { $0.isEnabled }
        if enabledRegions.isEmpty {
            return image
        }

        var ciImage = CIImage(cgImage: cgImage)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        for region in enabledRegions {
            let config = FaceRegionConfig(
                normalizedRect: region.normalizedRect,
                coverType: region.coverType,
                emoji: region.emoji
            )
            ciImage = applyEffect(to: ciImage, config: config, imageSize: imageSize)
        }

        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.renderingFailed
        }

        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Legacy method for backward compatibility
    func processImage(_ image: UIImage) async throws -> ProcessedPhoto {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.invalidImage
        }

        let ciImage = CIImage(cgImage: cgImage)
        let faceRects = try await detectFaceRects(in: cgImage)

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

    // MARK: - Private Methods

    private func detectFaceRects(in cgImage: CGImage) async throws -> [CGRect] {
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

    private func applyEffect(to image: CIImage, config: FaceRegionConfig, imageSize: CGSize) -> CIImage {
        // Convert normalized rect to image coordinates (Vision uses bottom-left origin)
        let faceRect = CGRect(
            x: config.normalizedRect.origin.x * imageSize.width,
            y: config.normalizedRect.origin.y * imageSize.height,
            width: config.normalizedRect.width * imageSize.width,
            height: config.normalizedRect.height * imageSize.height
        )

        // Expand rect for better coverage
        let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.4, dy: -faceRect.height * 0.5)

        switch config.coverType {
        case .blur:
            return applyBlurEffect(to: image, rect: expandedRect)
        case .pixelate:
            return applyPixelateEffect(to: image, rect: expandedRect)
        case .emoji:
            return applyEmojiEffect(to: image, rect: expandedRect, emoji: config.emoji)
        }
    }

    private func applyBlurEffect(to image: CIImage, rect: CGRect) -> CIImage {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = image
        blurFilter.radius = 30

        guard let blurredImage = blurFilter.outputImage else {
            return image
        }

        let maskGenerator = CIFilter.radialGradient()
        maskGenerator.center = CGPoint(x: rect.midX, y: rect.midY)
        maskGenerator.radius0 = Float(min(rect.width, rect.height) * 0.4)
        maskGenerator.radius1 = Float(max(rect.width, rect.height) * 0.6)
        maskGenerator.color0 = CIColor.white
        maskGenerator.color1 = CIColor.clear

        guard let maskImage = maskGenerator.outputImage else {
            return image
        }

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = blurredImage
        blendFilter.backgroundImage = image
        blendFilter.maskImage = maskImage

        return blendFilter.outputImage ?? image
    }

    private func applyPixelateEffect(to image: CIImage, rect: CGRect) -> CIImage {
        let pixelateFilter = CIFilter.pixellate()
        pixelateFilter.inputImage = image
        pixelateFilter.scale = Float(max(rect.width, rect.height) / 8)
        pixelateFilter.center = CGPoint(x: rect.midX, y: rect.midY)

        guard let pixelatedImage = pixelateFilter.outputImage else {
            return image
        }

        let maskGenerator = CIFilter.radialGradient()
        maskGenerator.center = CGPoint(x: rect.midX, y: rect.midY)
        maskGenerator.radius0 = Float(min(rect.width, rect.height) * 0.4)
        maskGenerator.radius1 = Float(max(rect.width, rect.height) * 0.6)
        maskGenerator.color0 = CIColor.white
        maskGenerator.color1 = CIColor.clear

        guard let maskImage = maskGenerator.outputImage else {
            return image
        }

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = pixelatedImage
        blendFilter.backgroundImage = image
        blendFilter.maskImage = maskImage

        return blendFilter.outputImage ?? image
    }

    private func applyEmojiEffect(to image: CIImage, rect: CGRect, emoji: String) -> CIImage {
        // Create emoji image
        let emojiSize = max(rect.width, rect.height) * 1.2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: emojiSize, height: emojiSize))

        let emojiUIImage = renderer.image { ctx in
            let fontSize = emojiSize * 0.85
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize)
            ]
            let emojiString = NSAttributedString(string: emoji, attributes: attributes)
            let emojiRect = CGRect(
                x: (emojiSize - emojiString.size().width) / 2,
                y: (emojiSize - emojiString.size().height) / 2,
                width: emojiString.size().width,
                height: emojiString.size().height
            )
            emojiString.draw(in: emojiRect)
        }

        guard let emojiCGImage = emojiUIImage.cgImage else {
            return image
        }

        var emojiCIImage = CIImage(cgImage: emojiCGImage)

        // Position emoji over face
        let translateX = rect.midX - emojiSize / 2
        let translateY = rect.midY - emojiSize / 2
        emojiCIImage = emojiCIImage.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))

        // Composite emoji over original image
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = emojiCIImage
        compositeFilter.backgroundImage = image

        return compositeFilter.outputImage ?? image
    }

    // Legacy blur method for backward compatibility
    private func applyBlurToFaces(image: CIImage, faceRects: [CGRect], imageSize: CGSize) -> CIImage {
        var result = image

        for normalizedRect in faceRects {
            let faceRect = CGRect(
                x: normalizedRect.origin.x * imageSize.width,
                y: normalizedRect.origin.y * imageSize.height,
                width: normalizedRect.width * imageSize.width,
                height: normalizedRect.height * imageSize.height
            )

            let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.4, dy: -faceRect.height * 0.5)
            result = applyBlurEffect(to: result, rect: expandedRect)
        }

        return result
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
