//
//  DLParser.swift
//  AccidentAssistant
//
//  Parses the AAMVA PDF417 barcode payload from the back of a US driver's license
//  into structured fields.
//

import Foundation

struct ParsedLicense {
    var firstName: String?
    var lastName: String?
    var licenseNumber: String?
    var dateOfBirth: String?
    var issueDate: String?
    var expirationDate: String?
}

struct DLParser {
    /// AAMVA 3-character element identifiers we care about.
    private static let designators = ["DAC", "DCS", "DAB", "DAQ", "DBB", "DBD", "DBA"]

    static func parse(payload: String) -> ParsedLicense {
        var result = ParsedLicense()

        // Real-world scans don't always agree on line endings (LF, CRLF, lone CR),
        // and some scanners strip line breaks entirely, compressing every element
        // onto a single line. Normalizing first means the scan below behaves the
        // same regardless of which format we were handed.
        let normalized = payload
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Locate every designator's position in the payload, then sort by where
        // they occur so we can bound each field's value below.
        var matches: [(range: Range<String.Index>, code: String)] = []
        for code in designators {
            var searchRange = normalized.startIndex..<normalized.endIndex
            while let found = normalized.range(of: code, range: searchRange) {
                matches.append((found, code))
                searchRange = found.upperBound..<normalized.endIndex
            }
        }

        guard !matches.isEmpty else { return result }
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        for (index, match) in matches.enumerated() {
            let valueStart = match.range.upperBound

            // A value ends at whichever boundary comes first: the next designator
            // we recognize, or the next line break. The line-break check is what
            // strips trailing jurisdiction-specific subfile codes (e.g. DDEN, DDFN)
            // that sit on their own line between two fields we care about but
            // aren't themselves in our designator list — without it, a field like
            // DCS would swallow an unrelated DDE line that happens to follow it.
            let nextDesignatorStart = index + 1 < matches.count ? matches[index + 1].range.lowerBound : normalized.endIndex
            let nextLineBreak = normalized[valueStart...].firstIndex(of: "\n") ?? normalized.endIndex
            let valueEnd = min(nextDesignatorStart, nextLineBreak)

            guard valueStart < valueEnd else { continue }
            let value = String(normalized[valueStart..<valueEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            switch match.code {
            case "DAC":
                result.firstName = value
            case "DCS", "DAB":
                result.lastName = value
            case "DAQ":
                result.licenseNumber = value
            case "DBB":
                result.dateOfBirth = formatAAMVADate(value)
            case "DBD":
                result.issueDate = formatAAMVADate(value)
            case "DBA":
                result.expirationDate = formatAAMVADate(value)
            default:
                break
            }
        }

        return result
    }

    /// Converts a raw AAMVA date string (MMDDYYYY, e.g. "02071983") into a
    /// standard US-readable format (MM/DD/YYYY, e.g. "02/07/1983"). Falls back
    /// to the raw value unchanged if it doesn't match the expected 8-digit shape,
    /// so an unusual jurisdiction's format is never silently corrupted.
    private static func formatAAMVADate(_ raw: String) -> String {
        guard raw.count == 8, raw.allSatisfy(\.isNumber) else { return raw }
        let month = raw.prefix(2)
        let day = raw.dropFirst(2).prefix(2)
        let year = raw.suffix(4)
        return "\(month)/\(day)/\(year)"
    }
}
