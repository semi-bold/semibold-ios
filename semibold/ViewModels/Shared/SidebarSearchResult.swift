import Foundation

/// One row in the sidebar drawer's search results — either a matching
/// folder or a matching document.
///
/// Kept separate from the shared `Entry` enum (`Views/Shared/Entry.swift`)
/// because a search result also carries the document's parent folder
/// name, which `Entry` has no use for anywhere else it's used (rename/
/// delete flows). `tasks/NO-008.md` §3.2: "동명의 문서/폴더가 여러 위치에
/// 있을 수 있어, 검색 결과에는 문서 제목 아래 직전 폴더명을 작게 병기해
/// 구분할 수 있게 했다."
enum SidebarSearchResult: Identifiable {
    case folder(Folder)
    case document(Document, parentFolderName: String?)

    var id: String {
        switch self {
        case .folder(let folder):
            "folder-\(folder.id)"
        case .document(let document, _):
            "document-\(document.id)"
        }
    }
}
