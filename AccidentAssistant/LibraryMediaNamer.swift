//
//  LibraryMediaNamer.swift
//  AccidentAssistant
//
//  Naming logic for photos/videos picked from the user's photo library — deliberately kept
//  separate from `PhotoAutoNamer`, which only applies to live camera captures. Library uploads
//  never touch GeminiService: we simply try to preserve the asset's own original file name, and
//  fall back to a "Library_" + creation-timestamp name when it's missing or looks like an
//  opaque, iOS-generated identifier. Reading creation dates straight from EXIF/video container
//  metadata (rather than via PHAsset) means this never needs Photos-library permission.
//

import CoreTransferable
import ImageIO
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// A `Transferable` wrapper that, like `VideoFile`, copies the picked item to a temp file via
/// `FileRepresentation` — which is what lets us see the asset's own original file name instead
/// of just raw `Data`.
struct ImageFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { image in
            SentTransferredFile(image.url)
        } importing: { received in
            let fileName = received.file.lastPathComponent
            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return ImageFile(url: copyURL)
        }
    }
}

nonisolated enum LibraryMediaNamer {
    /// Matches the PHPicker-style UUID iOS tacks onto the end of a transferred file's name —
    /// with or without a leading separator — e.g. the trailing chunk of
    /// "TestclipforAAapp-02DBEA56-50A4-408D-8C72-9B660AB7FD99" or a name that's nothing
    /// but a bare UUID like "51EF6EC4-3684-4F0D-9DE3-2FD2D3193B2E".
    private static let trailingUUIDRegex = try! NSRegularExpression(
        pattern: "[-_]?[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$"
    )

    /// Matches short, auto-incremented default camera names with no real information content
    /// (e.g. "IMG_1234", "DSC_0007", "MOV_42") — these still fall back to the timestamp name
    /// even once a UUID suffix has been stripped off, since the remainder is just a serial number.
    private static let genericCameraNameRegex = try! NSRegularExpression(
        pattern: "^(IMG|DSC|DCIM|MOV|VID)[_-]?[0-9]{1,6}$",
        options: [.caseInsensitive]
    )

    /// Removes a trailing PHPicker UUID suffix (if present) from a file's base name.
    private static func strippingTrailingUUID(from name: String) -> String {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = trailingUUIDRegex.firstMatch(in: name, range: range),
              let matchRange = Range(match.range, in: name) else {
            return name
        }
        return String(name[name.startIndex..<matchRange.lowerBound])
    }

    private static func isGenericCameraName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return genericCameraNameRegex.firstMatch(in: name, range: range) != nil
    }

    /// The final display name (no extension) for a photo/video picked from the library. Strips
    /// any PHPicker UUID suffix off the asset's original name first; if what's left is empty or
    /// a generic default camera name (e.g. "IMG_1234"), falls back to "Library_" plus a short
    /// timestamp built from the asset's creation date (defaulting to now if that's unavailable).
    static func displayName(originalNameNoExtension: String?, creationDate: Date?) -> String {
        print("🏷️ [LibraryMediaNamer] Raw name from PhotosPicker: \(originalNameNoExtension ?? "nil")")

        let trimmedSeparators = CharacterSet(charactersIn: "-_ ")
        var keptName: String? = nil

        if let rawName = originalNameNoExtension?.trimmingCharacters(in: .whitespaces), !rawName.isEmpty {
            let cleaned = strippingTrailingUUID(from: rawName).trimmingCharacters(in: trimmedSeparators)
            print("🏷️ [LibraryMediaNamer] Cleaned name after UUID stripping: \"\(cleaned)\"")

            if cleaned.isEmpty {
                print("🏷️ [LibraryMediaNamer] Cleaned name is empty — not meaningful, falling back to timestamp name.")
            } else if isGenericCameraName(cleaned) {
                print("🏷️ [LibraryMediaNamer] \"\(cleaned)\" matched the generic camera name pattern — falling back to timestamp name.")
            } else {
                print("🏷️ [LibraryMediaNamer] \"\(cleaned)\" looks meaningful — keeping it as the display name.")
                keptName = cleaned
            }
        } else {
            print("🏷️ [LibraryMediaNamer] No usable raw name provided — falling back to timestamp name.")
        }

        let finalName: String
        if let keptName {
            finalName = keptName
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmm"
            finalName = "Library_\(formatter.string(from: creationDate ?? Date()))"
        }

        print("🏷️ [LibraryMediaNamer] Final display name: \"\(finalName)\"")
        return finalName
    }

    /// Reads the EXIF/TIFF "date taken" straight out of the image file's own metadata —
    /// no Photos-library permission required since this never touches the Photos framework.
    static func creationDate(fromImageAt url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let dateString =
            exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime as String] as? String

        guard let dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }

    /// Reads the creation date embedded in a video file's own container metadata —
    /// again, no Photos-library permission required. Uses the modern async `load()` APIs
    /// instead of the deprecated synchronous AVFoundation properties.
    static func creationDate(fromVideoAt url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let metadataItems = try? await asset.load(.commonMetadata) else { return nil }

        for item in metadataItems where item.commonKey == .commonKeyCreationDate {
            if let date = try? await item.load(.dateValue) {
                return date
            }
            if let stringValue = try? await item.load(.stringValue) {
                return ISO8601DateFormatter().date(from: stringValue)
            }
        }
        return nil
    }
}
