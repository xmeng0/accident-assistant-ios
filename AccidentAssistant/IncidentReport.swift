//
//  IncidentReport.swift
//  AccidentAssistant
//
//  Central view-model passed from the Wizard into the FNOL summary screen.
//  Designed to be extended in later sprints with AI scene summaries, media arrays,
//  vehicle details, and more — without breaking existing consumers.
//

import Foundation

/// Lightweight address value type shared by LocationManager and AccidentWizardView.
struct IncidentLocation: Codable, Equatable {
    var latitude: Double?
    var longitude: Double?
    var street: String = ""
    var city: String = ""
    var state: String = ""

    var formattedAddress: String {
        [street, city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var isEmpty: Bool { street.isEmpty && city.isEmpty && state.isEmpty }
}

struct IncidentReport {
    let id   = UUID()
    var date: Date

    // Driver & Insurance (MVP)
    var otherDriverName: String
    var licenseNumber: String
    var insuranceCompany: String
    var policyNumber: String
    var location: IncidentLocation?
    // Scene details (future-proofed for AI)
    var incidentDescription: String = ""
    // Driver's License scan details (Sprint: DL barcode parsing)
    var dateOfBirth: String = ""
    var issueDate: String = ""
    var expirationDate: String = ""
    // TODO: Add vehicle make/model, AI scene summaries, and media arrays in later sprints.
}
