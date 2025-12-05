import SwiftUI
import Photos

struct PhotoResultView: View {
    let processedPhoto: ProcessedPhoto
    let onDismiss: () -> Void

    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            if processedPhoto.facesDetected == 0 {
                Text("No faces detected")
                    .foregroundStyle(.secondary)
                    .padding(.top)
            } else {
                Text("\(processedPhoto.facesDetected) face\(processedPhoto.facesDetected == 1 ? "" : "s") blurred")
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }

            Image(uiImage: processedPhoto.blurred)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

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
                    onDismiss()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [processedPhoto.blurred])
        }
        .alert("Saved!", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The blurred photo has been saved to your photo library.")
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
                    saveErrorMessage = "Photo library access is required to save images."
                    showSaveError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: processedPhoto.blurred)
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
