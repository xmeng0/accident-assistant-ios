//
//  AccidentWizardView.swift
//  AccidentAssistant
//
//  Created by Sean Meng on 4/19/26.
//

import SwiftUI
import UIKit
import MapKit
import PhotosUI

struct AccidentWizardView: View {
    /// When set, the Wizard resumes this existing draft accident instead of starting a fresh
    /// one — its already-saved photos (and telemetry) are picked back up rather than lost.
    var resumeID: UUID? = nil

    enum Step: Int, CaseIterable {
        case safety    = 1
        case location  = 2
        case hazard    = 3
        case police    = 4
        case photos    = 5
        case insurance = 6

        var title: String {
            switch self {
            case .safety:    return "Safety First"
            case .location:  return "Incident Location"
            case .hazard:    return "Secure the Scene"
            case .police:    return "Authorities"
            case .photos:    return "Document Scene"
            case .insurance: return "Other Driver's Information"
            }
        }

        var instruction: String {
            switch self {
            case .safety:
                return "Check yourself and others for injuries."
            case .location:
                return "Confirm where the incident happened."
            case .hazard:
                return "Move to the shoulder if possible. Turn on hazard lights."
            case .police:
                return "Call police for injuries, major damage, or if the other driver is uncooperative."
            case .photos:
                return "Take photos of vehicles and the surrounding area before they are moved."
            case .insurance:
                return "Scan or enter the other driver's insurance and driver license details"
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .safety:    return "Everyone is Safe"
            case .location:  return "Use This Location and Time"
            case .hazard:    return "Scene is Secure"
            case .police:    return "Continue to Photos"
            case .photos:    return "Open Camera"
            case .insurance: return "Review Report"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var currentStep: Step = .safety
    @State private var showCamera = false
    /// Temporary bridge: receives from ImagePicker then is saved immediately via `addCapturedPhoto`.
    @State private var cameraImage: UIImage?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var incidentDate: Date = Date()

    /// The draft accident created as soon as the user takes their first photo in this Wizard
    /// session — nil until then. Photos are saved directly to it (mirroring the Evidence Tab)
    /// instead of being held in memory and flushed at the end.
    @State private var wizardAccidentID: UUID? = nil
    @State private var loadedImageURLs: [URL] = []
    /// Set right before the Wizard dismisses via a successful save, so `discardDraftIfNeeded()`
    /// knows not to delete the draft the user just finished.
    @State private var didCompleteWizard = false
    /// True when this session picked up an existing draft via `resumeID` — cancelling out of a
    /// resumed session should leave the draft (and its photos) exactly as they already were,
    /// not discard it, since it was intentionally saved for later.
    @State private var isResumingDraft = false

    // Step 5 — Other Driver's Insurance
    @State private var insuranceProvider: String = ""
    @State private var policyNumber: String = ""
    @State private var otherDriverName: String = ""
    @State private var licenseNumber: String = ""
    @State private var dateOfBirth: String = ""
    @State private var issueDate: String = ""
    @State private var expirationDate: String = ""
    @State private var showOCRScanner: Bool = false
    @State private var showDLScanner: Bool = false
    @State private var dlScanImage: UIImage? = nil
    @State private var showDLSourceDialog = false
    @State private var useCameraForDL = true
    @State private var showScanErrorAlert = false

    // Well-lit capture reminder — shown before either scan flow begins.
    @State private var showCaptureReminder = false
    @State private var pendingCaptureAction: (() -> Void)? = nil

    // Step 2 — Location
    @StateObject private var locationManager = LocationManager()
    @State private var incidentLocation: IncidentLocation?
    @State private var usingManualEntry = false

    private let safetyRed = Color(red: 0.86, green: 0.10, blue: 0.15)

    private var progressValue: Double { Double(currentStep.rawValue) }
    private var totalSteps: Double { Double(Step.allCases.count) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // Fixed Header
                VStack(alignment: .leading, spacing: 18) {
                    ProgressView(value: progressValue, total: totalSteps)
                        .tint(safetyRed)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(currentStep.title)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)

                        Text(currentStep.instruction)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 22)

                // Scrollable Content & Actions
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        scrollableStepContent

                        actionButtons
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if currentStep.rawValue > 1 {
                            currentStep = Step(rawValue: currentStep.rawValue - 1) ?? .safety
                        } else {
                            discardDraftIfNeeded()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Back")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        discardDraftIfNeeded()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: { showCamera = false }) {
                ImagePicker(image: $cameraImage, useCamera: true)
                    .ignoresSafeArea()
            }
            .onChange(of: cameraImage) { _, newImage in
                guard let newImage else { return }
                addCapturedPhoto(newImage)
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let items = newItems
                selectedPhotoItems = []
                Task {
                    for item in items {
                        await addLibraryPhoto(item)
                    }
                }
            }
            .sheet(isPresented: $showOCRScanner) {
                OCRScannerView { parsed in
                    if let provider = parsed.provider       { insuranceProvider  = provider  }
                    if let policy  = parsed.policyNumber    { policyNumber       = policy    }
                    if let name    = parsed.driverName      { otherDriverName    = name      }
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showDLSourceDialog, titleVisibility: .visible) {
                Button("Camera") { useCameraForDL = true; showDLScanner = true }
                Button("Photo Library") { useCameraForDL = false; showDLScanner = true }
            }
            .fullScreenCover(isPresented: $showDLScanner, onDismiss: { showDLScanner = false }) {
                ImagePicker(image: $dlScanImage, useCamera: useCameraForDL)
                    .ignoresSafeArea()
            }
            .onChange(of: dlScanImage) { _, image in
                guard let image else { return }
                Task { await processScannedDLImage(image) }
            }
            .alert("Scan Failed", isPresented: $showScanErrorAlert) {
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
        .onAppear { resumeDraftIfNeeded() }
        .onChange(of: incidentLocation) { _, newLocation in
            // As soon as a GPS fix or manual address resolves, the draft is guaranteed to exist
            // on disk — so it survives even if the user closes the Wizard before adding photos.
            guard newLocation != nil else { return }
            ensureAccidentCreated()
        }
    }

    /// Picks a resumed draft's accident ID back up, points the store at it, and reloads
    /// whatever photos (and telemetry) were already saved to it in an earlier session —
    /// jumping straight to the Photos step since that's the only state we can restore.
    private func resumeDraftIfNeeded() {
        guard let resumeID, wizardAccidentID == nil else { return }
        isResumingDraft = true
        wizardAccidentID = resumeID
        AccidentStore.shared.currentAccidentID = resumeID
        AccidentStore.shared.currentReportFolderURL = AccidentStore.shared.incidentFolderURL(for: resumeID)
        refreshLoadedImageURLs()
        currentStep = .photos
    }

    /// Extracted from `body` so the compiler doesn't have to type-check the
    /// step-conditional branches inline inside the ScrollView's VStack, which
    /// was causing "unable to type-check this expression in reasonable time."
    @ViewBuilder
    private var scrollableStepContent: some View {
        if currentStep == .location {
            locationStepContent
                .padding(.top, 4)
        }

        if currentStep == .insurance {
            insuranceStepContent
                .padding(.top, 4)
        }

        if currentStep == .photos {
            photosStepContent
                .padding(.top, 4)
        }
    }

    /// Live camera capture: creates the draft accident on first use, then immediately saves
    /// `image` to disk under a fallback timestamp name and refreshes the on-screen thumbnail
    /// strip. The AI-descriptive rename happens in the background (fire-and-forget) and never
    /// blocks the UI.
    private func addCapturedPhoto(_ image: UIImage) {
        ensureAccidentCreated()
        PhotoAutoNamer.saveAndAutoName(image) { _ in
            refreshLoadedImageURLs()
        } onRenamed: {
            refreshLoadedImageURLs()
        }
    }

    /// Library upload: creates the draft accident on first use, then saves the picked photo
    /// immediately with no AI naming — preserving its own original file name when meaningful,
    /// otherwise falling back to a "Library_" + creation-timestamp name.
    private func addLibraryPhoto(_ item: PhotosPickerItem) async {
        guard let imageFile = try? await item.loadTransferable(type: ImageFile.self),
              let image = UIImage(contentsOfFile: imageFile.url.path) else { return }

        ensureAccidentCreated()
        let originalName = imageFile.url.deletingPathExtension().lastPathComponent
        let creationDate = LibraryMediaNamer.creationDate(fromImageAt: imageFile.url)
        let fileName = LibraryMediaNamer.displayName(originalNameNoExtension: originalName, creationDate: creationDate)

        AccidentStore.shared.saveImage(image, fileName: fileName)
        refreshLoadedImageURLs()
    }

    /// Lazily creates the draft accident record the first time a photo needs to be saved,
    /// so the Wizard can persist evidence as it's captured instead of only at the final step.
    private func ensureAccidentCreated() {
        guard wizardAccidentID == nil else { return }
        AccidentStore.shared.createNewAccident(date: incidentDate)
        wizardAccidentID = AccidentStore.shared.currentAccidentID
    }

    private func refreshLoadedImageURLs() {
        guard let id = wizardAccidentID else { return }
        loadedImageURLs = AccidentStore.shared.getImageURLs(for: id)
    }

    /// Called when the user explicitly cancels out of the Wizard (the "X" button, or "Back" on
    /// the first step) instead of completing it. Acts as a strict gatekeeper: the draft is only
    /// ever deleted when the wizard is completely empty — it was NOT resumed from an existing
    /// draft/telemetry attachment (`resumeID == nil`), no location was resolved, and no photos
    /// were added. If the user attached telemetry, entered a location, or took a photo, the
    /// draft is left exactly as-is so it can be safely resumed later from the "Draft" card.
    private func discardDraftIfNeeded() {
        guard let id = wizardAccidentID,
              resumeID == nil,
              incidentLocation == nil,
              loadedImageURLs.isEmpty
        else { return }

        AccidentStore.shared.deleteReport(for: id)
        if AccidentStore.shared.currentAccidentID == id {
            AccidentStore.shared.currentAccidentID = nil
            AccidentStore.shared.currentReportFolderURL = nil
        }
        wizardAccidentID = nil
    }

    @MainActor
    private func processScannedDLImage(_ image: UIImage) async {
        do {
            guard let payload = try await OCRService.shared.detectBarcode(in: image) else {
                print("🪪 No PDF417 barcode found — user may need to scan back of ID.")
                showScanErrorAlert = true
                return
            }
            let parsed = DLParser.parse(payload: payload)
            print("🛠 PARSER RESULT: \(parsed)")

            let hasLicense = parsed.licenseNumber?.isEmpty == false
            let hasName = parsed.firstName?.isEmpty == false || parsed.lastName?.isEmpty == false

            guard hasLicense || hasName else {
                print("🪪 Parsed payload lacked a usable license number and name.")
                showScanErrorAlert = true
                return
            }

            if let license = parsed.licenseNumber, !license.isEmpty {
                licenseNumber = license
            }

            let fullName = [parsed.firstName, parsed.lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !fullName.isEmpty {
                otherDriverName = fullName
            }

            if let dob = parsed.dateOfBirth, !dob.isEmpty {
                dateOfBirth = dob
            }
            if let issue = parsed.issueDate, !issue.isEmpty {
                issueDate = issue
            }
            if let expiration = parsed.expirationDate, !expiration.isEmpty {
                expirationDate = expiration
            }
        } catch {
            print("🪪 Barcode detection error: \(error.localizedDescription)")
            showScanErrorAlert = true
        }
    }

    private func handlePrimaryAction() {
        switch currentStep {
        case .safety:
            locationManager.requestOneTimeLocation()
            currentStep = .location
        case .location:
            // GPS path: assign the resolved address and advance.
            if let resolved = locationManager.resolvedLocation, !usingManualEntry {
                incidentLocation = resolved
            }

            currentStep = .hazard
        case .hazard:
            currentStep = .police
        case .police:
            currentStep = .photos
        case .photos:
            break
        case .insurance:
            break
        }
    }

    private func callEmergencyServices() {
        if let url = URL(string: "tel://911") {
            openURL(url)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if currentStep == .photos {
                // Open Camera
                Button {
                    #if targetEnvironment(simulator)
                    let mock = UIImage(systemName: "photo.on.rectangle.angled") ?? UIImage()
                    addCapturedPhoto(mock)
                    #else
                    showCamera = true
                    #endif
                } label: {
                    Label("Open Camera", systemImage: "camera.fill")
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: Color(.secondaryLabel))

                // Photo Library (multi-select)
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: Color(.secondaryLabel))

                // Advance to insurance step
                Button {
                    currentStep = .insurance
                } label: {
                    Text(loadedImageURLs.isEmpty ? "Skip Photos" : "Continue")
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: safetyRed)

            } else if currentStep == .insurance {
                // NavigationLink constructs the IncidentReport from current state
                // and pushes the FNOL summary onto the NavigationStack.
                // .simultaneousGesture fires the store save without blocking navigation.
                NavigationLink {
                    FNOLSummaryView(
                        report: IncidentReport(
                            date:             incidentDate,
                            otherDriverName:  otherDriverName,
                            licenseNumber:    licenseNumber,
                            insuranceCompany: insuranceProvider,
                            policyNumber:     policyNumber,
                            location:         incidentLocation,
                            dateOfBirth:      dateOfBirth,
                            issueDate:        issueDate,
                            expirationDate:   expirationDate
                        ),
                        existingAccidentID: wizardAccidentID,
                        onSaved: {
                            // `currentAccidentID` is guaranteed correct here even if photos were
                            // skipped entirely (FNOLSummaryView creates the accident itself in
                            // that case) — fall back to it so the right draft always gets locked in.
                            if let finalID = wizardAccidentID ?? AccidentStore.shared.currentAccidentID {
                                AccidentStore.shared.finalizeAccident(for: finalID)
                            }
                            didCompleteWizard = true
                            dismiss()
                        }
                    )
                } label: {
                    Text(currentStep.primaryActionTitle)
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: safetyRed)
            } else if currentStep == .location && usingManualEntry {
                // No primary button — the user advances by tapping an autocomplete result.
                EmptyView()
            } else {
                Button {
                    handlePrimaryAction()
                } label: {
                    Text(currentStep.primaryActionTitle)
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: safetyRed)
            }

            if currentStep == .safety {
                Button {
                    callEmergencyServices()
                } label: {
                    Text("Call 911")
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: safetyRed, isHighContrastDestructive: true)
                .accessibilityLabel("Call 911")
            }
        }
    }

    // MARK: - Location step UI

    private var locationStepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !usingManualEntry {
                // GPS auto-detect card
                if let loc = locationManager.resolvedLocation {
                    HStack(spacing: 14) {
                        Image(systemName: "location.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.street.isEmpty ? "Location Detected" : loc.street)
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                            Text([loc.city, loc.state].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
                    )
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Detecting your location…")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                Button {
                    usingManualEntry = true
                } label: {
                    Label("Enter Address Manually", systemImage: "pencil")
                        .wizardButtonLabel()
                }
                .wizardPrimaryButton(background: Color(.secondaryLabel))

            } else {
                // Manual address search
                TextField("Search address…", text: $locationManager.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
                    .onChange(of: locationManager.searchQuery) { _, newValue in
                        locationManager.updateSearchQuery(newValue)
                    }

                if !locationManager.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(locationManager.searchResults, id: \.self) { result in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.system(.body, design: .rounded))
                                    Text(result.subtitle)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    locationManager.selectLocation(completion: result) { location in
                                        incidentLocation = location
                                        currentStep = .hazard
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Divider()

            DatePicker(
                "Incident Date & Time",
                selection: $incidentDate,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.system(.body, design: .rounded))
        }
    }

    // MARK: - Photos step UI

    private var photosStepContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loadedImageURLs.isEmpty {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No photos yet")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Use camera or choose from library.")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("\(loadedImageURLs.count) photo\(loadedImageURLs.count == 1 ? "" : "s") captured")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(loadedImageURLs, id: \.self) { url in
                            VStack(spacing: 4) {
                                wizardPhotoThumbnail(for: url)

                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 100)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    /// Loads a captured photo straight from disk for the Photos-step thumbnail strip.
    private func wizardPhotoThumbnail(for url: URL) -> some View {
        Group {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Insurance step UI

    private var insuranceStepContent: some View {
        VStack(spacing: 12) {
            Button {
                pendingCaptureAction = { showOCRScanner = true }
                showCaptureReminder = true
            } label: {
                Label("Scan Insurance Card", systemImage: "doc.viewfinder")
                    .wizardButtonLabel()
            }
            .wizardPrimaryButton(background: Color(.secondaryLabel))

            Button {
                pendingCaptureAction = { showDLSourceDialog = true }
                showCaptureReminder = true
            } label: {
                Label("Scan Driver's License", systemImage: "barcode.viewfinder")
                    .wizardButtonLabel()
            }
            .wizardPrimaryButton(background: Color(.secondaryLabel))

            VStack(spacing: 0) {
                insuranceField("Provider",       placeholder: "e.g., State Farm",      text: $insuranceProvider, icon: "building.2")
                Divider().padding(.leading, 44)
                insuranceField("Policy Number",  placeholder: "e.g., 123456789",        text: $policyNumber,      icon: "number")
                Divider().padding(.leading, 44)
                insuranceField("Driver Name",    placeholder: "First and Last Name",    text: $otherDriverName,   icon: "person")
                Divider().padding(.leading, 44)
                insuranceField("License Number", placeholder: "e.g., 12345678",         text: $licenseNumber,     icon: "creditcard")
                Divider().padding(.leading, 44)
                insuranceField("Date of Birth",    placeholder: "MM/DD/YYYY", text: $dateOfBirth,    icon: "calendar")
                Divider().padding(.leading, 44)
                insuranceField("Issue Date",       placeholder: "MM/DD/YYYY", text: $issueDate,      icon: "calendar.badge.plus")
                Divider().padding(.leading, 44)
                insuranceField("Expiration Date",  placeholder: "MM/DD/YYYY", text: $expirationDate, icon: "calendar.badge.exclamationmark")
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Insurance field helper

    /// Reusable row used inside the Step 6 insurance card form.
    /// Shows a persistent caption above the field so the label stays visible
    /// even after the user (or a DL scan) fills in a value — the icon and
    /// TextField placeholder alone aren't enough once the field is non-empty.
    /// `placeholder` shows a format hint (e.g. "e.g., State Farm") instead of repeating `label`.
    private func insuranceField(_ label: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
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
                    .font(.system(.body, design: .rounded))
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private extension View {
    func wizardButtonLabel() -> some View {
        self
            .font(.system(.title3, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
    }

    func wizardPrimaryButton(background: Color, isHighContrastDestructive: Bool = false) -> some View {
        self
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isHighContrastDestructive ? background : background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHighContrastDestructive ? 0.22 : 0), lineWidth: 1)
            )
            .shadow(color: background.opacity(0.22), radius: 14, x: 0, y: 8)
            .buttonStyle(.plain)
    }
}

#Preview {
    AccidentWizardView()
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    /// True → rear camera (evidence capture). False → photo library (DL barcode scan, etc.).
    var useCamera: Bool = false
    /// When true, the selected image is also persisted immediately to AccidentStore.
    var storeOnSelect: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        print("📸 Picker is launching now")

        if useCamera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .rear
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        // THE WIRE THAT MAKES THE SHUTTER WORK — without this, the picker never calls your Coordinator when the user taps Use Photo.
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    /// UIKit talks to objects, not SwiftUI structs. The Coordinator is a stable `class` that conforms to
    /// `UIImagePickerControllerDelegate` and can write into `parent.image` when the camera finishes.
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Same rule as below: dismiss the actual UIKit camera controller so the modal goes away.
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
                if parent.storeOnSelect {
                    AccidentStore.shared.saveImage(uiImage)
                    print("📸 Handshake complete: Image captured!")
                } else {
                    print("🪪 DL scan image received — barcode processing queued.")
                }
            }
            // picker.dismiss is the key: UIImagePickerController is a UIKit modal. Until you dismiss *that*
            // controller, it stays on screen even if SwiftUI state updated. This call tears down the
            // camera UI so it slides away after Use Photo (and SwiftUI’s fullScreenCover can finish too).
            picker.dismiss(animated: true)
        }
    }
}
