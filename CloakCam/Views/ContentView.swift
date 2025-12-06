import SwiftUI
import PhotosUI

// Wrapper types for fullScreenCover item binding
struct SelectedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct SelectedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedImage: SelectedImage?
    @State private var selectedVideo: SelectedVideo?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // App icon and title
                    VStack(spacing: 16) {
                        Image(systemName: "eye.slash.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("CloakCam")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Hide faces with blur, pixels, or emoji")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(32)
                    } else {
                        // Selection buttons
                        VStack(spacing: 16) {
                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images
                            ) {
                                HStack {
                                    Image(systemName: "photo.fill")
                                        .font(.title2)
                                    Text("Select Photo")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                            }

                            PhotosPicker(
                                selection: $selectedVideoItem,
                                matching: .videos
                            ) {
                                HStack {
                                    Image(systemName: "video.fill")
                                        .font(.title2)
                                    Text("Select Video")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        colors: [.green, .green.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                        .padding(.horizontal, 32)
                    }

                    Spacer()

                    // Footer
                    Text("Your privacy, protected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom)
                }
            }
            .fullScreenCover(item: $selectedImage) { selected in
                PhotoEditorView(originalImage: selected.image)
                    .onDisappear {
                        selectedPhotoItem = nil
                    }
            }
            .fullScreenCover(item: $selectedVideo) { selected in
                VideoEditorView(videoURL: selected.url)
                    .onDisappear {
                        selectedVideoItem = nil
                    }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if newValue != nil {
                    Task {
                        await loadPhoto(from: newValue)
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newValue in
                if newValue != nil {
                    Task {
                        await loadVideo(from: newValue)
                    }
                }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        print("📷 [ContentView] Loading photo from picker...")
        await MainActor.run {
            isLoading = true
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                print("📷 [ContentView] Failed to load image data")
                await MainActor.run { isLoading = false }
                return
            }

            print("📷 [ContentView] Photo loaded: \(image.size), showing editor")
            await MainActor.run {
                isLoading = false
                selectedImage = SelectedImage(image: image)
            }
        } catch {
            print("📷 [ContentView] Failed to load photo: \(error)")
            await MainActor.run { isLoading = false }
        }
    }

    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        await MainActor.run {
            isLoading = true
        }

        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                await MainActor.run { isLoading = false }
                return
            }

            print("🎬 [ContentView] Video loaded, showing editor")
            await MainActor.run {
                isLoading = false
                selectedVideo = SelectedVideo(url: movie.url)
            }
        } catch {
            print("🎬 [ContentView] Failed to load video: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

#Preview {
    ContentView()
}
