import Foundation

/// User-facing copy for the error states defined in §15.2 ("에러 상태").
///
/// semi:bold's local database is expected to always be available — these
/// messages exist for the rare/defensive case where a read, write, or
/// delete against it fails anyway, so the user sees *something* went
/// wrong (and, for save/delete, can retry) instead of the app silently
/// dropping their change. Centralized here so every screen that surfaces
/// one of these three states uses the exact §15.2 wording.
enum AppErrorMessages {
    /// "DB 열기 실패" — shown by `DatabaseUnavailableView` when the local
    /// database can't be opened/migrated at launch.
    static let databaseUnavailable = "로컬 저장소를 열 수 없습니다."

    /// "저장 실패" — shown when a folder/document/block create or update
    /// fails to persist.
    static let saveFailed = "변경사항을 저장하지 못했습니다. 다시 시도해주세요."

    /// "삭제 실패" — shown when a folder/document/block delete fails to
    /// persist.
    static let deleteFailed = "항목을 삭제하지 못했습니다."

    /// Shown when the user taps a block's "잠금" swipe action
    /// (`Planning_9_SwipeActionFlow` callout ⑤) — Secret Lock's actual
    /// encryption is out of scope for now (PLANNING §1.2, §19), so tapping
    /// it only confirms the feature is coming rather than doing nothing
    /// silently.
    static let secretLockNotYetSupported = "잠금 기능은 아직 지원하지 않습니다."
}
