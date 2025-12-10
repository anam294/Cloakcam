import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class VideoProcessor {
    private let context: CIContext
    private let processingQueue = DispatchQueue(label: "com.cloakcam.videoprocessing", qos: .userInitiated)

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        } else {
            context = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    // MARK: - Face Detection for First Frame (for thumbnail preview)
    func detectFacesInFirstFrame(url: URL) async throws -> (thumbnail: UIImage, hasFaces: Bool) {
        let asset = AVAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)

        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        let thumbnail = UIImage(cgImage: cgImage)

        // Detect faces just to show if there are any
        var hasFaces = false
        let request = VNDetectFaceRectanglesRequest { req, _ in
            if let results = req.results as? [VNFaceObservation], !results.isEmpty {
                hasFaces = true
            }
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (thumbnail: thumbnail, hasFaces: hasFaces)
    }

    // MARK: - Process Video with Continuous Face Detection
    func processVideo(
        at url: URL,
        coverType: CoverType,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> ProcessedVideo {
        print("🎬 [VideoProcessor] Starting video processing with \(coverType.rawValue)")

        let asset = AVAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        print("📊 [VideoProcessor] Video: \(naturalSize), \(nominalFrameRate) fps, \(CMTimeGetSeconds(duration))s")

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // Video reader
        let videoReader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        videoReader.add(videoOutput)

        // Audio reader (separate)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?

        if let audioTrack = audioTracks.first {
            let ar = try AVAssetReader(asset: asset)
            let ao = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            ao.alwaysCopiesSampleData = false
            ar.add(ao)
            audioReader = ar
            audioOutput = ao
        }

        // Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let pixelCount = naturalSize.width * naturalSize.height
        let bitrate = max(8_000_000, Int(pixelCount * 10))

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: naturalSize.width,
                AVVideoHeightKey: naturalSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: nominalFrameRate
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = preferredTransform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(naturalSize.width),
                kCVPixelBufferHeightKey as String: Int(naturalSize.height)
            ]
        )
        writer.add(videoInput)

        // Audio input
        var audioInput: AVAssetWriterInput?
        if let audioTrack = audioTracks.first {
            let formatDescs = try await audioTrack.load(.formatDescriptions)
            if let fmt = formatDescs.first {
                let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)
                ai.expectsMediaDataInRealTime = false
                writer.add(ai)
                audioInput = ai
            }
        }

        // Start
        videoReader.startReading()
        audioReader?.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(1, Int(CMTimeGetSeconds(duration) * Double(nominalFrameRate)))
        // Detect faces every 5 frames for good tracking
        let detectionInterval = 5

        print("🎞️ [VideoProcessor] Processing \(totalFrames) frames")

        // Store the cover type for use in the closure
        let selectedCoverType = coverType

        let result: ProcessedVideo = try await withCheckedThrowingContinuation { continuation in
            var processedFrames = 0
            var lastDetectedFaces: [CGRect] = []
            var videoFinished = false
            var audioFinished = audioInput == nil
            var hasResumed = false
            var totalFacesDetected = 0

            let finishProcessing = {
                guard !hasResumed else { return }
                hasResumed = true

                DispatchQueue.main.async {
                    progressHandler(0.95)
                }

                writer.finishWriting {
                    if writer.status == .completed {
                        print("🎉 [VideoProcessor] Complete!")
                        DispatchQueue.main.async {
                            progressHandler(1.0)
                        }
                        continuation.resume(returning: ProcessedVideo(
                            originalURL: url,
                            processedURL: outputURL,
                            facesDetected: totalFacesDetected
                        ))
                    } else {
                        print("❌ [VideoProcessor] Failed: \(writer.error?.localizedDescription ?? "unknown")")
                        continuation.resume(throwing: writer.error ?? ProcessingError.videoWriteFailed)
                    }
                }
            }

            videoInput.requestMediaDataWhenReady(on: self.processingQueue) { [weak self] in
                guard let self = self else { return }

                while videoInput.isReadyForMoreMediaData && !videoFinished {
                    autoreleasepool {
                        if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                                // Detect faces periodically throughout the video
                                if processedFrames % detectionInterval == 0 {
                                    let detected = self.detectFacesSync(in: pixelBuffer)
                                    if !detected.isEmpty {
                                        lastDetectedFaces = detected
                                        totalFacesDetected = max(totalFacesDetected, detected.count)
                                    }
                                }

                                // Apply effect to all detected faces
                                let processed = self.applyEffectToFaces(
                                    pixelBuffer: pixelBuffer,
                                    faces: lastDetectedFaces,
                                    coverType: selectedCoverType
                                )
                                adaptor.append(processed, withPresentationTime: time)

                                processedFrames += 1

                                let progress = Double(processedFrames) / Double(totalFrames) * 0.9
                                if processedFrames % 30 == 0 {
                                    DispatchQueue.main.async {
                                        progressHandler(min(progress, 0.9))
                                    }
                                }
                            }
                        } else {
                            videoFinished = true
                            videoInput.markAsFinished()
                            print("✅ [VideoProcessor] Video done: \(processedFrames) frames")

                            if audioFinished {
                                finishProcessing()
                            }
                        }
                    }
                }
            }

            // Process audio
            if let ai = audioInput, let ao = audioOutput {
                ai.requestMediaDataWhenReady(on: self.processingQueue) {
                    while ai.isReadyForMoreMediaData && !audioFinished {
                        if let buffer = ao.copyNextSampleBuffer() {
                            ai.append(buffer)
                        } else {
                            audioFinished = true
                            ai.markAsFinished()
                            print("✅ [VideoProcessor] Audio done")

                            if videoFinished {
                                finishProcessing()
                            }
                            break
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: - Private Methods

    private func detectFacesSync(in pixelBuffer: CVPixelBuffer) -> [CGRect] {
        var faces: [CGRect] = []
        let request = VNDetectFaceRectanglesRequest { req, _ in
            if let results = req.results as? [VNFaceObservation] {
                faces = results.map { $0.boundingBox }
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
        return faces
    }

    private func applyEffectToFaces(pixelBuffer: CVPixelBuffer, faces: [CGRect], coverType: CoverType) -> CVPixelBuffer {
        guard !faces.isEmpty else { return pixelBuffer }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var img = CIImage(cvPixelBuffer: pixelBuffer)

        for face in faces {
            let faceRect = CGRect(
                x: face.origin.x * CGFloat(w),
                y: face.origin.y * CGFloat(h),
                width: face.width * CGFloat(w),
                height: face.height * CGFloat(h)
            )

            // Expanded rect for better coverage
            let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.4, dy: -faceRect.height * 0.5)

            switch coverType {
            case .blur:
                img = applyBlurEffect(to: img, rect: expandedRect)
            case .pixelate:
                img = applyPixelateEffect(to: img, rect: expandedRect)
            }
        }

        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &out)
        if let o = out {
            context.render(img, to: o)
            return o
        }
        return pixelBuffer
    }

    private func applyBlurEffect(to image: CIImage, rect: CGRect) -> CIImage {
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = 30
        guard let blurred = blur.outputImage else { return image }

        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: rect.midX, y: rect.midY)
        mask.radius0 = Float(min(rect.width, rect.height) * 0.35)
        mask.radius1 = Float(max(rect.width, rect.height) * 0.65)
        mask.color0 = CIColor.white
        mask.color1 = CIColor.clear
        guard let maskImg = mask.outputImage else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = image
        blend.maskImage = maskImg
        return blend.outputImage ?? image
    }

    private func applyPixelateEffect(to image: CIImage, rect: CGRect) -> CIImage {
        let pixelate = CIFilter.pixellate()
        pixelate.inputImage = image
        pixelate.scale = Float(max(rect.width, rect.height) / 8)
        pixelate.center = CGPoint(x: rect.midX, y: rect.midY)
        guard let pixelated = pixelate.outputImage else { return image }

        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: rect.midX, y: rect.midY)
        mask.radius0 = Float(min(rect.width, rect.height) * 0.35)
        mask.radius1 = Float(max(rect.width, rect.height) * 0.65)
        mask.color0 = CIColor.white
        mask.color1 = CIColor.clear
        guard let maskImg = mask.outputImage else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = pixelated
        blend.backgroundImage = image
        blend.maskImage = maskImg
        return blend.outputImage ?? image
    }
}
