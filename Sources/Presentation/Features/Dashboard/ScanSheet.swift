import SwiftUI
import VisionKit

// MARK: - Scan Sheet

struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedImages: [UIImage] = []
    @State private var showingScanner = false
    @State private var showUnsupportedAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.lg) {
                if scannedImages.isEmpty {
                    emptyState
                } else {
                    resultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Scan Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerViewRepresentable { images in
                    scannedImages.append(contentsOf: images)
                }
            }
            .alert("Scanner Unavailable", isPresented: $showUnsupportedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Document scanning is not available on this device.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.lg) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.accentAgent)

            VStack(spacing: Theme.sm) {
                Text("Scan a Document")
                    .font(.title2.bold())
                    .foregroundStyle(AppColors.textPrimary)

                Text("Use your camera to scan documents, whiteboards, or handwritten notes.")
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.xl)
            }

            Button {
                if VNDocumentCameraViewController.isSupported {
                    showingScanner = true
                } else {
                    showUnsupportedAlert = true
                }
            } label: {
                Label("Open Camera", systemImage: "camera.fill")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.md)
                    .background(AppColors.accentAgent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .padding(.horizontal, Theme.xl)

            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: Theme.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(scannedImages.indices, id: \.self) { index in
                        Image(uiImage: scannedImages[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    scannedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .padding(4)
                            }
                    }
                }
                .padding(.horizontal, Theme.md)
            }

            HStack(spacing: Theme.md) {
                Button {
                    if VNDocumentCameraViewController.isSupported {
                        showingScanner = true
                    } else {
                        showUnsupportedAlert = true
                    }
                } label: {
                    Label("Scan Another", systemImage: "camera.fill")
                        .font(.body.bold())
                        .foregroundStyle(AppColors.accentAgent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.sm)
                        .background(AppColors.accentAgent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.bottom, Theme.lg)
        }
    }
}

// MARK: - Document Scanner Representable

struct DocumentScannerViewRepresentable: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void

        init(onScan: @escaping ([UIImage]) -> Void) {
            self.onScan = onScan
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onScan(images)
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("[ScanSheet] Scanner failed: \(error.localizedDescription)")
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    ScanSheet()
        .preferredColorScheme(.dark)
}
