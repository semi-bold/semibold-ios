import Foundation

/// Drives the "new document" title-entry sheet opened from `HomeView`'s
/// "+" menu (`Planning_3_DocumentCreateFlow`, PLANNING §5.3).
///
/// Walks through the flow's state diagram: the user is asked which folder
/// the document belongs to (the home screen has no "currently selected
/// folder" yet, so new documents land at the root), types an optional
/// title, and a `documents` row is saved — using "Untitled" when the title
/// is left blank, per PLANNING §6.2 ("제목이 없을 경우 Untitled 사용").
@Observable
final class NewDocumentViewModel {
    /// The title the user is typing for the new document. Unlike folder
    /// names, an empty title is valid — it falls back to "Untitled"
    /// (PLANNING §5.3 step G / §6.2), so there's no inline validation
    /// error for this field.
    var title: String = ""

    private let documentRepository: DocumentRepository

    /// The folder this document is created inside of. `nil` means the
    /// root of the Private space (PLANNING §5.3 step B: "현재 선택된 폴더
    /// 있음?" — `HomeView` has no folder-selection concept yet, so this
    /// always takes the "없음" branch and uses the root/default location).
    private let folderId: String?

    /// Set when saving the document fails, so the sheet can show why and
    /// let the user retry without losing what they typed.
    private(set) var errorMessage: String?

    init(
        folderId: String? = nil,
        documentRepository: DocumentRepository = DocumentRepository()
    ) {
        self.folderId = folderId
        self.documentRepository = documentRepository
    }

    /// Saves a new document, defaulting its title to "Untitled" when left
    /// blank (PLANNING §5.3: "documents row 생성").
    ///
    /// - Returns: the created document on success, so the caller can
    ///   refresh its list and select the new document. Returns `nil` on a
    ///   persistence failure; `errorMessage` is set so the sheet can show
    ///   why and stay open for the user to retry.
    @discardableResult
    func createDocument() -> Document? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = Document(
            folderId: folderId,
            title: trimmed.isEmpty ? "Untitled" : trimmed
        )

        do {
            let created = try documentRepository.create(document)
            errorMessage = nil
            return created
        } catch {
            errorMessage = "Couldn't save this document. Please try again."
            return nil
        }
    }

    /// Clears any error once the user edits the title again, so the
    /// message doesn't linger after they've started retrying.
    func titleDidChange() {
        errorMessage = nil
    }
}
