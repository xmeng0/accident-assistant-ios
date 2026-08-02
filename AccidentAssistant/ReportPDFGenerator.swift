//
//  ReportPDFGenerator.swift
//  AccidentAssistant
//
//  Renders PDFTemplateView into a single-page PDF file using SwiftUI's ImageRenderer
//  and CoreGraphics' PDF context, then saves the result to the temporary directory.
//

import SwiftUI

@MainActor
struct ReportPDFGenerator {

    /// Generates a PDF for the specified incident and returns a file URL on success.
    /// Fetches all evidence from `AccidentStore` internally.
    static func generateAndSavePDF(
        reportID: UUID,
        aiReport: ParsedReconstruction
    ) -> URL? {
        let details     = AccidentStore.shared.loadDetails(for: reportID)
        let allPhotos   = AccidentStore.shared.getImages(for: reportID)
        let photos      = Array(allPhotos.prefix(4))
        let incidentDate = AccidentStore.shared
            .getAllSummaries()
            .first { $0.id == reportID }?.date

        let template = PDFTemplateView(
            incidentDate: incidentDate,
            details: details,
            aiReport: aiReport,
            photos: photos
        )

        let renderer = ImageRenderer(content: template)
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        // Scale 2× for crisp rasterised text inside the PDF bitmap.
        renderer.scale = 2.0

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FNOL_Report_\(reportID.uuidString).pdf")

        renderer.render { size, drawIntoContext in
            // The rendered size is at 2×; divide back to PDF points for the page box.
            let pointSize = CGSize(width: size.width / 2, height: size.height / 2)
            var mediaBox  = CGRect(origin: .zero, size: pointSize)

            guard let consumer = CGDataConsumer(url: tempURL as CFURL),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else {
                print("📄 ReportPDFGenerator: failed to create PDF context.")
                return
            }

            pdfContext.beginPDFPage(nil)
            // Scale the context down by 0.5 so the 2× render fits the 1× point page.
            pdfContext.scaleBy(x: 0.5, y: 0.5)
            drawIntoContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }

        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            print("📄 ReportPDFGenerator: PDF file not found after render.")
            return nil
        }

        print("📄 PDF saved to: \(tempURL.path)")
        return tempURL
    }
}
