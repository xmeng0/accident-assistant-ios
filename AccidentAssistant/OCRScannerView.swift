//
//  OCRScannerView.swift
//  AccidentAssistant
//
//  Sprint 2: Vision OCR — document scanning UI.
//  Can be used standalone (Home → Scan Document) or as a sheet inside the Wizard.
//  When `onResult` is provided, the view parses the OCR text and calls back with
//  a `ParsedInsurance` value so the caller can auto-fill its text fields.
//

import SwiftUI
import UIKit

struct OCRScannerView: View {
    /// Optional callback. When set (e.g., from the Wizard), the view calls this after
    /// parsing the scanned text and then dismisses itself automatically.
    var onResult: ((ParsedInsurance) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var showSourceDialog = false
    @State private var useCamera = true
    @State private var selectedImage: UIImage?
    @State private var extractedText: String = ""
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Image picker
                    Button {
                        showSourceDialog = true
                    } label: {
                        Label("Scan or Choose Document", systemImage: "doc.viewfinder")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    // MARK: Selected image preview
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
                            )
                    }

                    // MARK: Extraction state
                    if isExtracting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Extracting text…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }

                    // MARK: Extracted text result (shown only in standalone mode)
                    if !extractedText.isEmpty && onResult == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Extracted Text")
                                .font(.title3.bold())
                                .foregroundStyle(.primary)

                            Text(extractedText)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("Document Scanner")
            .navigationBarTitleDisplayMode(.inline)
            // Show a Cancel button only when used as a sheet inside the Wizard.
            .toolbar {
                if onResult != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("Camera") { useCamera = true; showPicker = true }
                Button("Photo Library") { useCamera = false; showPicker = true }
            }
            .fullScreenCover(isPresented: $showPicker) {
                ImagePicker(image: $selectedImage, useCamera: useCamera)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedImage) { _, newImage in
                guard let newImage else { return }
                Task { await loadAndScan(image: newImage) }
            }
        }
    }

    // MARK: - Private

    private func loadAndScan(image: UIImage) async {
        errorMessage = nil
        extractedText = ""
        isExtracting = true

        do {
            let raw = try await OCRService.shared.extractText(from: image)
            extractedText = raw

            if let onResult {
                let parsed = InsuranceParser.parse(rawText: raw)
                onResult(parsed)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isExtracting = false
    }
}

#Preview {
    OCRScannerView()
}
