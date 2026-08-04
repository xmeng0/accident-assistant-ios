//
//  AccidentStore.swift
//  AccidentAssistant
//
//  Sprint 1: The Life-Raft — Local Persistence ("Vault")
//

import Foundation
import UIKit
import SwiftUI
import Combine

// MARK: - Data Models

/// Lightweight index entry — the only thing written to the global manifest.json.
/// Fast to load; used exclusively by the Home Screen list.
struct AccidentSummary: Identifiable, Codable {
    let id: UUID
    let date: Date
    var status: String
    var photoCount: Int = 0
}

/// Heavy per-incident detail record — written to Documents/Incidents/{id}/metadata.json.
/// Only pulled from disk when the Evidence Room opens for a specific incident.
struct AccidentReport: Identifiable, Codable {
    let id: UUID
    var otherDriverProvider: String?
    var otherDriverPolicyNumber: String?
    var otherDriverName: String?
    var otherDriverLicenseNumber: String?
    var dateOfBirth: String?
    var issueDate: String?
    var expirationDate: String?
    var incidentDescription: String?
    var location: IncidentLocation?
}

/// Telemetry snapshot waiting to be claimed by a new report.
/// Created by TelemetryManager on impact detection; consumed (or discarded) by the user.
struct PendingTelemetry {
    let data: String
    let timestamp: Date
}

// MARK: - Manifest envelope

private struct AccidentManifest: Codable {
    var summaries: [AccidentSummary]
}

// MARK: - Store

@MainActor
class AccidentStore: ObservableObject {
    static let shared = AccidentStore()

    @Published var currentAccidentID: UUID?
    @Published var currentReportFolderURL: URL?
    @Published var pendingTelemetry: PendingTelemetry?

    init() {}

    // MARK: - Directory helpers

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func incidentsRootURL() -> URL {
        documentsURL().appendingPathComponent("Incidents", isDirectory: true)
    }

     func incidentFolderURL(for id: UUID) -> URL {
        incidentsRootURL().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func metadataURL(for id: UUID) -> URL {
        incidentFolderURL(for: id).appendingPathComponent("metadata.json")
    }

    private func manifestURL() -> URL {
        documentsURL().appendingPathComponent("manifest.json")
    }

    // MARK: - Manifest persistence

    private func saveManifest(_ manifest: AccidentManifest) {
        do {
            let encoded = try JSONEncoder().encode(manifest)
            try encoded.write(to: manifestURL(), options: [.atomic])
        } catch {
            print("💾 saveManifest failed: \(error.localizedDescription)")
        }
    }

    private func loadManifest() -> AccidentManifest {
        let url = manifestURL()
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AccidentManifest.self, from: data) {
            return decoded
        }
        return AccidentManifest(summaries: [])
    }

    // MARK: - Report (detail) persistence

    private func saveReport(_ report: AccidentReport) {
        let url = metadataURL(for: report.id)
        do {
            let encoded = try JSONEncoder().encode(report)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            print("💾 saveReport failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API — Index

    /// Returns the lightweight summaries used by the Home Screen.
    /// Reads only manifest.json — never touches per-incident folders.
    func getAllSummaries() -> [AccidentSummary] {
        loadManifest().summaries
    }

    // MARK: - Public API — Details

    /// Loads the full detail record for a single incident from its metadata.json.
    /// Returns nil if the file doesn't exist or can't be decoded.
    func loadDetails(for id: UUID) -> AccidentReport? {
        let url = metadataURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AccidentReport.self, from: data)
        else { return nil }
        return decoded
    }

    // MARK: - Public API — Delete

    /// Permanently deletes an incident: removes its manifest entry and its
    /// entire on-disk folder (photos, videos, metadata, AI reconstruction, telemetry).
    func deleteReport(for id: UUID) {
        var manifest = loadManifest()
        manifest.summaries.removeAll { $0.id == id }
        saveManifest(manifest)

        let folder = incidentFolderURL(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
            print("🗑️ Deleted incident: \(id.uuidString)")
        } catch {
            print("💾 deleteReport failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API — Create

    func createNewAccident(date: Date = Date()) {
        let id = UUID()
        currentAccidentID = id

        let fileManager = FileManager.default
        let folder = incidentFolderURL(for: id)
        let dashcam     = folder.appendingPathComponent("dashcam",      isDirectory: true)
        let driverUpload = folder.appendingPathComponent("driverupload", isDirectory: true)

        do {
            try fileManager.createDirectory(at: dashcam,      withIntermediateDirectories: true)
            try fileManager.createDirectory(at: driverUpload, withIntermediateDirectories: true)

            // Write an empty detail record so metadata.json always exists.
            saveReport(AccidentReport(id: id))

            // Append a lightweight summary to the global index. Starts as "draft" — the Wizard
            // hasn't been completed yet, so this accident can be resumed or safely discarded.
            var manifest = loadManifest()
            manifest.summaries.append(AccidentSummary(id: id, date: date, status: "draft"))
            saveManifest(manifest)

            currentReportFolderURL = folder

            // Auto-consume pending telemetry if it exists
            if pendingTelemetry != nil {
                consumePendingTelemetry(for: id)
            }

            print("📁 New accident case: \(id.uuidString)")
        } catch {
            print("💾 createNewAccident failed: \(error.localizedDescription)")
        }
    }

    /// Marks a draft accident as fully completed — called once the Wizard's summary step has
    /// actually been saved, so it stops showing up as a resumable "Draft" on the Home Screen.
    func finalizeAccident(for id: UUID) {
        var manifest = loadManifest()
        guard let index = manifest.summaries.firstIndex(where: { $0.id == id }) else {
            print("💾 finalizeAccident: could not find accident \(id.uuidString) in manifest.")
            return
        }
        manifest.summaries[index].status = "active"
        saveManifest(manifest)
        print("✅ Finalized accident: \(id.uuidString)")
    }

    // MARK: - Public API — Images

    /// Saves a photo to the active incident's driverupload folder. When `fileName` is provided
    /// (e.g. an AI-generated, timestamp-prefixed label), it's sanitized and used as the file's
    /// base name instead of the default `evidence_N` scheme; a numeric suffix is appended on
    /// collision so no existing file is ever silently overwritten. Returns the URL the photo was
    /// written to (nil on failure) so callers can later rename that exact file in place.
    @discardableResult
    func saveImage(_ image: UIImage, fileName: String? = nil) -> URL? {
        guard let accidentID = currentAccidentID else {
            print("💾 No active accident ID — run createNewAccident() first.")
            return nil
        }

        let fileManager = FileManager.default
        let driverUploadURL = incidentFolderURL(for: accidentID)
            .appendingPathComponent("driverupload", isDirectory: true)

        do {
            try fileManager.createDirectory(at: driverUploadURL, withIntermediateDirectories: true)

            var manifest = loadManifest()
            guard let index = manifest.summaries.firstIndex(where: { $0.id == accidentID }) else {
                print("💾 saveImage: could not find active accident in manifest.")
                return nil
            }

            let nextIndex = manifest.summaries[index].photoCount + 1
            let baseName  = sanitizedFileName(fileName, fallback: "evidence_\(nextIndex)")

            var fileURL = driverUploadURL.appendingPathComponent("\(baseName).jpg")
            var duplicateSuffix = 2
            while fileManager.fileExists(atPath: fileURL.path) {
                fileURL = driverUploadURL.appendingPathComponent("\(baseName)_\(duplicateSuffix).jpg")
                duplicateSuffix += 1
            }

            guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
                print("💾 Could not convert UIImage to JPEG bytes.")
                return nil
            }

            try jpegData.write(to: fileURL, options: [.atomic])

            manifest.summaries[index].photoCount = nextIndex
            saveManifest(manifest)

            currentReportFolderURL = incidentFolderURL(for: accidentID)
            print("📁 Saved to: \(fileURL.path) and updated manifest.")
            return fileURL
        } catch {
            print("💾 saveImage failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Strips characters that are unsafe in a file name, keeping alphanumerics, underscores,
    /// and hyphens. Falls back to `fallback` if `name` is nil, blank, or empty after cleaning.
    private func sanitizedFileName(_ name: String?, fallback: String) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { allowed.contains($0) }))
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Loads every JPEG in the driverupload folder for an incident.
    func getImages(for incidentID: UUID) -> [UIImage] {
        getImageURLs(for: incidentID).compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    /// Returns the URLs of every JPEG in the driverupload folder for an incident, sorted by filename.
    /// Unlike `getImages`, this keeps the file identity around so a specific photo can be deleted later.
    func getImageURLs(for incidentID: UUID) -> [URL] {
        let fileManager  = FileManager.default
        let driverUpload = incidentFolderURL(for: incidentID)
            .appendingPathComponent("driverupload", isDirectory: true)

        guard fileManager.fileExists(atPath: driverUpload.path) else { return [] }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: driverUpload,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return urls
                .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("💾 getImageURLs failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Renames a photo file in the driverupload folder, preserving its original extension.
    /// Returns true on success.
    @discardableResult
    func renamePhoto(at currentURL: URL, to newName: String) -> Bool {
        let ext = currentURL.pathExtension
        let sanitised = newName.hasSuffix(".\(ext)") ? newName : newName + ".\(ext)"
        let destination = currentURL.deletingLastPathComponent().appendingPathComponent(sanitised)
        do {
            try FileManager.default.moveItem(at: currentURL, to: destination)
            print("✏️ Renamed to: \(sanitised)")
            return true
        } catch {
            print("💾 renamePhoto failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Deletes the photo file at the exact URL provided and keeps the manifest's
    /// `photoCount` for `reportID` in sync with what's actually left on disk.
    func deleteImage(at url: URL, for reportID: UUID) {
        do {
            try FileManager.default.removeItem(at: url)
            print("🗑️ Photo removed: \(url.lastPathComponent)")
        } catch {
            print("💾 deleteImage failed: \(error.localizedDescription)")
            return
        }

        var manifest = loadManifest()
        guard let index = manifest.summaries.firstIndex(where: { $0.id == reportID }) else { return }
        manifest.summaries[index].photoCount = getImageURLs(for: reportID).count
        saveManifest(manifest)
    }

    // MARK: - Public API — Video

    private func dashcamFolderURL(for id: UUID) -> URL {
        incidentFolderURL(for: id).appendingPathComponent("dashcam", isDirectory: true)
    }

    /// Copies the video at `tempURL` into the incident's dashcam folder. When `fileName` is
    /// provided (e.g. a preserved library file name), it's sanitized and used as-is; otherwise
    /// falls back to the default `yyyy-MM-dd_clip_N.mp4` scheme. A numeric suffix is appended on
    /// collision so no existing file is ever silently overwritten. Returns the URL the video was
    /// written to (nil on failure).
    @discardableResult
    func saveVideo(from tempURL: URL, for reportID: UUID, fileName: String? = nil) -> URL? {
        let fileManager = FileManager.default
        let dashcam = dashcamFolderURL(for: reportID)
        do {
            try fileManager.createDirectory(at: dashcam, withIntermediateDirectories: true)

            let baseName: String
            if let fileName {
                baseName = sanitizedFileName(fileName, fallback: "clip")
            } else {
                let existingCount = (try? fileManager.contentsOfDirectory(
                    at: dashcam, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ))?.filter { $0.pathExtension.lowercased() == "mp4" }.count ?? 0
                let dateString = DateFormatter.fileSafeDate.string(from: Date())
                baseName = "\(dateString)_clip_\(existingCount + 1)"
            }

            var destination = dashcam.appendingPathComponent("\(baseName).mp4")
            var duplicateSuffix = 2
            while fileManager.fileExists(atPath: destination.path) {
                destination = dashcam.appendingPathComponent("\(baseName)_\(duplicateSuffix).mp4")
                duplicateSuffix += 1
            }

            try fileManager.copyItem(at: tempURL, to: destination)
            print("🎥 Video saved: \(destination.lastPathComponent)")
            return destination
        } catch {
            print("💾 saveVideo failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Renames a video file in the dashcam folder. Appends .mp4 if omitted.
    /// Returns true on success.
    @discardableResult
    func renameVideo(at currentURL: URL, to newName: String, for reportID: UUID) -> Bool {
        let sanitised = newName.hasSuffix(".mp4") ? newName : newName + ".mp4"
        let destination = dashcamFolderURL(for: reportID).appendingPathComponent(sanitised)
        do {
            try FileManager.default.moveItem(at: currentURL, to: destination)
            print("✏️ Renamed to: \(sanitised)")
            return true
        } catch {
            print("💾 renameVideo failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Returns all .mp4 URLs stored in the incident's dashcam folder, sorted by filename.
    func getVideoURLs(for reportID: UUID) -> [URL] {
        let dashcam = dashcamFolderURL(for: reportID)
        guard FileManager.default.fileExists(atPath: dashcam.path) else { return [] }
        do {
            return try FileManager.default
                .contentsOfDirectory(at: dashcam, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "mp4" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("💾 getVideoURLs failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Deletes the video file at the exact URL provided.
    func deleteVideo(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("🗑️ Video removed: \(url.lastPathComponent)")
        } catch {
            print("💾 deleteVideo failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API — AI Reconstruction

    private func reconstructionURL(for id: UUID) -> URL {
        incidentFolderURL(for: id).appendingPathComponent("reconstruction.txt")
    }

    func saveAIReconstruction(_ text: String, for id: UUID) {
        do {
            try text.write(to: reconstructionURL(for: id), atomically: true, encoding: .utf8)
            print("🤖 AI reconstruction saved for \(id.uuidString).")
        } catch {
            print("💾 saveAIReconstruction failed: \(error.localizedDescription)")
        }
    }

    func loadAIReconstruction(for id: UUID) -> String? {
        let url = reconstructionURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    func loadTelemetry(for id: UUID) -> String? {
        let url = telemetryURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Public API — Pending Telemetry

    private func telemetryURL(for id: UUID) -> URL {
        incidentFolderURL(for: id).appendingPathComponent("telemetry.json")
    }

    /// Writes the pending telemetry payload to the incident folder and clears the pending slot.
    /// Returns `true` when data was successfully written.
    @discardableResult
    func consumePendingTelemetry(for reportID: UUID) -> Bool {
        guard let pending = pendingTelemetry else {
            pendingTelemetry = nil
            return false
        }
        do {
            try pending.data.write(to: telemetryURL(for: reportID), atomically: true, encoding: .utf8)
            print("📡 Telemetry consumed and saved for \(reportID.uuidString).")
        } catch {
            print("💾 consumePendingTelemetry: write failed — \(error.localizedDescription)")
        }
        pendingTelemetry = nil
        return true
    }

    /// Discards the pending telemetry without attaching it to any report.
    func discardPendingTelemetry() {
        print("📡 Pending telemetry discarded by user.")
        pendingTelemetry = nil
    }

    func saveIncidentDescription(_ description: String, for id: UUID) {
        var report = loadDetails(for: id) ?? AccidentReport(id: id)
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        report.incidentDescription = trimmed.isEmpty ? nil : trimmed
        saveReport(report)
    }

    // MARK: - Public API — Insurance

    /// Updates the insurance details for any already-saved incident (e.g. edits made in the Evidence Room).
    /// Trims whitespace and nil-coalesces empty strings before writing.
    func updateIncidentDetails(
        for id: UUID,
        provider: String,
        policyNumber: String,
        driverName: String,
        licenseNumber: String,
        dateOfBirth: String = "",
        issueDate: String = "",
        expirationDate: String = "",
        incidentDescription: String = "",
        location: IncidentLocation? = nil
    ) {
        var report = loadDetails(for: id) ?? AccidentReport(id: id)
        report.otherDriverProvider      = provider.trimmed.nilIfEmpty
        report.otherDriverPolicyNumber  = policyNumber.trimmed.nilIfEmpty
        report.otherDriverName          = driverName.trimmed.nilIfEmpty
        report.otherDriverLicenseNumber = licenseNumber.trimmed.nilIfEmpty
        report.dateOfBirth              = dateOfBirth.trimmed.nilIfEmpty
        report.issueDate                = issueDate.trimmed.nilIfEmpty
        report.expirationDate           = expirationDate.trimmed.nilIfEmpty
        report.incidentDescription      = incidentDescription.trimmed.nilIfEmpty
        report.location                 = location
        saveReport(report)
        print("💾 Incident details updated for \(id.uuidString).")
    }

    /// Reads the existing metadata.json for the active accident, merges in the
    /// insurance fields, and writes it back. The manifest is intentionally NOT
    /// touched — insurance data lives only in the per-incident detail file.
    func saveInsuranceData(
        provider: String?,
        policyNumber: String?,
        driverName: String?,
        licenseNumber: String?
    ) {
        guard let accidentID = currentAccidentID else {
            print("💾 saveInsuranceData: no active accident ID.")
            return
        }
        var report = loadDetails(for: accidentID) ?? AccidentReport(id: accidentID)
        report.otherDriverProvider      = provider?.trimmed.nilIfEmpty
        report.otherDriverPolicyNumber  = policyNumber?.trimmed.nilIfEmpty
        report.otherDriverName          = driverName?.trimmed.nilIfEmpty
        report.otherDriverLicenseNumber = licenseNumber?.trimmed.nilIfEmpty
        saveReport(report)
        print("💾 Insurance data saved for \(accidentID.uuidString).")
    }
}

// MARK: - String helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - DateFormatter helpers

private extension DateFormatter {
    static let fileSafeDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
