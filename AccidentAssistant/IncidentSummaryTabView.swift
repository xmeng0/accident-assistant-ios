//
//  IncidentSummaryTabView.swift
//  AccidentAssistant
//
//  Summary tab — paperwork view of all captured data, AI reconstruction,
//  and PDF export for a saved incident.
//

import SwiftUI

struct IncidentSummaryTabView: View {
    let reportID: UUID
    let photoCount: Int

    @State private var details: AccidentReport? = nil
    @State private var summary: AccidentSummary? = nil

    @State private var driverDescription: String = ""

    @AppStorage("selectedAIModel") private var selectedAIModel: GeminiModel = .efficient
    @State private var aiReportText: String? = nil
    @State private var parsedReport: ParsedReconstruction? = nil
    @State private var isGeneratingReport: Bool = false
    @State private var aiError: String? = nil
    @State private var pdfURLToShare: IdentifiablePDFURL? = nil
    @State private var isExportingPDF: Bool = false

    private let safetyRed = Color(red: 0.86, green: 0.10, blue: 0.15)

    var body: some View {
        Form {

            // Incident metadata
            Section("Incident Details") {
                if let date = summary?.date {
                    row(label: "Date", value: date.formatted(date: .long, time: .omitted))
                }
                
                if let location = details?.location {
                                    row(label: "Location", value: location.formattedAddress)
                                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("What Happened")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $driverDescription)
                        .font(.body)
                        .frame(minHeight: 80)
                }
                .padding(.vertical, 4)
                .onChange(of: driverDescription) { _, newValue in
                    AccidentStore.shared.saveIncidentDescription(newValue, for: reportID)
                }
            }

            // AI Accident Reconstruction
            Section("AI Accident Reconstruction") {

                Picker("Model", selection: $selectedAIModel) {
                    Text("Standard (Fast)").tag(GeminiModel.efficient)
                    Text("Forensic (Deep)").tag(GeminiModel.frontier)
                }
                .pickerStyle(.segmented)

                Button(isGeneratingReport ? "Analyzing Evidence..." : "Generate AI Reconstruction") {
                    Task { @MainActor in
                        defer { isGeneratingReport = false }
                        isGeneratingReport = true
                        aiError = nil
                        do {
                            let images    = AccidentStore.shared.getImages(for: reportID)
                            let videoURLs = AccidentStore.shared.getVideoURLs(for: reportID)
                            let telemetry = AccidentStore.shared.loadTelemetry(for: reportID) ?? "{}"

                            let result = try await GeminiService.shared.generateReconstruction(
                                images: images,
                                videoURLs: videoURLs,
                                telemetry: telemetry,
                                model: selectedAIModel
                            )
                            aiReportText = result
                            AccidentStore.shared.saveAIReconstruction(result, for: reportID)
                            parsedReport = decodeReconstruction(result)
                        } catch {
                            aiError = error.localizedDescription
                        }
                    }
                }
                .disabled(isGeneratingReport)

                if isGeneratingReport {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Analyzing evidence...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = aiError {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if let report = parsedReport {
                // Summary
                Section {
                    Text(report.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)
                } header: {
                    Label("Summary", systemImage: "doc.text.magnifyingglass")
                }

                // Timeline
                Section {
                    ForEach(report.timeline) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(event.time, systemImage: timelineIcon(for: event.time))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(event.description)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label("Timeline", systemImage: "clock.arrow.circlepath")
                }

                // Visual Damage Assessment
                Section {
                    Text(report.visualDamage)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Label("Visual Damage Assessment", systemImage: "exclamationmark.triangle")
                }

                // Environmental Factors
                Section {
                    envRow(icon: "cloud.sun", label: "Weather",
                           value: report.environmentalFactors.weather)
                    envRow(icon: "lightbulb", label: "Lighting",
                           value: report.environmentalFactors.lighting)
                    envRow(icon: "road.lanes", label: "Road & Traffic",
                           value: report.environmentalFactors.roadAndTraffic)
                } header: {
                    Label("Environmental Factors", systemImage: "thermometer.sun")
                }

                // Liability Indicators
                Section {
                    Text(report.liabilityIndicators)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Label("Liability Indicators", systemImage: "scalemass")
                }
            }

            // Export
            Section {
                Button {
                    guard let report = parsedReport else { return }
                    isExportingPDF = true
                    Task { @MainActor in
                        defer { isExportingPDF = false }
                        if let url = ReportPDFGenerator.generateAndSavePDF(
                            reportID: reportID,
                            aiReport: report
                        ) {
                            pdfURLToShare = IdentifiablePDFURL(url: url)
                            
                            #if DEBUG
                            print("📄 MY PDF IS LOCATED AT: \(url.path())")
                            #endif
                        }
                    }
                } label: {
                    if isExportingPDF {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Generating PDF…")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                    } else {
                        Label("Export to PDF", systemImage: "arrow.up.doc.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                    }
                }
                .listRowBackground(parsedReport == nil ? Color.gray : safetyRed)
                .disabled(parsedReport == nil || isExportingPDF)
            }
        }
        .sheet(item: $pdfURLToShare) { item in
            ShareSheet(pdfURL: item.url)
        }
        .onAppear {
            details = AccidentStore.shared.loadDetails(for: reportID)
            summary = AccidentStore.shared.getAllSummaries().first { $0.id == reportID }
            driverDescription = details?.incidentDescription ?? ""
            let stored = AccidentStore.shared.loadAIReconstruction(for: reportID)
            aiReportText = stored
            parsedReport = stored.flatMap { decodeReconstruction($0) }
        }
    }

    // MARK: - Helpers

    /// Flexible row: accepts an optional value and shows "—" when nil.
    private func row(label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(value != nil ? .primary : .tertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Two-line environmental factor row with an SF Symbol icon.
    private func envRow(icon: String, label: String, value: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }

    /// Maps a timeline phase name to a descriptive SF Symbol.
    private func timelineIcon(for phase: String) -> String {
        switch phase.lowercased() {
        case let p where p.contains("pre"):    return "arrow.right.circle"
        case let p where p.contains("impact"): return "exclamationmark.circle.fill"
        case let p where p.contains("post"):   return "arrow.down.circle"
        default:                               return "clock"
        }
    }

    /// Strips optional markdown code fences Gemini may inject despite instructions,
    /// then decodes the raw JSON into a `ParsedReconstruction`.
    private func decodeReconstruction(_ raw: String) -> ParsedReconstruction? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ParsedReconstruction.self, from: data)
    }
}

#Preview {
    NavigationStack {
        IncidentSummaryTabView(reportID: UUID(), photoCount: 0)
    }
}

// MARK: - Identifiable URL wrapper (required for sheet(item:))

struct IdentifiablePDFURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Pro share sheet with email metadata

import UIKit

/// Attaches a pre-filled email subject line when the share sheet detects Mail.
final class ReportActivityItemSource: NSObject, UIActivityItemSource {
    private let pdfURL: URL

    init(pdfURL: URL) {
        self.pdfURL = pdfURL
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        pdfURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        pdfURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        activityType == .mail
            ? "Accident Assistant: FNOL Reconstruction Report"
            : ""
    }
}

/// UIKit share sheet wrapped for SwiftUI presentation.
struct ShareSheet: UIViewControllerRepresentable {
    let pdfURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = ReportActivityItemSource(pdfURL: pdfURL)
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
