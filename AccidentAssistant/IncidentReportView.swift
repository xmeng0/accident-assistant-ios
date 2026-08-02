//
//  IncidentReportView.swift
//  AccidentAssistant
//
//  Two-tab container for a saved incident.
//  Tab 1 "Summary" — paperwork view of all captured data.
//  Tab 2 "Evidence" — photo gallery with editable Other Driver card.
//

import SwiftUI

struct IncidentReportView: View {
    let reportID: UUID
    let photoCount: Int

    var body: some View {
        TabView {

            // MARK: Tab 1 — Summary
            IncidentSummaryTabView(reportID: reportID, photoCount: photoCount)
                .tabItem {
                    Label("Summary", systemImage: "doc.text")
                }

            // MARK: Tab 2 — Evidence
            IncidentEvidenceTabView(reportID: reportID, photoCount: photoCount)
                .tabItem {
                    Label("Evidence", systemImage: "photo.on.rectangle")
                }
        }
        .navigationTitle("Incident Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        IncidentReportView(reportID: UUID(), photoCount: 0)
    }
}
