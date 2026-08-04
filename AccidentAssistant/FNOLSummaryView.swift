//
//  FNOLSummaryView.swift
//  AccidentAssistant
//
//  First Notice of Loss summary screen. Displays all captured incident data, lets
//  the user add a free-text description, and saves the completed report to the store.
//

import SwiftUI

struct FNOLSummaryView: View {
    // Mutable so the description TextField can write back through $report.
    @State var report: IncidentReport

    /// The draft accident the Wizard already created (and saved photos into directly) as soon
    /// as the user captured their first photo. If nil (the user skipped the Photos step
    /// entirely), a new accident is created here instead.
    var existingAccidentID: UUID? = nil

    /// Called after a successful save — typically the wizard's dismiss action,
    /// which pops the fullScreenCover and returns the user to the Home Screen.
    var onSaved: (() -> Void)? = nil

    private let safetyRed = Color(red: 0.86, green: 0.10, blue: 0.15)

    var body: some View {
        Form {

            // MARK: Incident Details
            // MARK: Incident Details
                        Section("Incident Details") {
                            HStack {
                                Text("Date")
                                Spacer()
                                Text(report.date.formatted(date: .long, time: .omitted))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            // Add the Location row right below the Date
                            if let location = report.location {
                                HStack(alignment: .top) {
                                    Text("Location")
                                    Spacer()
                                    Text(location.formattedAddress)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }

                            TextField(
                                "Describe what happened...",
                                text: $report.incidentDescription,
                                axis: .vertical
                            )
                            .lineLimit(4...10)
                        }

            // MARK: Other Driver
            Section("Other Driver") {
                summaryRow(label: "Name",             value: report.otherDriverName)
                summaryRow(label: "License Number",   value: report.licenseNumber)
                summaryRow(label: "Date of Birth",    value: report.dateOfBirth)
                summaryRow(label: "Issue Date",       value: report.issueDate)
                summaryRow(label: "Expiration Date",  value: report.expirationDate)
            }

            // MARK: Insurance
            Section("Insurance") {
                summaryRow(label: "Company",       value: report.insuranceCompany)
                summaryRow(label: "Policy Number", value: report.policyNumber)
            }

            // MARK: Save — primary action
            Section {
                Button {
                    saveAndReturn()
                } label: {
                    Label("Save Report to Home", systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                }
                .listRowBackground(safetyRed)
            }
        }
        .navigationTitle("Incident Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func saveAndReturn() {
        let id: UUID
        if let existingAccidentID {
            // Photos were already saved directly to this accident as they were captured.
            id = existingAccidentID
        } else {
            // The user skipped the Photos step entirely — nothing exists on disk yet.
            AccidentStore.shared.createNewAccident(date: report.date)
            guard let newID = AccidentStore.shared.currentAccidentID else {
                print("💾 FNOLSummaryView: no active accident ID after creation.")
                onSaved?()
                return
            }
            id = newID
        }

        AccidentStore.shared.updateIncidentDetails(
            for: id,
            provider:            report.insuranceCompany,
            policyNumber:        report.policyNumber,
            driverName:          report.otherDriverName,
            licenseNumber:       report.licenseNumber,
            dateOfBirth:         report.dateOfBirth,
            issueDate:           report.issueDate,
            expirationDate:      report.expirationDate,
            incidentDescription: report.incidentDescription,
            location:            report.location
        )
        onSaved?()
    }

    // MARK: - Helpers

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        FNOLSummaryView(report: IncidentReport(
            date:             Date(),
            otherDriverName:  "Jane Smith",
            licenseNumber:    "D1234567",
            insuranceCompany: "GEICO",
            policyNumber:     "A12B34567"
        ))
    }
}
