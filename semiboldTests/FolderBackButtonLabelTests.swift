import Testing

@testable import semibold

/// Verifies `FolderBackButtonLabel.resolve` matches
/// `Planning_6_FolderNavigationFlow` callout ①'s exact rule: "뒤로가기
/// 레이블('< Semi:bold')... 하위 폴더 진입 시 레이블은 상위 폴더명으로
/// 바뀐다."
///   - A root-level folder (`parentId == nil`) keeps the literal
///     "< Semi:bold" label — there's no parent folder to name.
///   - A nested folder shows its parent folder's name instead (e.g.
///     "< 일상").
///   - A nested folder whose parent lookup failed (e.g. the parent row
///     was deleted out from under it) falls back to `.root` rather than
///     showing a blank/garbled label.
struct FolderBackButtonLabelTests {
    @Test("A root-level folder keeps the literal Semi:bold back label")
    func rootFolderKeepsSemiboldLabel() {
        let label = FolderBackButtonLabel.resolve(parentId: nil, parentName: nil)

        #expect(label == .root)
        #expect(label.text == "< Semi:bold")
    }

    @Test("A nested folder shows its parent folder's name in the back label")
    func nestedFolderShowsParentName() {
        let label = FolderBackButtonLabel.resolve(parentId: "parent-id", parentName: "일상")

        #expect(label == .parentFolder(name: "일상"))
        #expect(label.text == "< 일상")
    }

    @Test("A nested folder whose parent lookup failed falls back to the root label")
    func nestedFolderWithFailedParentLookupFallsBackToRoot() {
        let label = FolderBackButtonLabel.resolve(parentId: "missing-parent-id", parentName: nil)

        #expect(label == .root)
        #expect(label.text == "< Semi:bold")
    }
}
