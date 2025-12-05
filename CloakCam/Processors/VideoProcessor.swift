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

    struct TrackedFace {
        var id: UUID
        var rect: CGRect
        var lastSeen: Int
    }

    func processVideo(
        at url: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> ProcessedVideo {
        print("🎬 [VideoProcessor] Starting video processing")

        let asset = AVAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        print("📊 [VideoProcessor] Video: \(naturalSize), \(nominalFrameRate) fps, \(CMTimeGetSeconds(duration))s")

        let transformedSize = naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

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

        // Calculate appropriate bitrate based on resolution (higher res = higher bitrate)
        let pixelCount = naturalSize.width * naturalSize.height
        let bitrate = max(8_000_000, Int(pixelCount * 10)) // At least 8Mbps, scales with resolution

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
        let detectionInterval = max(1, Int(nominalFrameRate / 6))

        print("🎞️ [VideoProcessor] Processing \(totalFrames) frames")

        // Process video using requestMediaDataWhenReady (proper async pattern)
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessedVideo, Error>) in
            var processedFrames = 0
            var trackedFaces: [TrackedFace] = []
            var totalFacesDetected = 0
            var videoFinished = false
            var audioFinished = audioInput == nil

            videoInput.requestMediaDataWhenReady(on: processingQueue) { [weak self] in
                guard let self = self else { return }

                while videoInput.isReadyForMoreMediaData && !videoFinished {
                    if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            // Face detection
                            if processedFrames % detectionInterval == 0 {
                                let detected = self.detectFacesSync(in: pixelBuffer)
                                trackedFaces = self.updateTrackedFaces(existing: trackedFaces, detected: detected, frameNumber: processedFrames)
                                totalFacesDetected = max(totalFacesDetected, trackedFaces.count)
                            }

                            // Apply blur
                            let processed = self.applyBlurToFaces(pixelBuffer: pixelBuffer, faces: trackedFaces.map { $0.rect })
                            adaptor.append(processed, withPresentationTime: time)

                            processedFrames += 1
                            if processedFrames % 50 == 0 {
                                print("📈 [VideoProcessor] \(processedFrames)/\(totalFrames)")
                            }

                            let progress = Double(processedFrames) / Double(totalFrames) * 0.8
                            DispatchQueue.main.async {
                                progressHandler(min(progress, 0.8))
                            }
                        }
                    } else {
                        videoFinished = true
                        videoInput.markAsFinished()
                        print("✅ [VideoProcessor] Video done: \(processedFrames) frames")

                        // Check if we're completely done
                        if audioFinished {
                            self.finishWriting(writer: writer, outputURL: outputURL, totalFacesDetected: totalFacesDetected, url: url, progressHandler: progressHandler, continuation: continuation)
                        }
                        break
                    }
                }
            }

            // Process audio
            if let ai = audioInput, let ao = audioOutput {
                ai.requestMediaDataWhenReady(on: processingQueue) { [weak self] in
                    guard let self = self else { return }

                    while ai.isReadyForMoreMediaData && !audioFinished {
                        if let buffer = ao.copyNextSampleBuffer() {
                            ai.append(buffer)
                        } else {
                            audioFinished = true
                            ai.markAsFinished()
                            print("✅ [VideoProcessor] Audio done")

                            // Check if we're completely done
                            if videoFinished {
                                self.finishWriting(writer: writer, outputURL: outputURL, totalFacesDetected: totalFacesDetected, url: url, progressHandler: progressHandler, continuation: continuation)
                            }
                            break
                        }
                    }
                }
            }
        }

        return result
    }

    private func finishWriting(
        writer: AVAssetWriter,
        outputURL: URL,
        totalFacesDetected: Int,
        url: URL,
        progressHandler: @escaping (Double) -> Void,
        continuation: CheckedContinuation<ProcessedVideo, Error>
    ) {
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

    private func updateTrackedFaces(existing: [TrackedFace], detected: [CGRect], frameNumber: Int) -> [TrackedFace] {
        var updated = existing
        var matched = Set<Int>()

        for i in 0..<updated.count {
            var best: (idx: Int, iou: CGFloat)?
            for (j, rect) in detected.enumerated() where !matched.contains(j) {
                let iou = calculateIoU(updated[i].rect, rect)
                if iou > 0.3 && (best == nil || iou > best!.iou) {
                    best = (j, iou)
                }
            }
            if let b = best {
                let old = updated[i].rect
                let new = detected[b.idx]
                updated[i].rect = CGRect(
                    x: old.origin.x * 0.3 + new.origin.x * 0.7,
                    y: old.origin.y * 0.3 + new.origin.y * 0.7,
                    width: old.width * 0.3 + new.width * 0.7,
                    height: old.height * 0.3 + new.height * 0.7
                )
                updated[i].lastSeen = frameNumber
                matched.insert(b.idx)
            }
        }

        for (j, rect) in detected.enumerated() where !matched.contains(j) {
            updated.append(TrackedFace(id: UUID(), rect: rect, lastSeen: frameNumber))
        }

        return updated.filter { frameNumber - $0.lastSeen < 30 }
    }

    private func calculateIoU(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
        let intersection = r1.intersection(r2)
        guard !intersection.isNull else { return 0 }
        let iArea = intersection.width * intersection.height
        let uArea = r1.width * r1.height + r2.width * r2.height - iArea
        return uArea > 0 ? iArea / uArea : 0
    }

    private func applyBlurToFaces(pixelBuffer: CVPixelBuffer, faces: [CGRect]) -> CVPixelBuffer {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var img = CIImage(cvPixelBuffer: pixelBuffer)

        for norm in faces {
            let rect = CGRect(
                x: norm.origin.x * CGFloat(w),
                y: norm.origin.y * CGFloat(h),
                width: norm.width * CGFloat(w),
                height: norm.height * CGFloat(h)
            ).insetBy(dx: -norm.width * CGFloat(w) * 0.4, dy: -norm.height * CGFloat(h) * 0.5)
            img = blurRegion(in: img, rect: rect)
        }

        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &out)
        if let o = out {
            context.render(img, to: o)
            return o
        }
        return pixelBuffer
    }

    private func blurRegion(in image: CIImage, rect: CGRect) -> CIImage {
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
}
