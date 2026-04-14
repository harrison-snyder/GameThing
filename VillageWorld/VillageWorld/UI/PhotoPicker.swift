//
//  PhotoPicker.swift
//  VillageWorld
//
//  SwiftUI wrapper for selecting a photo from the library or camera.
//  Used by Researcher and Farmer to classify real-world items via Vision.
//

import SwiftUI
import PhotosUI

struct PhotoPicker: View {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Pick a Photo", systemImage: "photo.on.rectangle")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    isPresented = false
                }
            }
        }
    }
}

/// Standalone camera capture using UIImagePickerController.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWith info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
