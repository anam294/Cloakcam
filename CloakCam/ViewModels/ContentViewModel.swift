import SwiftUI
import PhotosUI

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var processingState: ProcessingState = .idle
    @Published var showPhotoPicker = false
    @Published var showVideoPicker = false
    @Published var processedPhoto: ProcessedPhoto?
    @Published var processedVideo: ProcessedVideo?
    @Published var showPhotoResult = false
    @Published var showVideoResult = false
    @Published var errorMessage: String?
    @Published var showError = false

    private let photoProcessor = PhotoProcessor()
    private let videoProcessor = VideoProcessor()

    func processSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        processingState = .processing(progress: 0)

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw ProcessingError.invalidImage
            }

            processingState = .processing(progress: 0.5)

            let result = try await photoProcessor.processImage(image)
            processedPhoto = result
            processingState = .completed
            showPhotoResult = true
        } catch {
            handleError(error)
        }
    }

    func processSelectedVideo(url: URL) async {
        processingState = .processing(progress: 0)

        do {
            let result = try await videoProcessor.processVideo(at: url) { [weak self] progress in
                Task { @MainActor in
                    self?.processingState = .processing(progress: progress)
                }
            }

            processedVideo = result
            processingState = .completed
            showVideoResult = true
        } catch {
            handleError(error)
        }
    }

    func reset() {
        processingState = .idle
        processedPhoto = nil
        processedVideo = nil
        showPhotoResult = false
        showVideoResult = false
    }

    private func handleError(_ error: Error) {
        processingState = .error(message: error.localizedDescription)
        errorMessage = error.localizedDescription
        showError = true
    }
}
