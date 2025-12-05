import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                Text("CloakCam")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Blur faces in photos and videos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if case .processing(let progress) = viewModel.processingState {
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)

                        Text("Processing... \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            Label("Select Photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .frame(width: 200)

                        PhotosPicker(
                            selection: $selectedVideoItem,
                            matching: .videos
                        ) {
                            Label("Select Video", systemImage: "video")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .frame(width: 200)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: $viewModel.showPhotoResult) {
                if let photo = viewModel.processedPhoto {
                    PhotoResultView(processedPhoto: photo) {
                        viewModel.reset()
                    }
                }
            }
            .navigationDestination(isPresented: $viewModel.showVideoResult) {
                if let video = viewModel.processedVideo {
                    VideoResultView(processedVideo: video) {
                        viewModel.reset()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if newValue != nil {
                    Task {
                        await viewModel.processSelectedPhoto(newValue)
                        selectedPhotoItem = nil
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newValue in
                if let item = newValue {
                    Task {
                        await loadAndProcessVideo(item: item)
                        selectedVideoItem = nil
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.reset()
                }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func loadAndProcessVideo(item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                return
            }
            await viewModel.processSelectedVideo(url: movie.url)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
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
