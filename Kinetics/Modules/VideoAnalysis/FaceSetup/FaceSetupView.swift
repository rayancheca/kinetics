import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - FaceSetupView

/// Full-screen sheet that guides the user through face-enrolment onboarding.
///
/// Phases:
/// - `.idle`       → Title, brief instructions, and a "Begin Scan" button.
/// - `.scanning`   → Animated ring prompt; immediately opens the camera or photo picker.
/// - `.processing` → Spinner while Vision generates the feature print.
/// - `.success`    → Green check, face thumbnail, and a "Done" button.
/// - `.failed`     → Warning, error message, and recovery actions.
///
/// The view owns a `UIImagePickerController` sheet (camera) and a `PhotosPicker` sheet
/// (library fallback). Both converge through `vm.processCapturedPhoto` / `vm.processPickedPhoto`.
struct FaceSetupView: View {

    // MARK: - Input

    let userId: String

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var vm = FaceSetupViewModel()
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cameraImage: UIImage?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar
                Spacer(minLength: 0)
                phaseContent
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.8),
                        value: phaseID
                    )
                Spacer(minLength: 0)
                bottomActions
                    .padding(.bottom, 40)
            }
        }
        // Camera sheet (UIImagePickerController).
        .sheet(isPresented: $showCamera) {
            FaceCameraSheet(capturedImage: $cameraImage)
                .ignoresSafeArea()
        }
        // Photo library picker.
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        // Handle camera result.
        .onChange(of: cameraImage) { _, newImage in
            guard let image = newImage else { return }
            Task {
                await vm.processCapturedPhoto(image, userId: userId, modelContext: modelContext)
            }
        }
        // Handle library result.
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await vm.processPickedPhoto(image, userId: userId, modelContext: modelContext)
                }
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.kineticsSubtext)
                    .frame(width: 36, height: 36)
                    .background(Color.kineticsMidGray)
                    .clipShape(Circle())
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch vm.phase {
        case .idle:
            idleView
        case .scanning:
            scanningView
        case .processing:
            processingView
        case .success(let image):
            successView(image: image)
        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: Idle

    private var idleView: some View {
        VStack(spacing: 32) {
            // Face circle placeholder.
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200, height: 200)

                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 64, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.kineticsPurple, Color.kineticsBlue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("SCAN")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }

            VStack(spacing: 12) {
                Text("Set Up Face ID")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(
                    "Kinetics will learn your face so it can\n"
                        + "automatically label you in workout videos."
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            }

            primaryButton(title: "Begin Scan", icon: "camera.fill") {
                beginScan()
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: Scanning

    private var scanningView: some View {
        VStack(spacing: 32) {
            ZStack {
                // Outer animated ring.
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.kineticsPurple.opacity(0.4),
                                Color.kineticsBlue.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 220, height: 220)

                // Inner face outline.
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 180, height: 180)

                Image(systemName: "person.crop.circle.badge.viewfinder")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.kineticsPurple, Color.kineticsBlue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("Position Your Face")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Centre your face in the circle.\nLook straight ahead in good lighting.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.kineticsMidGray)
                    .frame(width: 120, height: 120)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.kineticsBlue)
                    .scaleEffect(1.4)
            }

            VStack(spacing: 8) {
                Text("Analyzing…")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Generating your face signature")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
    }

    // MARK: Success

    private func successView(image: UIImage) -> some View {
        VStack(spacing: 32) {
            ZStack(alignment: .bottomTrailing) {
                // Face thumbnail.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.kineticsGreen, lineWidth: 3)
                    )

                // Green check badge.
                ZStack {
                    Circle()
                        .fill(Color.kineticsGreen)
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .offset(x: 4, y: 4)
            }

            VStack(spacing: 10) {
                Text("Perfect!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your face is saved.\nKinetics will recognize you automatically.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            primaryButton(title: "Done", icon: "checkmark") {
                dismiss()
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 28) {
            // Warning icon.
            ZStack {
                Circle()
                    .fill(Color.kineticsOrange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.kineticsOrange)
            }

            VStack(spacing: 12) {
                Text("Couldn't Scan Face")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Bottom Actions

    @ViewBuilder
    private var bottomActions: some View {
        switch vm.phase {
        case .idle, .scanning, .processing, .success:
            EmptyView()

        case .failed:
            VStack(spacing: 16) {
                if vm.triesRemaining > 0 {
                    primaryButton(title: "Try Again", icon: "arrow.clockwise") {
                        vm.retry()
                        beginScan()
                    }
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Upload a Photo", systemImage: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.kineticsBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)

                Button {
                    vm.useManualIdentification()
                    dismiss()
                } label: {
                    Text("Skip — use tap to identify")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.kineticsSubtext)
                        .underline()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    /// Opens the camera if available; falls back to the photo library.
    private func beginScan() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            showPhotoPicker = true
        }
    }

    /// A reusable full-width gradient primary button.
    private func primaryButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.kineticsPurple, Color.kineticsBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 32)
    }

    /// Stable string key derived from the current phase, used to drive phase-change animations.
    private var phaseID: String {
        switch vm.phase {
        case .idle:           return "idle"
        case .scanning:       return "scanning"
        case .processing:     return "processing"
        case .success:        return "success"
        case .failed(let m):  return "failed-\(m.prefix(20))"
        }
    }
}

// MARK: - FaceCameraSheet

/// A `UIViewControllerRepresentable` wrapper around `UIImagePickerController` that
/// presents the front camera for face capture.
///
/// Falls back silently if the camera is unavailable (the caller should guard with
/// `UIImagePickerController.isSourceTypeAvailable(.camera)` before presenting).
struct FaceCameraSheet: UIViewControllerRepresentable {

    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    // MARK: Coordinator

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        let parent: FaceCameraSheet

        init(_ parent: FaceCameraSheet) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let edited = info[.editedImage] as? UIImage {
                parent.capturedImage = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.capturedImage = original
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        // Prefer front camera for face capture; fall back to rear if unavailable.
        picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front)
            ? .front
            : .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No dynamic updates required.
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    FaceSetupView(userId: "preview-user")
        .modelContainer(for: FaceProfile.self, inMemory: true)
}
#endif
