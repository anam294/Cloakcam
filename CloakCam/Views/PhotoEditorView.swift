import SwiftUI
import Photos

struct PhotoEditorView: View {
    let originalImage: UIImage
    @State private var faceRegions: [FaceRegion] = []
    @State private var selectedRegionId: UUID?
    @State private var isDetecting = true
    @State private var isProcessing = false
    @State private var processedImage: UIImage?
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @Environment(\.dismiss) private var dismiss

    private let photoProcessor = PhotoProcessor()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Image with face overlays
                    GeometryReader { geometry in
                        let containerSize = geometry.size
                        let currentImage = processedImage ?? originalImage
                        let fitSize = calculateFitSize(imageSize: currentImage.size, containerSize: containerSize)
                        let offsetX = (containerSize.width - fitSize.width) / 2
                        let offsetY = (containerSize.height - fitSize.height) / 2

                        ZStack {
                            Image(uiImage: currentImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: fitSize.width, height: fitSize.height)
                                .position(x: containerSize.width / 2, y: containerSize.height / 2)

                            // Face region overlays (only show when not processed)
                            if processedImage == nil && !isDetecting {
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

                            // Loading overlay
                            if isDetecting {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    Text("Detecting faces...")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5))
                            }

                            // Processing overlay
                            if isProcessing {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    Text("Applying effects...")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5))
                            }
                        }
                        .frame(width: containerSize.width, height: containerSize.height)
                    }

                    // Bottom controls
                    VStack(spacing: 16) {
                        // Face count and info
                        if !isDetecting && processedImage == nil {
                            let enabledCount = faceRegions.filter { $0.isEnabled }.count
                            if faceRegions.isEmpty {
                                Text("No faces detected")
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
                           processedImage == nil {
                            CoverTypePicker(selectedType: $faceRegions[index].coverType)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Action buttons
                        if processedImage == nil {
                            Button {
                                Task {
                                    await applyEffects()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Apply Effects")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(faceRegions.filter { $0.isEnabled }.isEmpty ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(faceRegions.filter { $0.isEnabled }.isEmpty)
                            .padding(.horizontal)
                        } else {
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
                                    processedImage = nil
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
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = processedImage {
                    ShareSheet(items: [image])
                }
            }
            .alert("Saved!", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The photo has been saved to your photo library.")
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .task {
                await detectFaces()
            }
        }
    }

    private func calculateFitSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider - fit to width
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller - fit to height
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func detectFaces() async {
        print("📸 [PhotoEditor] Starting face detection on image: \(originalImage.size)")
        do {
            let regions = try await photoProcessor.detectFaces(in: originalImage)
            print("📸 [PhotoEditor] Detected \(regions.count) faces")
            for (i, region) in regions.enumerated() {
                print("📸 [PhotoEditor] Face \(i): \(region.normalizedRect)")
            }
            await MainActor.run {
                faceRegions = regions
                isDetecting = false
                // Auto-select first face
                if let first = regions.first {
                    selectedRegionId = first.id
                }
            }
        } catch {
            print("📸 [PhotoEditor] Error detecting faces: \(error)")
            await MainActor.run {
                isDetecting = false
            }
        }
    }

    private func applyEffects() async {
        isProcessing = true
        do {
            let result = try await photoProcessor.applyEffects(to: originalImage, regions: faceRegions)
            await MainActor.run {
                processedImage = result
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func saveToPhotos() {
        guard let image = processedImage else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveErrorMessage = "Photo library access is required to save images."
                    showSaveError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        showSaveSuccess = true
                    } else {
                        saveErrorMessage = error?.localizedDescription ?? "Failed to save photo."
                        showSaveError = true
                    }
                }
            }
        }
    }
}
