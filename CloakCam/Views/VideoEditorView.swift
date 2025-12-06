import SwiftUI
import AVKit
import Photos

struct VideoEditorView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?
    @State private var faceRegions: [FaceRegion] = []
    @State private var selectedRegionId: UUID?
    @State private var isDetecting = true
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0
    @State private var processedVideoURL: URL?
    @State private var player: AVPlayer?
    @State private var showEmojiPicker = false
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @Environment(\.dismiss) private var dismiss

    private let videoProcessor = VideoProcessor()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Video/Thumbnail with face overlays
                    GeometryReader { geometry in
                        let containerSize = geometry.size

                        ZStack {
                            if let processed = processedVideoURL, let player = player {
                                // Show processed video
                                VideoPlayer(player: player)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let thumb = thumbnail {
                                let fitSize = calculateFitSize(imageSize: thumb.size, containerSize: containerSize)
                                let offsetX = (containerSize.width - fitSize.width) / 2
                                let offsetY = (containerSize.height - fitSize.height) / 2

                                // Show thumbnail with overlays
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: fitSize.width, height: fitSize.height)
                                    .position(x: containerSize.width / 2, y: containerSize.height / 2)

                                // Video indicator
                                if !isDetecting && !isProcessing {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding()
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }

                                // Face region overlays
                                if !isDetecting && !isProcessing {
                                    ForEach(faceRegions) { region in
                                        FaceRegionOverlay(
                                            region: region,
                                            imageSize: fitSize,
                                            isSelected: selectedRegionId == region.id,
                                            onSelect: {
                                                withAnimation(.spring(response: 0.3)) {
                                                    selectedRegionId = region.id
                                                }
                                            },
                                            onToggle: {
                                                withAnimation(.spring(response: 0.3)) {
                                                    if let index = faceRegions.firstIndex(where: { $0.id == region.id }) {
                                                        faceRegions[index].isEnabled.toggle()
                                                    }
                                                }
                                            }
                                        )
                                        .offset(x: offsetX, y: offsetY)
                                    }
                                }
                            }

                            // Loading overlay
                            if isDetecting {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    Text("Analyzing video...")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5))
                            }

                            // Processing overlay
                            if isProcessing {
                                VStack(spacing: 16) {
                                    ProgressView(value: processingProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 200)
                                        .tint(.white)

                                    Text("Processing video... \(Int(processingProgress * 100))%")
                                        .foregroundColor(.white)
                                        .font(.headline)

                                    Text("This may take a moment")
                                        .foregroundColor(.white.opacity(0.7))
                                        .font(.caption)
                                }
                                .padding(32)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.8)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5))
                            }
                        }
                        .frame(width: containerSize.width, height: containerSize.height)
                    }

                    // Bottom controls
                    VStack(spacing: 16) {
                        // Face count and info
                        if !isDetecting && processedVideoURL == nil && !isProcessing {
                            let enabledCount = faceRegions.filter { $0.isEnabled }.count
                            if faceRegions.isEmpty {
                                Text("No faces detected in video")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(enabledCount) of \(faceRegions.count) face\(faceRegions.count == 1 ? "" : "s") will be hidden")
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Cover type picker (show when a region is selected and enabled)
                        if let selectedId = selectedRegionId,
                           let index = faceRegions.firstIndex(where: { $0.id == selectedId }),
                           faceRegions[index].isEnabled,
                           processedVideoURL == nil && !isProcessing {
                            CoverTypePicker(
                                selectedType: $faceRegions[index].coverType,
                                selectedEmoji: $faceRegions[index].emoji,
                                onEmojiPickerTap: {
                                    showEmojiPicker = true
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Action buttons
                        if processedVideoURL == nil && !isProcessing {
                            Button {
                                Task {
                                    await processVideo()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Process Video")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(faceRegions.filter { $0.isEnabled }.isEmpty ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(faceRegions.filter { $0.isEnabled }.isEmpty || isDetecting)
                            .padding(.horizontal)
                        } else if processedVideoURL != nil {
                            // Save and Share buttons
                            HStack(spacing: 16) {
                                Button {
                                    saveToPhotos()
                                } label: {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                Button {
                                    showShareSheet = true
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)

                            Button {
                                withAnimation {
                                    player?.pause()
                                    player = nil
                                    processedVideoURL = nil
                                }
                            } label: {
                                Text("Edit Again")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.vertical)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEmojiPicker) {
                if let selectedId = selectedRegionId,
                   let index = faceRegions.firstIndex(where: { $0.id == selectedId }) {
                    EmojiPicker(selectedEmoji: $faceRegions[index].emoji)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = processedVideoURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Saved!", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The video has been saved to your photo library.")
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .task {
                await analyzeVideo()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    private func calculateFitSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func analyzeVideo() async {
        print("🎬 [VideoEditor] Analyzing video at: \(videoURL)")
        do {
            let result = try await videoProcessor.detectFacesInFirstFrame(url: videoURL)
            print("🎬 [VideoEditor] Detected \(result.faces.count) faces in first frame")
            for (i, face) in result.faces.enumerated() {
                print("🎬 [VideoEditor] Face \(i): \(face.normalizedRect)")
            }
            await MainActor.run {
                thumbnail = result.thumbnail
                faceRegions = result.faces
                isDetecting = false
                if let first = result.faces.first {
                    selectedRegionId = first.id
                }
            }
        } catch {
            print("🎬 [VideoEditor] Error analyzing video: \(error)")
            await MainActor.run {
                isDetecting = false
            }
        }
    }

    private func processVideo() async {
        isProcessing = true
        processingProgress = 0

        do {
            let result = try await videoProcessor.processVideo(
                at: videoURL,
                regions: faceRegions
            ) { progress in
                Task { @MainActor in
                    processingProgress = progress
                }
            }

            await MainActor.run {
                processedVideoURL = result.processedURL
                player = AVPlayer(url: result.processedURL)
                player?.play()

                // Loop video
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player?.currentItem,
                    queue: .main
                ) { _ in
                    player?.seek(to: .zero)
                    player?.play()
                }

                isProcessing = false
            }
        } catch {
            print("🎬 [VideoEditor] Error processing video: \(error)")
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func saveToPhotos() {
        guard let url = processedVideoURL else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveErrorMessage = "Photo library access is required to save videos."
                    showSaveError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        showSaveSuccess = true
                    } else {
                        saveErrorMessage = error?.localizedDescription ?? "Failed to save video."
                        showSaveError = true
                    }
                }
            }
        }
    }
}
