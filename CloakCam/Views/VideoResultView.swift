import SwiftUI
import AVKit
import Photos

struct VideoResultView: View {
    let processedVideo: ProcessedVideo
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            if processedVideo.facesDetected == 0 {
                Text("No faces detected")
                    .foregroundStyle(.secondary)
                    .padding(.top)
            } else {
                Text("\(processedVideo.facesDetected) face\(processedVideo.facesDetected == 1 ? "" : "s") blurred")
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }

            if let player = player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            HStack(spacing: 20) {
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
            .padding(.bottom)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    player?.pause()
                    onDismiss()
                }
            }
        }
        .onAppear {
            player = AVPlayer(url: processedVideo.processedURL)
            player?.play()

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [processedVideo.processedURL])
        }
        .alert("Saved!", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The blurred video has been saved to your photo library.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveErrorMessage = "Photo library access is required to save videos."
                    showSaveError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: processedVideo.processedURL)
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
