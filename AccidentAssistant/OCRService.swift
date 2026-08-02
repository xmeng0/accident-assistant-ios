//
//  OCRService.swift
//  AccidentAssistant
//
//  Sprint 2: Vision OCR — local text extraction and barcode scanning.
//

import Vision
import UIKit

final class OCRService {
    static let shared = OCRService()
    private init() {}

    /// Extracts all recognizable text from a UIImage using Apple's on-device Vision framework.
    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Run safely without continuations to prevent Double-Resume crashes
        try handler.perform([request])

        let lines = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            ?? []

        return lines.joined(separator: "\n")
    }

    /// Scans a UIImage for a PDF417 barcode, optimized for UIImagePickerController captures.
    func detectBarcode(in image: UIImage) async throws -> String? {
        
        #if targetEnvironment(simulator)
        print("🖥️ SIMULATOR DETECTED: Bypassing Vision and returning mock PDF417 payload.")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        return """
        @
        ANSI 636026080102DL00410288ZA03290015DLDAQD12345678
        DCSMENG
        DACXIANG
        """
        #else
        
        // 1. Normalize the image. This permanently bakes the physical rotation into the pixels,
        // stripping away EXIF data so the Vision framework starts with a perfectly flat canvas.
        let flatImage = normalizeImage(image)
        
        guard let cgImage = flatImage.cgImage else {
            throw OCRError.invalidImage
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.pdf417]
        
        // 2. Upgrade to the ML-based engine. Revision 3 (iOS 16+) is significantly more resilient
        // when reading dense PDF417 barcodes out of massive 12MP+ camera frames.
        if #available(iOS 16.0, *) {
            request.revision = VNDetectBarcodesRequestRevision3
        }

        // 3. Fallback Sweep: Try normal orientation first. If the user held the phone in portrait
        // but the ID was landscape, the first pass might fail. The second pass (.right) rotates
        // the search grid 90 degrees to guarantee a hit.
        let orientations: [CGImagePropertyOrientation] = [.up, .right]
        
        for orientation in orientations {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])

                // Iterate through all detected barcodes to find the true AAMVA license payload
                // (ignoring tiny auxiliary tracking codes that might be shorter than 30 characters)
                if let results = request.results {
                    for barcode in results {
                        if let payload = barcode.payloadStringValue,
                           payload.count > 30,
                           payload.hasPrefix("@") || payload.contains("ANSI") || payload.contains("DLQ") || payload.contains("DL") {
                            print("✅ VALID AAMVA PDF417 FOUND! Payload length: \(payload.count)")
                            return payload
                        }
                    }
                }
            } catch {
                print("❌ Vision Error on orientation \(orientation.rawValue): \(error.localizedDescription)")
            }
        }

        print("⚠️ Vision finished but found no valid AAMVA driver's license barcode.")
        return nil
        #endif
    }
    
    /// Redraws the image to strip EXIF orientation and ensure it is physically right-side up.
    private func normalizeImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be read. Please try again."
        }
    }
}
