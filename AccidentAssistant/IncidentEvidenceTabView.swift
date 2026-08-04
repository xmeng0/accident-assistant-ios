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

/// Identifies which single item a "Rename" context menu action targets.
private enum RenameTarget: Identifiable {
    case photo(URL)
    case video(URL)

    var id: URL {
        switch self {
        case .photo(let url), .video(let url): return url
        }
    }
}

struct IncidentEvidenceTabView: View {
    let reportID: UUID
    let photoCount: Int

    @State private var loadedImageURLs: [URL] = []
    @State private var details: AccidentReport? = nil

    // Full-screen media preview
    @State private var selectedPhoto: IdentifiableURL? = nil
    @State private var selectedVideo: IdentifiableURL? = nil

    // Bulk-select ("Select" toggle) for photos and videos
    @State private var isSelectionMode = false
    @State private var selectedPhotoURLs: Set<URL> = []
    @State private var selectedVideoURLs: Set<URL> = []

    // Single-item rename (via context menu)
    @State private var renameTarget: RenameTarget? = nil
    @State private var newMediaName: String = ""

    // Edit mode
    @State private var isEditing = false
    @State private var editProvider = ""
    @State private var editPolicyNumber = ""
    @State private var editDriverName = ""
    @State private var editLicenseNumber = ""
    @State private var editDateOfBirth = ""
    @State private var editIssueDate = ""
    @State private var editExpirationDate = ""

    // Add Photo (confirmation dialog: camera vs. library)
    @State private var showAddPhotoSourceDialog = false
    @State private var showPhotoCamera = false
    @State private var showPhotoLibraryPicker = false
    @State private var cameraPhotoImage: UIImage? = nil
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // Video evidence — Add Video (confirmation dialog: camera vs. library)
    @State private var showAddVideoSourceDialog = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var loadedVideoURLs: [URL] = []
    @State private var isShowingCamera = false
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

                HStack(alignment: .firstTextBaseline) {
                    Text("Evidence Photos")
                        .font(.title3.bold())
                    Spacer(minLength: 0)
                    if !loadedImageURLs.isEmpty {
                        selectionToggleButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 10)

                if loadedImageURLs.isEmpty {
                    Text("No photos available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(loadedImageURLs, id: \.self) { url in
                            photoCell(for: url)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                addPhotosButton
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
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                selectionToolbar
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("New name", text: $newMediaName)
            Button("Save") {
                switch renameTarget {
                case .photo(let url):
                    AccidentStore.shared.renamePhoto(at: url, to: newMediaName)
                    loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
                case .video(let url):
                    AccidentStore.shared.renameVideo(at: url, to: newMediaName, for: reportID)
                    loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                case .none:
                    break
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .onAppear {
            loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
            details = AccidentStore.shared.loadDetails(for: reportID)
            loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
        }
        .fullScreenCover(item: $selectedPhoto) { item in
            MediaFullScreenView {
                if let uiImage = UIImage(contentsOfFile: item.url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    Text("Unable to load photo")
                        .foregroundStyle(.white)
                }
            } onDelete: {
                AccidentStore.shared.deleteImage(at: item.url, for: reportID)
                loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
                selectedPhoto = nil
            } onDismiss: {
                selectedPhoto = nil
            }
        }
        .fullScreenCover(item: $selectedVideo) { item in
            MediaFullScreenView {
                VideoPlayer(player: AVPlayer(url: item.url))
            } onDelete: {
                AccidentStore.shared.deleteVideo(at: item.url)
                loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                selectedVideo = nil
            } onDismiss: {
                selectedVideo = nil
            }
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
            // Library uploads never get AI naming — just preserve the asset's own file name
            // (or fall back to a "Library_" + creation-timestamp name).
            item.loadTransferable(type: VideoFile.self) { result in
                switch result {
                case .success(let video):
                    guard let video else { return }
                    Task {
                        let originalName = video.url.deletingPathExtension().lastPathComponent
                        let creationDate = await LibraryMediaNamer.creationDate(fromVideoAt: video.url)
                        let fileName = LibraryMediaNamer.displayName(originalNameNoExtension: originalName, creationDate: creationDate)
                        await MainActor.run {
                            AccidentStore.shared.saveVideo(from: video.url, for: reportID, fileName: fileName)
                            self.loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                        }
                    }
                case .failure(let error):
                    print("Video load failed: \(error.localizedDescription)")
                }
            }
        }
        .fullScreenCover(isPresented: $showPhotoCamera) {
            ImagePicker(image: $cameraPhotoImage, useCamera: true)
                .ignoresSafeArea()
        }
        .onChange(of: cameraPhotoImage) { _, newImage in
            guard let newImage else { return }
            AccidentStore.shared.currentAccidentID = reportID
            addPhoto(newImage)
        }
        .onChange(of: selectedPhotoItems) {
                    guard !selectedPhotoItems.isEmpty else { return }
                    let items = selectedPhotoItems
                    selectedPhotoItems = []
                    AccidentStore.shared.currentAccidentID = reportID
                    Task {
                        for item in items {
                            await addLibraryPhoto(item)
                        }
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

    // MARK: - Adding photos

    /// Live camera capture: immediately saves `image` to disk under a fallback timestamp name
    /// and refreshes the grid; the AI-descriptive rename happens in the background and never
    /// blocks the UI.
    private func addPhoto(_ image: UIImage) {
        PhotoAutoNamer.saveAndAutoName(image) { _ in
            loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
        } onRenamed: {
            loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
        }
    }

    /// Library upload: no AI naming — preserves the asset's own original file name when
    /// available and meaningful, otherwise falls back to a "Library_" + creation-timestamp name.
    private func addLibraryPhoto(_ item: PhotosPickerItem) async {
        guard let imageFile = try? await item.loadTransferable(type: ImageFile.self),
              let image = UIImage(contentsOfFile: imageFile.url.path) else { return }

        let originalName = imageFile.url.deletingPathExtension().lastPathComponent
        let creationDate = LibraryMediaNamer.creationDate(fromImageAt: imageFile.url)
        let fileName = LibraryMediaNamer.displayName(originalNameNoExtension: originalName, creationDate: creationDate)

        AccidentStore.shared.saveImage(image, fileName: fileName)
        loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
    }

    // MARK: - Selection mode (bulk delete)

    private var selectedCount: Int { selectedPhotoURLs.count + selectedVideoURLs.count }

    private func togglePhotoSelection(_ url: URL) {
        if selectedPhotoURLs.contains(url) {
            selectedPhotoURLs.remove(url)
        } else {
            selectedPhotoURLs.insert(url)
        }
    }

    private func toggleVideoSelection(_ url: URL) {
        if selectedVideoURLs.contains(url) {
            selectedVideoURLs.remove(url)
        } else {
            selectedVideoURLs.insert(url)
        }
    }

    /// Toggled by the "Select"/"Cancel" button in either section header.
    private func toggleSelectionMode() {
        if isSelectionMode {
            cancelSelectionMode()
        } else {
            isSelectionMode = true
        }
    }

    private func cancelSelectionMode() {
        isSelectionMode = false
        selectedPhotoURLs.removeAll()
        selectedVideoURLs.removeAll()
    }

    /// Removes every selected photo and video from the underlying data model, refreshes
    /// the galleries, and exits Selection Mode so the UI returns to normal.
    private func deleteSelectedMedia() {
        for url in selectedPhotoURLs {
            AccidentStore.shared.deleteImage(at: url, for: reportID)
        }
        for url in selectedVideoURLs {
            AccidentStore.shared.deleteVideo(at: url)
        }
        loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
        loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
        cancelSelectionMode()
    }

    /// Floating action bar shown only while Selection Mode is active.
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                cancelSelectionMode()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                deleteSelectedMedia()
            } label: {
                Label("Delete \(selectedCount) Item\(selectedCount == 1 ? "" : "s")", systemImage: "trash.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// "Select"/"Cancel" toggle shown at the top-right of each gallery section header.
    private var selectionToggleButton: some View {
        Button(isSelectionMode ? "Cancel" : "Select") {
            toggleSelectionMode()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.blue)
    }

    /// Blue-filled circle with a white checkmark when selected; a translucent outline otherwise.
    private func selectionBadge(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.black.opacity(0.35))
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Photo thumbnail helper

    /// Loads a single photo from disk and renders it as a grid thumbnail, dimming it and
    /// overlaying a selection badge while Selection Mode is active.
    private func photoThumbnail(for url: URL, isSelected: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 110)
            .clipped()

            if isSelectionMode {
                if isSelected {
                    Color.black.opacity(0.35)
                }
                selectionBadge(isSelected: isSelected)
                    .padding(6)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Small, secondary-styled caption shown under a media thumbnail to display its current
    /// (possibly AI-generated) file name. Centered and truncated in the middle so long
    /// auto-generated names stay readable without breaking the grid layout.
    private func mediaFileNameLabel(for url: URL) -> some View {
        Text(url.deletingPathExtension().lastPathComponent)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Full grid cell for a photo: the thumbnail, its file name caption, and tap behavior.
    /// The single-item "Rename"/"Delete" context menu (long-press) is only attached outside
    /// Selection Mode, so it never fights with the tap-to-select gesture.
    @ViewBuilder
    private func photoCell(for url: URL) -> some View {
        let cell = VStack(spacing: 4) {
            photoThumbnail(for: url, isSelected: selectedPhotoURLs.contains(url))
                .onTapGesture {
                    if isSelectionMode {
                        togglePhotoSelection(url)
                    } else {
                        selectedPhoto = IdentifiableURL(url: url)
                    }
                }

            mediaFileNameLabel(for: url)
        }

        if isSelectionMode {
            cell
        } else {
            cell.contextMenu {
                Button {
                    newMediaName = url.deletingPathExtension().lastPathComponent
                    renameTarget = .photo(url)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    AccidentStore.shared.deleteImage(at: url, for: reportID)
                    loadedImageURLs = AccidentStore.shared.getImageURLs(for: reportID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// Lightweight, tappable video thumbnail (the real playable `VideoPlayer` only exists
    /// inside the full-screen viewer). Scales proportionally to a 16:9 aspect ratio so it
    /// fits cleanly into the two-column grid. Dims and overlays a selection badge in
    /// Selection Mode.
    private func videoThumbnail(for url: URL, isSelected: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Color.black
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if isSelectionMode {
                if isSelected {
                    Color.black.opacity(0.35)
                }
                selectionBadge(isSelected: isSelected)
                    .padding(8)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Full grid cell for a video: the thumbnail, its file name caption, and tap behavior.
    /// The single-item "Rename"/"Delete" context menu (long-press) is only attached outside
    /// Selection Mode.
    @ViewBuilder
    private func videoCell(for url: URL) -> some View {
        let cell = VStack(spacing: 4) {
            videoThumbnail(for: url, isSelected: selectedVideoURLs.contains(url))
                .onTapGesture {
                    if isSelectionMode {
                        toggleVideoSelection(url)
                    } else {
                        selectedVideo = IdentifiableURL(url: url)
                    }
                }

            mediaFileNameLabel(for: url)
        }

        if isSelectionMode {
            cell
        } else {
            cell.contextMenu {
                Button {
                    newMediaName = url.deletingPathExtension().lastPathComponent
                    renameTarget = .video(url)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    AccidentStore.shared.deleteVideo(at: url)
                    loadedVideoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Video Evidence section

    private let videoColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var videoEvidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Video Evidence")
                    .font(.title3.bold())
                Spacer(minLength: 0)
                if !loadedVideoURLs.isEmpty {
                    selectionToggleButton
                }
            }
            .padding(.horizontal, 20)

            if loadedVideoURLs.isEmpty {
                Text("No videos available")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: videoColumns, spacing: 16) {
                    ForEach(loadedVideoURLs, id: \.self) { url in
                        videoCell(for: url)
                    }
                }
                .padding(.horizontal, 20)
            }

            addVideoButton
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Evidence action buttons (Add Photos / Add Video)

    /// Standard-height, softly rounded iOS action button. Kept as a clean, secondary
    /// affordance (not a dramatic block) so it doesn't compete with the evidence content above it.
    /// Presents a confirmation dialog (action sheet) matching `addVideoButton`'s pattern.
    private var addPhotosButton: some View {
        Button {
            showAddPhotoSourceDialog = true
        } label: {
            Label("Add More Photos", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.blue)
        .confirmationDialog("Add Photo", isPresented: $showAddPhotoSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") {
                showPhotoCamera = true
            }
            Button("Choose from Library") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showPhotoLibraryPicker = true
                }
            }
        }
        .photosPicker(isPresented: $showPhotoLibraryPicker, selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images)
    }

    /// Standard-height, softly rounded iOS action button, placed directly under the
    /// Video Evidence content it controls. Presents a confirmation dialog (action sheet)
    /// matching `addPhotosButton`'s pattern.
    private var addVideoButton: some View {
        Button {
            showAddVideoSourceDialog = true
        } label: {
            Label("Add Video Evidence", systemImage: "video.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.blue)
        .confirmationDialog("Add Video", isPresented: $showAddVideoSourceDialog, titleVisibility: .visible) {
            Button("Record Video") {
                isShowingCamera = true
            }
            Button("Choose from Library") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showDashcamPicker = true
                }
            }
        }
        .photosPicker(isPresented: $showDashcamPicker, selection: $selectedVideoItem, matching: .videos)
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
                            dateOfBirth: editDateOfBirth,
                            issueDate: editIssueDate,
                            expirationDate: editExpirationDate
                        )
                        details = AccidentStore.shared.loadDetails(for: reportID)
                        isEditing = false
                    } else {
                        editProvider        = details?.otherDriverProvider      ?? ""
                        editPolicyNumber    = details?.otherDriverPolicyNumber  ?? ""
                        editDriverName      = details?.otherDriverName          ?? ""
                        editLicenseNumber   = details?.otherDriverLicenseNumber ?? ""
                        editDateOfBirth     = details?.dateOfBirth              ?? ""
                        editIssueDate       = details?.issueDate                ?? ""
                        editExpirationDate  = details?.expirationDate           ?? ""
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
                    editRow(icon: "building.2",  label: "Provider",       placeholder: "e.g., State Farm", text: $editProvider,
                            keyboardType: .default, capitalization: .words)
                    Divider().padding(.leading, 52)
                    editRow(icon: "number",       label: "Policy Number",  placeholder: "e.g., 123456789", text: $editPolicyNumber,
                            keyboardType: .asciiCapable, capitalization: .characters)
                    Divider().padding(.leading, 52)
                    editRow(icon: "person",       label: "Driver Name",    placeholder: "First and Last Name", text: $editDriverName,
                            keyboardType: .default, capitalization: .words)
                    Divider().padding(.leading, 52)
                    editRow(icon: "creditcard",   label: "License Number", placeholder: "e.g., 12345678", text: $editLicenseNumber,
                            keyboardType: .asciiCapable, capitalization: .characters)
                    Divider().padding(.leading, 52)
                    editRow(icon: "calendar",                       label: "Date of Birth",   placeholder: "MM/DD/YYYY", text: $editDateOfBirth,
                            keyboardType: .numbersAndPunctuation, capitalization: .never)
                    Divider().padding(.leading, 52)
                    editRow(icon: "calendar.badge.plus",            label: "Issue Date",      placeholder: "MM/DD/YYYY", text: $editIssueDate,
                            keyboardType: .numbersAndPunctuation, capitalization: .never)
                    Divider().padding(.leading, 52)
                    editRow(icon: "calendar.badge.exclamationmark", label: "Expiration Date", placeholder: "MM/DD/YYYY", text: $editExpirationDate,
                            keyboardType: .numbersAndPunctuation, capitalization: .never)
                } else {
                    detailRow(icon: "building.2", label: "Provider",       value: details?.otherDriverProvider, placeholder: "e.g., State Farm")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "number",      label: "Policy Number",  value: details?.otherDriverPolicyNumber, placeholder: "e.g., 123456789")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "person",      label: "Driver Name",    value: details?.otherDriverName, placeholder: "First and Last Name")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "creditcard",  label: "License Number", value: details?.otherDriverLicenseNumber, placeholder: "e.g., 12345678")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar",                        label: "Date of Birth",    value: details?.dateOfBirth, placeholder: "MM/DD/YYYY")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar.badge.plus",             label: "Issue Date",       value: details?.issueDate, placeholder: "MM/DD/YYYY")
                    Divider().padding(.leading, 52)
                    detailRow(icon: "calendar.badge.exclamationmark",  label: "Expiration Date",  value: details?.expirationDate, placeholder: "MM/DD/YYYY")
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

    /// Read-only row: shows a caption label and a body-sized value, or a subtle gray
    /// format-hint placeholder (e.g. "e.g., State Farm") in place of a value when empty.
    private func detailRow(icon: String, label: String, value: String?, placeholder: String) -> some View {
        let hasValue = !(value ?? "").isEmpty
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(hasValue ? value! : placeholder)
                    .font(.body)
                    .foregroundStyle(hasValue ? Color.primary : Color(.tertiaryLabel))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Editable row: same icon + label layout, but body area is a TextField.
    /// `placeholder` shows a format hint (e.g. "e.g., State Farm") instead of repeating `label`.
    private func editRow(
        icon: String,
        label: String,
        placeholder: String,
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
                TextField(placeholder, text: text)
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

// MARK: - Identifiable URL wrapper (required for fullScreenCover(item:))

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Full-screen media viewer

/// Shared full-screen presentation for a single photo or video: dark backdrop, a "Done"
/// button to dismiss, and a red trash button that confirms before deleting the underlying file.
struct MediaFullScreenView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                    Spacer()

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(Color.red))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()
            }
        }
        .alert("Delete This Item?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action can't be undone.")
        }
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
