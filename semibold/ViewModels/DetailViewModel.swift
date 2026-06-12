import Foundation

/// Drives `DetailView` — the document editor screen.
///
/// Loads a document's blocks from the local database so the editor
/// always reflects what's actually been saved. Block editing itself
/// (paragraph input, Enter-to-create, delete/merge, reorder) is driven by
/// `Planning_4_BlockCreateFlow` and lands in a later acceptance criterion
/// — this view-model currently only loads what's needed to render the
/// document read-only.
@Observable
final class DetailViewModel {
    /// The document being viewed/edited.
    private(set) var document: Document

    /// The document's top-level blocks, in display order, excluding
    /// soft-deleted ones.
    private(set) var blocks: [DocumentBlock] = []

    private let documentBlockRepository: DocumentBlockRepository

    init(
        document: Document,
        documentBlockRepository: DocumentBlockRepository = DocumentBlockRepository()
    ) {
        self.document = document
        self.documentBlockRepository = documentBlockRepository
    }

    /// Reloads this document's top-level blocks.
    func load() {
        do {
            blocks = try documentBlockRepository.blocks(documentId: document.id, parentId: nil)
        } catch {
            // The editor simply shows an empty document if blocks can't be
            // read; the local database is expected to always be available,
            // so this would indicate a deeper setup problem rather than
            // something the user can act on here.
            blocks = []
        }
    }
}
