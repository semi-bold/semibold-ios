import Foundation

/// User-facing copy for the destructive-action confirmation alerts the
/// "삭제" swipe action shows before soft-deleting a folder or document
/// (`Planning_9_SwipeActionFlow` callout ③, PLANNING §6.1 "폴더 삭제
/// 정책").
///
/// Centralized here, alongside `AppErrorMessages`, so `HomeScreen` and
/// `FolderContentsScreen` show the exact same wording for the same
/// situation instead of drifting apart.
enum AppConfirmationMessages {
    /// Title shown on every delete-confirmation alert, regardless of
    /// what's being deleted.
    static let deleteTitle = "삭제하시겠습니까?"

    /// Body for deleting an empty folder or a document — a single
    /// action with nothing else affected.
    static let deleteSimple = "삭제된 항목은 목록에서 사라집니다."

    /// Body for deleting a folder that still has live nested folders or
    /// documents — makes clear that its contents go with it
    /// ("하위 폴더·문서가 있는 폴더 삭제 시 포함 여부를 묻는
    /// 다이얼로그", PLANNING §6.1/§19).
    static let deleteFolderWithContents =
        "이 폴더 안의 하위 폴더와 문서도 함께 목록에서 사라집니다. 계속하시겠습니까?"

    /// Label for the destructive confirm button.
    static let confirmButton = "삭제"

    /// Label for the cancel button.
    static let cancelButton = "취소"
}
