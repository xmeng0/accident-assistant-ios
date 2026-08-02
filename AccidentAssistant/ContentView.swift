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
    @StateObject private var viewModel = EvidenceGalleryViewModel()
    @StateObject private var telemetry = TelemetryManager.shared
    @ObservedObject private var store = AccidentStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                    recentReportsSection
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
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
            }) {
                AccidentWizardView()
            }
            .navigationDestination(item: $createdReportID) { id in
                IncidentReportView(reportID: id, photoCount: 0)
            }
            .alert("Impact Detected", isPresented: $showTelemetryAlert) {
                Button("Yes, attach") {
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

    private var recentReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Reports")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Button("See All") { }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(safetyRed)
                    .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                if viewModel.reports.isEmpty {
                    Text("No recent reports. You're driving safely!")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ForEach(viewModel.reports) { report in
                        recentReportCard(report)
                    }
                }
            }
        }
    }

    private func recentReportCard(_ report: EvidenceGalleryViewModel.ReportDisplayData) -> some View {
        NavigationLink {
            IncidentReportView(reportID: report.id, photoCount: report.photoCount)
        } label: {
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
                    Text("\(report.title) — Location Pending")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

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

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
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
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
