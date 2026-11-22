import Foundation

extension String {
    func decodingHTMLEntities() -> String {
        // Fast path: if no HTML entities, return as-is
        guard self.contains("&") else { return self }

        // Manual decoding for common entities to avoid NSAttributedString crashes
        var result = self
        let entities: [(String, String)] = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#039;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&#x27;", "'"),
            ("&#x2F;", "/")
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Try NSAttributedString as fallback, but catch any errors
        guard result.contains("&") else { return result }

        do {
            guard let data = result.data(using: .utf8) else { return result }

            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]

            let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            return attributedString.string
        } catch {
            // If NSAttributedString fails, return the manually decoded version
            return result
        }
    }

    func firstCapture(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .decodingHTMLEntities()
    }
}
