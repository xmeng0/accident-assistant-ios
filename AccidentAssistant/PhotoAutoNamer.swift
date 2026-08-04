//
//  PhotoAutoNamer.swift
//  AccidentAssistant
//
//  AI-assisted, non-blocking auto-naming for evidence photos: a photo is saved to disk
//  immediately under a short timestamp-based fallback name (e.g. "1105AM_Photo"), then a
//  detached background task asks Gemini for a brief description of the subject and silently
//  renames the file once (and if) a usable answer comes back.
//

import UIKit

enum PhotoAutoNamer {
    static let namingPrompt = """
        Provide a very brief, 2 to 3 word description of the subject of this car accident photo (e.g., 'Rear Bumper', 'License Plate', 'Intersection'). Output ONLY the description, with spaces replaced by underscores.
        """

    /// Formats a moment in time as a short local time string, e.g. "1105AM".
    static func timeStamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hhmma"
        return formatter.string(from: date)
    }

    /// Name used immediately at capture/save time, before the AI description is available.
    static func fallbackName(timeStamp: String) -> String {
        "\(timeStamp)_Photo"
    }

    /// Immediately saves `image` to `AccidentStore` under a fallback timestamp name (requires
    /// `AccidentStore.shared.currentAccidentID` to already be set), then fires a detached
    /// background task that asks Gemini for a short descriptive label and silently renames the
    /// file once it arrives. Never blocks on the network call — if it fails or times out, the
    /// fallback name is simply left in place.
    ///
    /// - Parameters:
    ///   - onSaved: called synchronously (on the main actor) right after the immediate save.
    ///   - onRenamed: called on the main actor after a successful background rename, so callers
    ///     can refresh whatever UI list is displaying the file's name.
    @MainActor
    static func saveAndAutoName(
        _ image: UIImage,
        onSaved: (URL) -> Void = { _ in },
        onRenamed: @escaping () -> Void = {}
    ) {
        let stamp = timeStamp()
        guard let savedURL = AccidentStore.shared.saveImage(image, fileName: fallbackName(timeStamp: stamp)) else { return }
        onSaved(savedURL)

        Task.detached(priority: .utility) {
            guard let descriptiveName = await generateDescriptiveName(for: image, timeStamp: stamp) else { return }
            await MainActor.run {
                AccidentStore.shared.renamePhoto(at: savedURL, to: descriptiveName)
                onRenamed()
            }
        }
    }

    /// Calls Gemini for a short descriptive label and combines it with the same `timeStamp`
    /// used for the fallback name so the two names share a time prefix. Returns nil (never
    /// throws) if the label can't be generated — callers should just keep the fallback name.
    static func generateDescriptiveName(for image: UIImage, timeStamp: String, model: GeminiModel = .efficient) async -> String? {
        do {
            let rawLabel = try await GeminiService.shared.generateLabel(for: image, prompt: namingPrompt, model: model)
            let label = sanitize(rawLabel)
            guard !label.isEmpty else { return nil }
            return "\(timeStamp)_\(label)"
        } catch {
            print("🏷️ Photo auto-naming failed, keeping fallback name: \(error.localizedDescription)")
            return nil
        }
    }

    /// Keeps only characters safe for a file name, collapsing whitespace into underscores.
    private static func sanitize(_ raw: String) -> String {
        let spaced = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let filtered = spaced.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
}
