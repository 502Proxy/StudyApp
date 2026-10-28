import Foundation

/// Stud.IP delivers announcement and date descriptions as HTML.
enum StudIPHTML {
    /// Reduces HTML to readable text: line breaks for block elements, bullets for list items, no tags,
    /// common entities decoded.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: #"<\s*(br|/p|/div|/li|/h[1-6])\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: #"<\s*(ul|ol)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<\s*li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmed
    }
}
