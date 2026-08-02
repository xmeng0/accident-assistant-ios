//
//  InsuranceParser.swift
//  AccidentAssistant
//
//  Sprint 2: Parses raw OCR text from an insurance card into structured fields.
//  Uses a provider-specific regex architecture for high-accuracy policy extraction.
//

import Foundation

struct ParsedInsurance {
    var provider: String?
    var policyNumber: String?
    var driverName: String?
}

struct InsuranceParser {

    // MARK: - Provider Rule

    /// Encapsulates everything the parser needs to know about a single insurance carrier:
    /// which keywords identify it in raw OCR text, and the exact regex its policy numbers match.
    struct ProviderRule {
        let name: String
        let keywords: [String]
        let policyRegex: String
    }

    // MARK: - Provider Rule Table

    private static let providerRules: [ProviderRule] = [
        ProviderRule(
            name: "GEICO",
            keywords: ["GEICO"],
            policyRegex: #"\b[A-Z0-9]{9,10}\b"#
        ),
        ProviderRule(
            name: "State Farm",
            keywords: ["STATE FARM"],
            policyRegex: #"\b\d{7}-?[A-Z0-9]{2}-?\d{2}\b"#
        ),
        ProviderRule(
            name: "Progressive",
            keywords: ["PROGRESSIVE"],
            policyRegex: #"\b\d{8,9}\b"#
        ),
        ProviderRule(
            name: "Allstate",
            keywords: ["ALLSTATE"],
            policyRegex: #"\b\d{9,10}\b"#
        ),
        ProviderRule(
            name: "Farmers",
            keywords: ["FARMERS"],
            policyRegex: #"\b\d{9,10}\b"#
        ),
        ProviderRule(
            name: "USAA",
            keywords: ["USAA"],
            policyRegex: #"\b\d{7,10}\b"#
        ),
        ProviderRule(
            name: "Mercury",
            keywords: ["MERCURY"],
            policyRegex: #"\b[A-Z]{2,4}\d{8,10}\b"#
        ),
        ProviderRule(
            name: "AAA",
            keywords: ["AAA", "AUTO CLUB"],
            policyRegex: #"\b[A-Z0-9]{8,12}\b"#
        ),
    ]

    // MARK: - Generic fallback

    /// Matches 6–14 alphanumeric characters, explicitly excluding false-positive words
    /// like "REPORT" or "NUMBER" that OCR commonly picks up near the policy label.
    private static let genericPolicyBlocklist: Set<String> = ["REPORT", "NUMBER", "POLICY", "CLAIM", "CLAIMS"]
    private static let genericPolicyRegex = #"\b[A-Z0-9]{6,14}\b"#

    // MARK: - Parse

    static func parse(rawText: String) -> ParsedInsurance {
        var result = ParsedInsurance()

        let uppercased = rawText.uppercased()

        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // MARK: Provider — find the first rule whose keywords appear in the raw text.

        var matchedRule: ProviderRule? = nil
        for rule in providerRules {
            if rule.keywords.contains(where: { uppercased.contains($0) }) {
                matchedRule = rule
                result.provider = rule.name
                break
            }
        }

        // MARK: Policy Number — provider-specific regex, with generic fallback.

        if let rule = matchedRule {
            // Primary: use the carrier's exact policy format.
            result.policyNumber = firstRegexMatch(of: rule.policyRegex, in: uppercased)
        }

        if result.policyNumber == nil {
            // Fallback: generic alphanumeric sweep, blocking known false-positive words.
            if let candidate = firstRegexMatch(of: genericPolicyRegex, in: uppercased),
               !genericPolicyBlocklist.contains(candidate) {
                result.policyNumber = candidate
            }
        }

        // MARK: Driver name — look for "NAMED INSURED", "INSURED:", or "POLICYHOLDER"
        // and grab the very next non-empty line as the name.

        let nameKeywords = ["NAMED INSURED", "INSURED:", "INSURED", "POLICYHOLDER", "POLICY HOLDER"]
        for keyword in nameKeywords {
            if let lineIndex = lines.firstIndex(where: { $0.uppercased().contains(keyword) }),
               lineIndex + 1 < lines.count {
                let candidate = lines[lineIndex + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // A name contains spaces or mixed case — pure alphanumeric tokens are policy numbers.
                if candidate.range(of: #"^[A-Z0-9\-]+$"#, options: .regularExpression) == nil {
                    result.driverName = candidate
                    break
                }
            }
        }

        return result
    }

    // MARK: - Helpers

    /// Returns the first substring in `text` that matches `pattern`, trimmed of whitespace.
    /// Returns nil if the pattern is invalid or produces no match.
    private static func firstRegexMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else { return nil }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
