//
//  GeminiService.swift
//  AccidentAssistant
//
//  Created by Sean Meng on 5/10/26.
//

import Foundation
import UIKit

// MARK: - Model

public enum GeminiModel: String, Sendable {
    case efficient = "gemini-2.5-flash"
    case frontier  = "gemini-3.0-pro"

    var requestTimeout: TimeInterval {
        switch self {
        case .efficient: return 90
        case .frontier:  return 180
        }
    }
}

// MARK: - Protocol

@MainActor public protocol GeminiServiceProtocol {
    func generateAccidentReport(
        telemetryJSON: String,
        location: String?,
        driverDescription: String?,
        images: [UIImage],
        videos: [URL],
        crashDate: Date?,
        model: GeminiModel
    ) async throws -> String
}

// MARK: - Errors

public enum GeminiError: LocalizedError, Sendable {
    case configurationMissing
    case invalidURL
    case imageProcessingFailed(index: Int)
    case videoProcessingFailed(index: Int)
    case networkError(underlying: Error)
    case rateLimitExceeded
    case serverUnavailable
    case unexpectedStatusCode(Int)
    case malformedResponse
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "GEMINI_API_KEY is missing from Info.plist. Check your Secrets.xcconfig."
        case .invalidURL:
            return "Could not construct a valid Gemini API endpoint URL."
        case .imageProcessingFailed(let index):
            return "Failed to process image at index \(index) for upload."
        case .videoProcessingFailed(let index):
            return "Failed to read video file at index \(index). Ensure the file exists and is readable."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "Gemini API rate limit exceeded (HTTP 429). Please wait before retrying."
        case .serverUnavailable:
            return "Gemini API is temporarily unavailable (HTTP 503). Please try again shortly."
        case .unexpectedStatusCode(let code):
            return "Received unexpected HTTP status code \(code) from Gemini API."
        case .malformedResponse:
            return "Could not decode the response returned by the Gemini API."
        case .emptyResponse:
            return "The Gemini API returned a response with no generated content."
        }
    }
}

// MARK: - Private Codable Models (v1beta schema)

private struct GeminiRequest: Encodable, Sendable {
    let contents: [GeminiContent]
}

private struct GeminiContent: Encodable, Sendable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable, Sendable {
    let text: String?
    let inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(mimeType: String, base64Data: String) {
        self.text = nil
        self.inlineData = GeminiInlineData(mimeType: mimeType, data: base64Data)
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }
}

private struct GeminiInlineData: Encodable, Sendable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiResponse: Decodable, Sendable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable, Sendable {
    let content: GeminiContent?

    private struct ContentDecoding: Decodable, Sendable {
        let parts: [PartDecoding]
        struct PartDecoding: Decodable, Sendable {
            let text: String?
        }
    }

    // Use a raw-decodable wrapper so GeminiContent (Encodable only) is not misused here.
    var extractedText: String? { _rawContent?.parts.compactMap(\.text).joined(separator: "\n") }

    private let _rawContent: ContentDecoding?

    enum CodingKeys: String, CodingKey { case content }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _rawContent = try container.decodeIfPresent(ContentDecoding.self, forKey: .content)
        content = nil
    }
}

// MARK: - Service

@MainActor public final class GeminiService: GeminiServiceProtocol {

    public static let shared = GeminiService()

    private let session: URLSession
    private let maxRetries = 3
    private let systemPrompt = """
        You are an expert auto insurance adjuster AI. Your task is to generate a highly factual First Notice of Loss (FNOL) reconstruction.

        DATA INPUTS (MULTIMODAL FLEXIBILITY):
        You will receive ANY combination of the following data:
        - On-device iPhone telemetry (speed, G-force vectors)
        - Dashcam video footage (pre-impact and during impact)
        - Smartphone video (recorded post-impact at the scene)
        - Scene photos (taken post-impact)
        - Driver's written/spoken description

        STRICT CONSTRAINTS & BUSINESS LOGIC:
        1. ANTI-HALLUCINATION: State ONLY objective facts. If a detail (like speed, weather, traffic conditions, or specific damage) is not explicitly proven by the provided data or clearly visible in the media, you MUST use the string "Unknown". Do NOT extrapolate, guess, or assume.
        2. OBJECTIVE RECOUNT: Synthesize and corroborate whatever combination of data is provided. Do NOT assign legal fault or liability.
        3. TIMELINE CORRELATION: Correlate telemetry physics with visual video/photo evidence. Group continuous telemetry events. Map the provided Local Crash Time to T-00s.

        OUTPUT ARCHITECTURE:
        You MUST return ONLY a valid JSON object. Do NOT output any conversational text, Markdown formatting, or XML. Do NOT wrap the output in code blocks or backticks. The output must be raw, parseable JSON that matches this exact schema:

        {
          "summary": "2-3 sentence clinical, objective summary of the event based on the available data combination.",
          "timeline": [
            { "time": "Pre-Impact", "description": "Description of vehicle behavior, speed, and road conditions before the collision. Group continuous telemetry here." },
            { "time": "Point of Impact", "description": "Exact description of the collision, identifying the striking and struck vehicles, corroborating telemetry spikes with video/photos if available." },
            { "time": "Post-Impact", "description": "Resting positions, post-impact video analysis, and immediate aftermath." }
          ],
          "visualDamage": "Analyze available media (photos/videos) for Primary Point of Impact (POI), damage severity (e.g., superficial, structural crush), and corroborate with telemetry physics.",
          "environmentalFactors": {
            "weather": "Extracted from video/photos (e.g., Clear, Raining) or state Unknown",
            "lighting": "Extracted from video/photos (e.g., Daylight, Night) or state Unknown",
            "roadAndTraffic": "Note surface conditions and visible traffic controls. CRITICAL: Restrict observations ONLY to factors directly affecting the subject vehicle's path of travel or the incident itself. Strictly ignore ambient traffic, parked cars, or vehicles in opposite lanes unless they are actively involved in the sequence of events."
          },
          "liabilityIndicators": "Note any lane departures, right-of-way violations, or traffic signals visible in the footage."
        }
        """

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    public func generateAccidentReport(
        telemetryJSON: String,
        location: String? = nil,
        driverDescription: String? = nil,
        images: [UIImage],
        videos: [URL] = [],
        crashDate: Date? = nil,
        model: GeminiModel = .frontier
    ) async throws -> String {
        // DATA GATE: Prevent entirely empty payloads from draining AI tokens
        let cleanedJSON = telemetryJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTelemetry = !cleanedJSON.isEmpty && cleanedJSON != "{}" && cleanedJSON != "[]"
        let hasImages = !images.isEmpty
        let hasVideos = !videos.isEmpty

        guard hasTelemetry || hasImages || hasVideos else {
            return "Insufficient data. Please provide at least one form of evidence (telemetry, photos, or video) to generate a reconstruction."
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
        let crashDateString = crashDate.map { dateFormatter.string(from: $0) } ?? "Unknown"

        let apiKey = try resolvedAPIKey()
        let url    = try endpoint(for: model, apiKey: apiKey)

        let base64Images = try await processImages(images)
        let processedVideos = try await processVideos(videos)

        var parts: [GeminiPart] = [
            GeminiPart(text: systemPrompt),
            GeminiPart(text: "Local Crash Time: \(crashDateString)"),
            GeminiPart(text: "Location: \(location ?? "Unknown")"),
            GeminiPart(text: "Driver Description: \(driverDescription ?? "Not provided")"),
            GeminiPart(text: "Telemetry Data (T-15s to T-00s):\n\(telemetryJSON)")
        ]
        let imageParts = base64Images.map { GeminiPart(mimeType: "image/jpeg", base64Data: $0) }
        parts.append(contentsOf: imageParts)
        let videoParts = processedVideos.map { GeminiPart(mimeType: $0.mimeType, base64Data: $0.base64) }
        parts.append(contentsOf: videoParts)

        let body = GeminiRequest(contents: [GeminiContent(parts: parts)])
        let encoded = try JSONEncoder().encode(body)

        if let jsonString = String(data: encoded, encoding: .utf8) {
            print("\n====== 🚀 OUTGOING PAYLOAD TO GOOGLE ======")
            print(jsonString)
            print("===========================================\n")
        }

        // Give video-bearing requests a generous timeout on top of the model's baseline.
        let effectiveTimeout = videos.isEmpty ? model.requestTimeout : model.requestTimeout + 120

        let responseData = try await performRequest(with: encoded, url: url, timeout: effectiveTimeout)

        if let responseString = String(data: responseData, encoding: .utf8) {
            print("\n====== 📥 INCOMING PAYLOAD FROM GOOGLE ======")
            print(responseString)
            print("===========================================\n")
        }

        return try parseResponse(responseData)
    }

    // MARK: - Convenience wrapper for test / quick-call sites

    /// Thin wrapper that maps the simplified test-call signature onto `generateAccidentReport`.
    public func generateReconstruction(
        images: [UIImage],
        videoURLs: [URL] = [],
        telemetry: String,
        model: GeminiModel = .frontier
    ) async throws -> String {
        try await generateAccidentReport(
            telemetryJSON: telemetry,
            images: images,
            videos: videoURLs,
            model: model
        )
    }

    /// Sends a single image with a plain-text instruction and returns the raw text response.
    /// Used for lightweight, single-shot tasks (e.g. generating a short auto-name label)
    /// rather than the full multimodal accident-report pipeline.
    public func generateLabel(
        for image: UIImage,
        prompt: String,
        model: GeminiModel = .efficient
    ) async throws -> String {
        let apiKey = try resolvedAPIKey()
        let url = try endpoint(for: model, apiKey: apiKey)

        guard let base64 = try await processImages([image]).first else {
            throw GeminiError.imageProcessingFailed(index: 0)
        }

        let parts: [GeminiPart] = [
            GeminiPart(text: prompt),
            GeminiPart(mimeType: "image/jpeg", base64Data: base64)
        ]
        let body = GeminiRequest(contents: [GeminiContent(parts: parts)])
        let encoded = try JSONEncoder().encode(body)

        let responseData = try await performRequest(with: encoded, url: url, timeout: model.requestTimeout)
        return try parseResponse(responseData)
    }

    // MARK: - Key Resolution

    private func resolvedAPIKey() throws -> String {
        guard let key = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String,
              !key.isEmpty else {
            throw GeminiError.configurationMissing
        }
        return key
    }

    // MARK: - Endpoint Construction

    private func endpoint(for model: GeminiModel, apiKey: String) throws -> URL {
        let raw = "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent?key=\(apiKey)"
        guard let url = URL(string: raw) else { throw GeminiError.invalidURL }
        return url
    }

    // MARK: - Image Pipeline

    /// Scales images to a max dimension of 1600 px and JPEG-encodes at 0.7 quality.
    /// Wrapped in an autoreleasepool per iteration to prevent memory pressure.
    func processImages(_ images: [UIImage]) async throws -> [String] {
        var results: [String] = []
        results.reserveCapacity(images.count)

        for (index, image) in images.enumerated() {
            let base64: String = try autoreleasepool {
                let scaled = image.scaledToMaxDimension(1600)
                guard let jpegData = scaled.jpegData(compressionQuality: 0.7) else {
                    throw GeminiError.imageProcessingFailed(index: index)
                }
                return jpegData.base64EncodedString()
            }
            results.append(base64)
        }
        return results
    }

    // MARK: - Video Pipeline

    /// Reads each video file from disk and base64-encodes it for inline multimodal delivery.
    func processVideos(_ urls: [URL]) async throws -> [(mimeType: String, base64: String)] {
        var results: [(mimeType: String, base64: String)] = []
        results.reserveCapacity(urls.count)

        for (index, url) in urls.enumerated() {
            guard let data = try? Data(contentsOf: url) else {
                throw GeminiError.videoProcessingFailed(index: index)
            }
            results.append((mimeType: videoMIMEType(for: url), base64: data.base64EncodedString()))
        }
        return results
    }

    private func videoMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov":        return "video/quicktime"
        default:           return "video/mp4"
        }
    }

    // MARK: - Network Layer with Exponential Backoff

    private func performRequest(
        with requestData: Data,
        url: URL,
        timeout: TimeInterval
    ) async throws -> Data {
        var lastError: Error = GeminiError.serverUnavailable
        let baseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

        for attempt in 0 ..< maxRetries {
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestData

            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw GeminiError.unexpectedStatusCode(-1)
                }

                switch http.statusCode {
                case 200 ..< 300:
                    return data

                case 429:
                    lastError = GeminiError.rateLimitExceeded
                    try await Task.sleep(nanoseconds: baseDelay << attempt)

                case 503:
                    lastError = GeminiError.serverUnavailable
                    try await Task.sleep(nanoseconds: baseDelay << attempt)

                default:
                    throw GeminiError.unexpectedStatusCode(http.statusCode)
                }

            } catch let geminiErr as GeminiError {
                // Re-throw non-retryable Gemini errors immediately
                switch geminiErr {
                case .rateLimitExceeded, .serverUnavailable:
                    lastError = geminiErr
                default:
                    throw geminiErr
                }
            } catch {
                throw GeminiError.networkError(underlying: error)
            }
        }

        throw lastError
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> String {
        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiError.malformedResponse
        }

        guard let candidates = decoded.candidates, !candidates.isEmpty else {
            throw GeminiError.emptyResponse
        }

        let text = candidates.compactMap(\.extractedText).joined(separator: "\n\n")
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }
}

// MARK: - Parsed Reconstruction Models

/// Top-level decoded model for the AI's JSON response.
public struct ParsedReconstruction: Codable {
    public let summary: String
    public let timeline: [TimelineEvent]
    public let visualDamage: String
    public let environmentalFactors: EnvironmentalFactors
    public let liabilityIndicators: String
}

/// A single entry in the chronological timeline array.
public struct TimelineEvent: Codable, Identifiable {
    public var id: UUID { UUID() }
    public let time: String
    public let description: String

    enum CodingKeys: String, CodingKey {
        case time, description
    }
}

/// Nested environmental-conditions block inside `ParsedReconstruction`.
public struct EnvironmentalFactors: Codable {
    public let weather: String
    public let lighting: String
    public let roadAndTraffic: String
}

// MARK: - UIImage Scaling Helper

private extension UIImage {
    func scaledToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        let size = self.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
