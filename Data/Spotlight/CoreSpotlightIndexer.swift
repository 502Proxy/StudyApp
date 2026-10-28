import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Writes StudyApp's items into a dedicated Core Spotlight index. Replacing everything keeps the
/// index free of deleted notes without tracking changes; the data set is small.
struct CoreSpotlightIndexer: SearchIndexing {
    static let indexName = "StudyApp"
    static let domainIdentifier = "studyapp"

    private let index = CSSearchableIndex(name: Self.indexName)

    func replaceAll(with items: [SearchableItem]) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        guard !items.isEmpty else { return }
        try await index.indexSearchableItems(items.map(Self.searchableItem))
    }

    private static func searchableItem(_ item: SearchableItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.title
        attributes.contentDescription = item.subtitle
        attributes.textContent = item.content
        attributes.contentModificationDate = item.modifiedAt
        return CSSearchableItem(
            uniqueIdentifier: item.target.identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
