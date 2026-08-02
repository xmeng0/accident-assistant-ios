//
//  EvidenceGalleryViewModel.swift
//  AccidentAssistant
//
//  Sprint 2: Evidence Gallery — translate stored incidents into UI-ready rows.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class EvidenceGalleryViewModel: ObservableObject {
    struct ReportDisplayData: Identifiable {
        let id: UUID
        let title: String
        let dateText: String
        let photoCount: Int
        let icon: String
    }

    @Published var reports: [ReportDisplayData] = []

    func fetchReports() {
        let incidents = AccidentStore.shared.getAllSummaries()
        let incidentsByID = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0) })

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d"

        let mapped = incidents.map { incident in
            ReportDisplayData(
                id: incident.id,
                title: "Incident Report",
                dateText: formatter.string(from: incident.date),
                photoCount: incident.photoCount,
                icon: "folder.fill"
            )
        }

        // Sort newest first (by actual Date, not the formatted string).
        reports = mapped.sorted { lhs, rhs in
            let leftDate = incidentsByID[lhs.id]?.date ?? .distantPast
            let rightDate = incidentsByID[rhs.id]?.date ?? .distantPast
            return leftDate > rightDate
        }
    }
}

