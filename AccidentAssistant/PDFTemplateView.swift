//
//  PDFTemplateView.swift
//  AccidentAssistant
//
//  Print-ready FNOL reconstruction layout for PDF export.
//  Designed for a single US-Letter page (8.5 × 11 in / 612 × 792 pt at 72 DPI).
//  Rendered via ImageRenderer — no ScrollViews so the full layout captures cleanly.
//

import SwiftUI

struct PDFTemplateView: View {
    let incidentDate: Date?
    let details: AccidentReport?
    let aiReport: ParsedReconstruction
    /// Pre-capped at 4 by the caller.
    let photos: [UIImage]

    private let pageWidth: CGFloat = 612
    private let margin: CGFloat = 36
    private let accentColor = Color(red: 0.10, green: 0.10, blue: 0.10)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            headerBlock

            Divider()
                .background(Color.black)
                .padding(.horizontal, margin)

            // ── Section 1: Incident & Driver Details ────────────────────────
            sectionBand("1. INCIDENT & DRIVER DETAILS")
            metaSection.padding(.horizontal, margin)

            // ── Section 2: AI Summary & Timeline ────────────────────────────
            sectionBand("2. AI RECONSTRUCTION SUMMARY")
            summarySection.padding(.horizontal, margin)

            // ── Section 3: Damage & Environment ─────────────────────────────
            sectionBand("3. DAMAGE & ENVIRONMENTAL ASSESSMENT")
            damageSection.padding(.horizontal, margin)

            // ── Section 4: Evidence Gallery (if photos present) ─────────────
            if !photos.isEmpty {
                sectionBand("4. EVIDENCE GALLERY")
                photoGrid.padding(.horizontal, margin)
            }

            Spacer(minLength: 0)

            // ── Footer ───────────────────────────────────────────────────────
            footerBlock
        }
        .frame(width: pageWidth)
        .background(Color.white)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(spacing: 3) {
            Text("FIRST NOTICE OF LOSS RECONSTRUCTION")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Accident Assistant — Forensic AI Report")
                .font(.system(size: 8))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, margin)
        .padding(.vertical, 14)
    }

    // MARK: - Section band

    private func sectionBand(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, margin)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
    }

    // MARK: - Section 1: Meta

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = incidentDate {
                pdfRow("Date", value: date.formatted(date: .long, time: .shortened))
            }
            if let loc = details?.location, !loc.isEmpty {
                pdfRow("Location", value: loc.formattedAddress)
            }
            if let name = details?.otherDriverName {
                pdfRow("Other Driver", value: name)
            }
            if let license = details?.otherDriverLicenseNumber {
                pdfRow("License No.", value: license)
            }
            if let provider = details?.otherDriverProvider {
                pdfRow("Insurance", value: provider)
            }
            if let policy = details?.otherDriverPolicyNumber {
                pdfRow("Policy No.", value: policy)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Section 2: Summary + Timeline

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(aiReport.summary)
                .font(.system(size: 9))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ForEach(aiReport.timeline) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(event.time.uppercased())
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 88, alignment: .leading)
                    Text(event.description)
                        .font(.system(size: 9))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Section 3: Damage & Environment

    private var damageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            pdfRow("Visual Damage", value: aiReport.visualDamage)

            HStack(alignment: .top, spacing: 8) {
                envCell("Weather", aiReport.environmentalFactors.weather)
                envCell("Lighting", aiReport.environmentalFactors.lighting)
            }

            pdfRow("Road & Traffic", value: aiReport.environmentalFactors.roadAndTraffic)
            pdfRow("Liability Indicators", value: aiReport.liabilityIndicators)
        }
        .padding(.vertical, 8)
    }

    private func envCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 9))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section 4: Photo Grid

    private var photoGrid: some View {
        let cells = Array(photos.prefix(4))
        let cellWidth = (pageWidth - margin * 2 - 8) / 2

        return VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { col in
                        let index = row * 2 + col
                        if index < cells.count {
                            Image(uiImage: cells[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: cellWidth, height: 100)
                                .clipped()
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.gray.opacity(0.4), lineWidth: 0.5)
                                )
                        } else {
                            Color.clear
                                .frame(width: cellWidth, height: 100)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footerBlock: some View {
        VStack(spacing: 3) {
            Divider().background(Color.gray)
            Text(
                "Generated by Accident Assistant · " +
                Date().formatted(date: .abbreviated, time: .shortened) +
                " · For insurance claim purposes only. Not a legal document."
            )
            .font(.system(size: 7))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, margin)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    // MARK: - Row helper

    private func pdfRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 9))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
