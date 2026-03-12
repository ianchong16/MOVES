import SwiftUI
import PhotosUI

// MARK: - Memory Prompt View
// Slides up after the user marks a move as complete.
// Lets them attach a photo and a short note — or skip entirely.
// This is the "peak-end" capture moment: the ending of an experience,
// when emotional memory is strongest. Completely optional — never required.
// Aesthetic: same brutalist-minimal language as the rest of the app.

struct MemoryPromptView: View {
    let moveTitle: String
    let onSave: (String?, UIImage?) -> Void
    let onSkip: () -> Void

    @State private var note: String = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var showingCamera = false
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Spacer()
                Button(action: onSkip) {
                    Text("SKIP")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray400)
                        .padding(.vertical, MOVESSpacing.md)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.sm)

            // Hairline
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Move title — quiet confirmation of what they just did
                    Text(moveTitle.uppercased())
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.top, MOVESSpacing.xl)

                    // Prompt headline
                    Text("How did it go?")
                        .font(MOVESTypography.serifLarge())
                        .foregroundStyle(Color.movesPrimaryText)
                        .padding(.top, MOVESSpacing.sm)

                    // Photo section
                    photoSection
                        .padding(.top, MOVESSpacing.xl)

                    // Note field
                    noteField
                        .padding(.top, MOVESSpacing.lg)

                    // Action buttons
                    actionButtons
                        .padding(.top, MOVESSpacing.xl)
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
        }
        .background(Color.movesPrimaryBg)
        .sheet(isPresented: $showingCamera) {
            CameraPickerView(image: $selectedImage)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
    }

    // MARK: - Photo Section
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("ADD PHOTO")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            if let image = selectedImage {
                // Preview + tap to replace
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()

                    // Remove button
                    Button {
                        selectedImage = nil
                        selectedPhoto = nil
                    } label: {
                        Text("✕")
                            .font(MOVESTypography.mono())
                            .foregroundStyle(Color.movesPrimaryBg)
                            .padding(MOVESSpacing.sm)
                            .background(Color.movesPrimaryText.opacity(0.6))
                    }
                    .padding(MOVESSpacing.sm)
                }
            } else {
                // Photo picker buttons
                HStack(spacing: MOVESSpacing.sm) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        photoPickerButton(label: "LIBRARY", icon: "photo.on.rectangle")
                    }

                    Button {
                        showingCamera = true
                    } label: {
                        photoPickerButton(label: "CAMERA", icon: "camera")
                    }
                }
            }
        }
    }

    private func photoPickerButton(label: String, icon: String) -> some View {
        HStack(spacing: MOVESSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(MOVESTypography.monoSmall())
                .kerning(1)
        }
        .foregroundStyle(Color.movesPrimaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .overlay(
            Rectangle()
                .stroke(Color.movesGray100, lineWidth: 0.5)
        )
    }

    // MARK: - Note Field
    private var noteField: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("ADD NOTE")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            TextField("What stuck with you?", text: $note, axis: .vertical)
                .font(MOVESTypography.serif())
                .foregroundStyle(Color.movesPrimaryText)
                .lineLimit(3...6)
                .focused($noteIsFocused)
                .padding(MOVESSpacing.md)
                .overlay(
                    Rectangle()
                        .stroke(noteIsFocused ? Color.movesPrimaryText : Color.movesGray100, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: MOVESSpacing.sm) {
            MOVESPrimaryButton(title: "Save Memory") {
                HapticManager.success()
                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(trimmedNote.isEmpty ? nil : trimmedNote, selectedImage)
            }

            Button(action: onSkip) {
                Text("Skip")
                    .font(MOVESTypography.mono())
                    .kerning(1)
                    .foregroundStyle(Color.movesGray400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MOVESSpacing.md)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Camera Picker (UIKit wrapper)
// UIImagePickerController wrapped for SwiftUI.

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
