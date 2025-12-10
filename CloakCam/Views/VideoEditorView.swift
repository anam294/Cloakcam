import SwiftUI
import AVKit
import Photos

struct VideoEditorView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?
    @State private var hasFaces: Bool = false
    @State private var isLoading = true
    @State private var selectedCoverType: CoverType = .blur
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0
    @State private var processedVideoURL: URL?
    @State private var player: AVPlayer?
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
                    // Video/Thumbnail
                    GeometryReader { geometry in
                        let containerSize = geometry.size

                        ZStack {
                            if let processedURL = processedVideoURL, let player = player {
                                // Show processed video
                                VideoPlayer(player: player)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let thumb = thumbnail {
                                // Show thumbnail
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                // Video indicator
                                if !isLoading && !isProcessing {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding()
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                            }

                            // Loading overlay
                            if isLoading {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    Text("Loading video...")
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

                                    Text("Detecting and hiding faces throughout")
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
                        if !isLoading && processedVideoURL == nil && !isProcessing {
                            // Info text
                            if hasFaces {
                                Text("All faces in the video will be hidden")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No faces detected in first frame")
                                    .foregroundColor(.secondary)
                                Text("Faces will still be detected throughout the video")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }

                            // Cover type picker
                            CoverTypePicker(selectedType: $selectedCoverType)

                            // Process button
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
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
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
                await loadVideo()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    private func loadVideo() async {
        print("🎬 [VideoEditor] Loading video: \(videoURL)")

        do {
            let (thumb, faces) = try await videoProcessor.detectFacesInFirstFrame(url: videoURL)
            await MainActor.run {
                thumbnail = thumb
                hasFaces = faces
                isLoading = false
            }
            print("🎬 [VideoEditor] Video loaded, faces in first frame: \(faces)")
        } catch {
            print("🎬 [VideoEditor] Error loading video: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func processVideo() async {
        isProcessing = true
        processingProgress = 0

        do {
            let result = try await videoProcessor.processVideo(
                at: videoURL,
                coverType: selectedCoverType
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
