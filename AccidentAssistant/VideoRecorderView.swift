//
//  VideoRecorderView.swift
//  AccidentAssistant
//
//  Sprint 3: The Black Box — camera-based video capture.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps `UIImagePickerController` configured for live camera video capture.
/// Calls `onVideoRecorded` with the temporary file URL when recording completes,
/// or `onCancel` when the user dismisses without recording.
struct VideoRecorderView: UIViewControllerRepresentable {

    var onVideoRecorded: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoRecorded: onVideoRecorded, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType   = .camera
        picker.mediaTypes   = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate     = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

        private let onVideoRecorded: (URL) -> Void
        private let onCancel: () -> Void

        init(onVideoRecorded: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onVideoRecorded = onVideoRecorded
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let videoURL = info[.mediaURL] as? URL {
                onVideoRecorded(videoURL)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }
    }
}
