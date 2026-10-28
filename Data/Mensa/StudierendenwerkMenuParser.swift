import Foundation

/// Reads the menu HTML of the Studierendenwerk Oldenburg (`func=make_spl` of its menu system).
///
/// The page lists a heading per serving counter (`.gruppenname`, e.g. „AUSGABE EINS“, „SUPPEN“)
/// followed by its meals (`.splMeal`). Each meal shows its name, the prices
/// „Studierende / Bedienstete / Gäste“ and icons such as „vegan“. A closed day is a single `.nodata` row.
enum StudierendenwerkMenuParser {
    /// Heading for meals listed before the first counter heading.
    static let defaultCategory = "Gerichte"

    static func isClosed(_ html: String) -> Bool {
        html.contains("class='row nodata'") || html.contains("class=\"row nodata\"")
    }

    static func meals(_ html: String) -> [Meal] {
        var meals: [Meal] = []
        var category = defaultCategory
        // Headings and meals in page order; each meal's HTML runs up to the next marker.
        let markers = matches(of: #"col-xs-4 gruppenname'>([^<]*)<|<div class='row splMeal'"#, in: html)
        for (index, marker) in markers.enumerated() {
            if let heading = marker.group(1) {
                category = categoryTitle(heading)
                continue
            }
            let end = index + 1 < markers.count ? markers[index + 1].range.lowerBound : html.endIndex
            let block = String(html[marker.range.lowerBound..<end])
            guard let name = mealName(in: block) else { continue }
            meals.append(Meal(
                id: meals.count,
                name: name,
                category: category,
                studentPrice: studentPrice(in: block),
                notes: notes(in: block)
            ))
        }
        return meals
    }

    // MARK: Parts of a meal

    /// The name in the wide layout, without the allergen codes that follow it.
    static func mealName(in block: String) -> String? {
        guard let raw = matches(of: #"<div class='col-md-5[^>]*>\s*<span[^>]*>(.*?)(?:<div|</span>)"#, in: block)
            .first?.group(1) else { return nil }
        let name = plainText(raw)
        return name.isEmpty ? nil : name
    }

    /// First amount of „2,50 / 4,40 / 4,60 €“; „max. 2,50*“ counts as 2,50.
    static func studentPrice(in block: String) -> Double? {
        guard let prices = matches(of: #"<div class='preise'><span>(.*?)</span>"#, in: block).first?.group(1),
              let amount = matches(of: #"(\d+),(\d{2})"#, in: prices).first,
              let euros = amount.group(1), let cents = amount.group(2) else { return nil }
        return Double("\(euros).\(cents)")
    }

    /// Icon titles such as „vegan“ or „mit Rindfleisch“, each once.
    static func notes(in block: String) -> [String] {
        var notes: [String] = []
        for match in matches(of: #"class='iconLarge' title='([^']*)'"#, in: block) {
            guard let title = match.group(1).map(plainText), !title.isEmpty, !notes.contains(title) else { continue }
            notes.append(title)
        }
        return notes
    }

    /// „AUSGABE EINS“ → „Ausgabe Eins“; an empty heading keeps the default.
    static func categoryTitle(_ heading: String) -> String {
        let text = plainText(heading)
        return text.isEmpty ? defaultCategory : text.lowercased().capitalized
    }

    // MARK: Helpers

    private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&euro;": "€", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Match {
        let range: Range<String.Index>
        let groups: [String?]

        func group(_ index: Int) -> String? { index <= groups.count ? groups[index - 1] : nil }
    }

    private static func matches(of pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (1..<max(result.numberOfRanges, 1)).map { index in
                Range(result.range(at: index), in: text).map { String(text[$0]) }
            }
            return Match(range: range, groups: groups)
        }
    }
}
