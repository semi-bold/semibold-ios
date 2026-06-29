import Foundation

/// Drives the "rename document" title-entry sheet opened from the "편집"
/// swipe action on a document row (`Planning_9_SwipeActionFlow`, NO-003
/// §3.2).
///
/// Mirrors `NewDocumentViewModel`'s title-entry shape, but loads an
/// existing document's current title instead of starting blank, and
/// saves over that document via `DocumentRepository.update` instead of
/// creating a new row.
@Observable
final class RenameDocumentViewModel {
    /// The title being edited, pre-filled with the document's current
    /// title. Like creating a document, leaving it blank is fine — it
    /// falls back to "Untitled" (PLANNING §6.2), so there's no inline
    /// validation error for this field.
    var title: String

    /// Set when saving the renamed title fails, so the sheet can show
    /// why and let the user retry without losing what they typed.
    private(set) var errorMessage: String?

    private let document: Document
    private let documentRepository: DocumentRepository

    init(
        document: Document,
        documentRepository: DocumentRepository = DocumentRepository()
    ) {
        self.document = document
        self.title = document.title
        self.documentRepository = documentRepository
    }

    /// Saves the edited title over the existing document, defaulting
    /// back to "Untitled" when left blank (mirrors
    /// `NewDocumentViewModel.createDocument()`).
    ///
    /// - Returns: the updated document on success, so the caller can
    ///   refresh its list. Returns `nil` on a persistence failure;
    ///   `errorMessage` is set so the sheet can show why and stay open
    ///   for the user to retry.
    @discardableResult
    func renameDocument() -> Document? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = document
        updated.title = trimmed.isEmpty ? "Untitled" : trimmed

        do {
            let saved = try documentRepository.update(updated)
            errorMessage = nil
            return saved
        } catch {
            // §15.2 "저장 실패" — saving the renamed document failed.
            errorMessage = AppErrorMessages.saveFailed
            return nil
        }
    }

    /// Clears any error once the user edits the title again, so the
    /// message doesn't linger after they've started retrying.
    func titleDidChange() {
        errorMessage = nil
    }
}
