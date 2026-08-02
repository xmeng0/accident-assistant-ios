//
//  IncidentEvidenceTabView.swift
//  AccidentAssistant
//
//  Evidence Gallery — destination screen.
//

import SwiftUI
import UIKit
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct IncidentEvidenceTabView: View {
    let reportID: UUID
    let photoCount: Int

    @State private var loadedImages: [UIImage] = []
    @State private var details: AccidentReport? = nil

    // Edit mode
    @State private var isEditing = false
    @State private var editProvider = ""
    @State private var editPolicyNumber = ""
    @State private var editDriverName = ""
    @State private var editLicenseNumber = ""

    // Video evidence
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var loadedVideoURLs: [URL] = []
    @State private var isShowingCamera = false
    @State private var videoToRename: URL?
    @State private var newVideoName: String = ""
    @State private var showDashcamPicker = false

    // Document scanning
    @State private var showDLSourceDialog = false
    @State private var useCameraForDL = true
    @State private var showDLScanner = false
    @State private var dlScanImage: UIImage? = nil
    @State private var showInsuranceSourceDialog = false
    @State private var useCameraForInsurance = true
    @State private var showInsuranceScanner = false
    @State private var showDLScanErrorAlert = false

    // Well-lit capture reminder — shown before either scan flow begins.
    @State private var showCaptureReminder = false
    @State private var pendingCaptureAction: (() -> Void)? = nil

    @AppStorage("selectedAIModel") private var selectedAIModel: GeminiModel = .efficient

    private let safetyRed = Color(red: 0.86, green: 0.10, blue: 0.15)

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                otherDriverSection
                    .padding(.top, 20)

                Text("Evidence Photos")
                    .font(.title3.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                if loadedImages.isEmpty {
                    Text("No photos available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(loadedImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(height: 110)
                                .clipped()
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                        Label("Add More Photos", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Divider()
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)

                videoEvidenceSection
                    .padding(.top, 8)
            }
            .padding(.bottom, 20)
        }
        .alert("Rename Video", isPresented: Binding(
            get: { videoToRename != nil },
            set: { if !$0 { videoToRename = nil } }
        )) {
            TextField("New name", text: $newVideoName)
            Button("Save") {
                if let url = videoToRename {
                    AccidentStore.shared.renameVideo(at: url, to: newVideoName, for: reportID)
                    DispatchQueue.main.async {
                        loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                    }
                    videoToRename = nil
                }
            }
            Button("Cancel", role: .cancel) { videoToRename = nil }
        }
        .onAppear {
            loadedImages = AccidentStore.shared.getImages(for: reportID)
            details = AccidentStore.shared.loadDetails(for: reportID)
            loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
        }
        .sheet(isPresented: $isShowingCamera) {
            VideoRecorderView {
                tempURL in
                AccidentStore.shared.saveVideo(from: tempURL, for: reportID)
                loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                isShowingCamera = false
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedVideoItem) {
            guard let item = selectedVideoItem else { return }
            item.loadTransferable(type: VideoFile.self) { result in
                switch result {
                case .success(let video):
                    guard let video else { return }
                    DispatchQueue.main.async {
                        AccidentStore.shared.saveVideo(from: video.url, for: reportID)
                        self.loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                    }
                case .failure(let error):
                    print("Video load failed: \(error.localizedDescription)")
                }
            }
        }
        .onChange(of: selectedPhotoItems) {
                    Task {
                        // Temporarily tell the database which report we are editing
                        AccidentStore.shared.currentAccidentID = reportID
                        
                        for item in selectedPhotoItems {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                AccidentStore.shared.saveImage(uiImage)
                            }
                        }
                        // Refresh the UI and clear the picker
                        loadedImages = AccidentStore.shared.getImages(for: reportID)
                        selectedPhotoItems = []
                    }
                }
        .confirmationDialog("Choose Photo Source", isPresented: $showInsuranceSourceDialog, titleVisibility: .visible) {
            Button("Camera") { useCameraForInsurance = true; showInsuranceScanner = true }
            Button("Photo Library") { useCameraForInsurance = false; showInsuranceScanner = true }
        }
        .confirmationDialog("Choose Photo Source", isPresented: $showDLSourceDialog, titleVisibility: .visible) {
            Button("Camera") { useCameraForDL = true; showDLScanner = true }
            Button("Photo Library") { useCameraForDL = false; showDLScanner = true }
        }
        .fullScreenCover(isPresented: $showDLScanner) {
            ImagePicker(image: $dlScanImage, useCamera: useCameraForDL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showInsuranceScanner) {
            OCRScannerView { parsed in
                AccidentStore.shared.updateIncidentDetails(
                    for: reportID,
                    provider:       parsed.provider     ?? details?.otherDriverProvider      ?? "",
                    policyNumber:   parsed.policyNumber ?? details?.otherDriverPolicyNumber  ?? "",
                    driverName:     parsed.driverName   ?? details?.otherDriverName          ?? "",
                    licenseNumber:  details?.otherDriverLicenseNumber ?? "",
                    dateOfBirth:    details?.dateOfBirth    ?? "",
                    issueDate:      details?.issueDate      ?? "",
                    expirationDate: details?.expirationDate ?? ""
                )
                details = AccidentStore.shared.loadDetails(for: reportID)
            }
        }
        .onChange(of: dlScanImage) { _, image in
            guard let image else { return }
            Task {
                do {
                    guard let payload = try await OCRService.shared.detectBarcode(in: image) else {
                        print("🪪 No PDF417 barcode found in gallery DL scan.")
                        showDLScanErrorAlert = true
                        return
                    }
                    let parsed = DLParser.parse(payload: payload)
                    print("🛠 PARSER RESULT: \(parsed)")
                    if let license = parsed.licenseNumber, !license.isEmpty {
                        let fullName = [parsed.firstName, parsed.lastName]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        AccidentStore.shared.updateIncidentDetails(
                            for: reportID,
                            provider:       details?.otherDriverProvider ?? "",
                            policyNumber:   details?.otherDriverPolicyNumber ?? "",
                            driverName:     fullName.isEmpty ? (details?.otherDriverName ?? "") : fullName,
                            licenseNumber:  license,
                            dateOfBirth:    parsed.dateOfBirth    ?? details?.dateOfBirth    ?? "",
                            issueDate:      parsed.issueDate      ?? details?.issueDate      ?? "",
                            expirationDate: parsed.expirationDate ?? details?.expirationDate ?? ""
                        )
                        details = AccidentStore.shared.loadDetails(for: reportID)
                    } else {
                        print("🪪 Parsed payload lacked a usable license number — fields not updated.")
                        showDLScanErrorAlert = true
                    }
                } catch {
                    print("🪪 Barcode detection error: \(error.localizedDescription)")
                    showDLScanErrorAlert = true
                }
            }
        }
        .alert("Scan Failed", isPresented: $showDLScanErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We couldn't capture the driver's license information from that photo. Please try again in a well-lit area, holding the barcode flat and free of glare.")
        }
        .alert("Tip for a Better Scan", isPresented: $showCaptureReminder) {
            Button("Continue") {
                pendingCaptureAction?()
                pendingCaptureAction = nil
            }
            Button("Cancel", role: .cancel) { pendingCaptureAction = nil }
        } message: {
            Text("For best results, capture the photo in a well-lit area and avoid glare on the card.")
        }
    }

    // MARK: - Video Evidence section

    private var videoEvidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video Evidence")
                .font(.title3.bold())
                .padding(.horizontal, 20)

            if !loadedVideoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(loadedVideoURLs, id: \.self) { url in
                            VStack(spacing: 6) {
                                VideoPlayer(player: AVPlayer(url: url))
                                    .frame(width: 320, height: 240) // Nice, big cinematic view
                                    .background(Color.black)
                                    .cornerRadius(12)

                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 320)
                            }
                            .contextMenu {
                                Button {
                                    videoToRename = url
                                    newVideoName = url.deletingPathExtension().lastPathComponent
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    AccidentStore.shared.deleteVideo(at: url)
                                    DispatchQueue.main.async {
                                        loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Menu {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Record Video", systemImage: "camera")
                }

                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showDashcamPicker = true
                    }
                } label: {
                    Label("Upload from Dashcam", systemImage: "arrow.up.doc")
                }
            } label: {
                Label("Add Video Evidence", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 20)
            .photosPicker(isPresented: $showDashcamPicker, selection: $selectedVideoItem, matching: .videos)
        }
    }

    // MARK: - Other Driver section

    private var otherDriverSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header row with Edit / Save toggle
            HStack(alignment: .firstTextBaseline) {
                Text("Other Driver")
                    .font(.title3.bold())
                Spacer(minLength: 0)
                Button {
                    if isEditing {
                        AccidentStore.shared.updateIncidentDetails(
                            for: reportID,
                            provider: editProvider,
                            policyNumber: editPolicyNumber,
                            driverName: editDriverName,
                            licenseNumber: editLicenseNumber,
                            dateOfBirth: details?.dateOfBirth ?? "",
                            issueDate: details?.issueDate ?? "",
                            expirationDate: details?.expirationDate ?? ""
                        )
                        details = AccidentStore.shared.loadDetails(for: reportID)
                        isEditing = false
                    } else {
                        editProvider       = details?.otherDriverProvider      ?? ""
                        editPolicyNumber   = details?.otherDriverPolicyNumber  ?? ""
                        editDriverName     = details?.otherDriverName          ?? ""
                        editLicenseNumber  = details?.otherDriverLicenseNumber ?? ""
                        isEditing = true
                    }
                } label: {
                    Text(isEditing ? "Save" : "Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEditing ? .white : safetyRed)
                        .padding(.horizontal, isEditing ? 14 : 0)
                        .padding(.vertical,   isEditing ? 6  : 0)
                        .background(
                            Capsule()
                                .fill(isEditing ? safetyRed : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isEditing)
            }
            .padding(.horizontal, 20)

            // Card — rows swap between read-only and editable based on isEditing
            VStack(spacing: 0) {
                if isEditing {
                    editRow(icon: "building.2",  label: "Provider",       text: $editProvider,
                            keyboardType: .default, capitalization: .words)
                    Divider().padding(.leading, 52)
                    editRow(icon: "number",       label: "Policy Number",  text: $editPolicyNumber,
                            keyboardType: .asciiCapable, capitalization: .characters)
                    Divider().padding(.leading, 52)
                    editRow(icon: "person",       label: "Driver Name",    text: $editDriverName,
                            keyboardType: .default, capitalization: .words)
                    Divider().padding(.leading, 52)
                    editRow(icon: "creditcard",   label: "License Number", text: $editLicenseNumber,
                            keyboardType: .asciiCapable, capitalization: .characters)
                } else {
                    detailRow(icon: "building.2", label: "Provider",       value: details?.otherDriverProvider)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "number",      label: "Policy Number",  value: details?.otherDriverPolicyNumber)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "person",      label: "Driver Name",    value: details?.otherDriverName)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "creditcard",  label: "License Number", value: details?.otherDriverLicenseNumber)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar",                        label: "Date of Birth",    value: details?.dateOfBirth)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar.badge.plus",             label: "Issue Date",       value: details?.issueDate)
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar.badge.exclamationmark",  label: "Expiration Date",  value: details?.expirationDate)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 0.18), value: isEditing)

            HStack(spacing: 12) {
                Button {
                    pendingCaptureAction = { showInsuranceSourceDialog = true }
                    showCaptureReminder = true
                } label: {
                    Label("Scan Insurance", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    pendingCaptureAction = { showDLSourceDialog = true }
                    showCaptureReminder = true
                } label: {
                    Label("Scan License", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Row helpers

    /// Read-only row: shows a caption label and a body-sized value (or a greyed dash when nil).
    private func detailRow(icon: String, label: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value ?? "—")
                    .font(.body)
                    .foregroundStyle(value != nil ? .primary : .tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Editable row: same icon + label layout, but body area is a TextField.
    private func editRow(
        icon: String,
        label: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        capitalization: TextInputAutocapitalization
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(label, text: text)
                    .font(.body)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        IncidentEvidenceTabView(reportID: UUID(), photoCount: 0)
    }
}

import CoreTransferable

struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Create a safe temporary copy
            let fileName = received.file.lastPathComponent
            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // Clean up any old temp file before moving the new one
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return VideoFile(url: copyURL)
        }
    }
}
