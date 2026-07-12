import Foundation

/// The umbrella term for a `Folder` or a `Document` — anything that shows
/// up as a single row in a folder/document list and shares the same
/// "편집"/"삭제" swipe actions (`Planning_9_SwipeActionFlow`).
///
/// `Entry = Folder ∪ Document` (see `PLANNING.md` §2.2). `DocumentBlock`
/// is not part of this — it's scoped to content inside a `Document`.
enum Entry: Identifiable, Hashable {
    case folder(Folder)
    case document(Document)

    var id: String {
        switch self {
        case .folder(let folder):
            folder.id
        case .document(let document):
            document.id
        }
    }
}
