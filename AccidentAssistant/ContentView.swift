//
//  ContentView.swift
//  AccidentAssistant
//
//  Created by Sean Meng on 4/17/26.
//

import SwiftUI

struct ContentView: View {
    private let safetyRed = Color(red: 0.86, green: 0.10, blue: 0.15)
    @State private var isWizardShowing = false
    @State private var showTelemetryAlert = false
    @State private var createdReportID: UUID?
    /// Set when the user taps a "Draft" report card, so the Wizard can pick that accident's
    /// photos back up instead of starting a brand-new one.
    @State private var resumeDraftID: UUID? = nil
    @StateObject private var viewModel = EvidenceGalleryViewModel()
    @StateObject private var telemetry = TelemetryManager.shared
    @ObservedObject private var store = AccidentStore.shared

    var body: some View {
        NavigationStack {
            List {
                Group {
                    safetyTipBanner

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accident Assistant")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)

                        Text("Capture details fast and accurately.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)

                    #if DEBUG
                    // 👉 NEW: The Couch Test Debug Button
                    debugCouchTestButton
                        .padding(.top, 4)
                    #endif

                    startNewReportButton
                        .padding(.top, 4)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 20))

                recentReportsSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onAppear {
                viewModel.fetchReports()
                // 👉 NEW: Kick off the low-power gatekeeper when the app loads
                telemetry.startSmartMonitoring()
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        UserProfileView()
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Driver Profile")
                }
            }
            .fullScreenCover(isPresented: $isWizardShowing, onDismiss: {
                viewModel.fetchReports()
                resumeDraftID = nil
            }) {
                AccidentWizardView(resumeID: resumeDraftID)
            }
            .navigationDestination(item: $createdReportID) { id in
                IncidentReportView(reportID: id, photoCount: 0)
            }
            .alert("Impact Detected", isPresented: $showTelemetryAlert) {
                Button("Yes, attach") {
                    // Create the draft up front (this also auto-consumes the pending telemetry)
                    // and hand its ID into the Wizard so it resumes this exact draft.
                    AccidentStore.shared.createNewAccident()
                    resumeDraftID = AccidentStore.shared.currentAccidentID
                    isWizardShowing = true
                }
                Button("No, ignore", role: .cancel) {
                    AccidentStore.shared.discardPendingTelemetry()
                    isWizardShowing = true
                }
            } message: {
                if let pending = store.pendingTelemetry {
                    let timeString = pending.timestamp.formatted(date: .omitted, time: .shortened)
                    Text("We detected a sudden impact at \(timeString). Do you want to attach this telemetry data to your new report?")
                } else {
                    Text("Do you want to attach any pending telemetry to your new report?")
                }
            }
        }
    }
    
    #if DEBUG
    // 👉 NEW: The extracted Debug Button view
    private var debugCouchTestButton: some View {
        Button(action: {
            if telemetry.isDriving {
                telemetry.stopHighFidelityTracking()
            } else {
                telemetry.startHighFidelityTracking(isTest: true)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: telemetry.isDriving ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text(telemetry.isDriving ? "Stop Black Box" : "Force Start Couch Test")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(telemetry.isDriving ? Color.blue : Color.orange)
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    private var safetyTipBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(safetyRed.opacity(0.12))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(safetyRed)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Safety Tip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Stay calm. Check for injuries first.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }

    private var startNewReportButton: some View {
        Button {
            resumeDraftID = nil
            if AccidentStore.shared.pendingTelemetry != nil {
                showTelemetryAlert = true
            } else {
                isWizardShowing = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("Start New Report")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(safetyRed)
            )
            .shadow(color: safetyRed.opacity(0.22), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start New Report")
    }

    /// A `Section` (rather than a plain `VStack`) so the report rows participate in the
    /// enclosing `List`'s native, lazily-rendered row machinery — this keeps scrolling smooth
    /// as the report history grows, and is what unlocks `.swipeActions` for swipe-to-delete.
    private var recentReportsSection: some View {
        Section {
            if viewModel.reports.isEmpty {
                Text("No recent reports. You're driving safely!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            } else {
                ForEach(viewModel.reports) { report in
                    recentReportCard(report)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteReport(id: report.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Recent Reports")
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textCase(nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
    }

    private func recentReportCard(_ report: EvidenceGalleryViewModel.ReportDisplayData) -> some View {
        Group {
            if report.status == "draft" {
                // Drafts aren't full reports yet — tapping resumes the Wizard instead of
                // navigating to the (incomplete) Evidence Room.
                Button {
                    resumeDraftID = report.id
                    isWizardShowing = true
                } label: {
                    recentReportCardContent(report)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    IncidentReportView(reportID: report.id, photoCount: report.photoCount)
                } label: {
                    recentReportCardContent(report)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentReportCardContent(_ report: EvidenceGalleryViewModel.ReportDisplayData) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))

                Image(systemName: report.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(report.title) — Location Pending")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if report.status == "draft" {
                        draftBadge
                    }
                }

                HStack(spacing: 10) {
                    Text(report.dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(report.photoCount) Photos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
    }

    private var draftBadge: some View {
        Text("DRAFT")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
    }
}

#Preview {
    ContentView()
}
