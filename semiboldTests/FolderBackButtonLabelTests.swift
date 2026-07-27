import Testing

@testable import semibold

/// Verifies `FolderBackButtonLabel.resolve` matches
/// `Planning_6_FolderNavigationFlow` callout ①'s icon-only rule: a house
/// icon for the root case, a plain chevron for a nested folder — no
/// folder-name text, so an arbitrarily long name can't break the NavBar's
/// layout. The name is still tracked for `accessibilityLabel`.
///   - A root-level folder (`parentId == nil`) shows the house icon —
///     there's no parent folder to name.
///   - A nested folder shows the chevron icon, with its parent folder's
///     name only in `accessibilityLabel` (e.g. "뒤로가기, 일상").
///   - A nested folder whose parent lookup failed (e.g. the parent row
///     was deleted out from under it) falls back to `.root` rather than
///     showing a blank/garbled label.
struct FolderBackButtonLabelTests {
    @Test("A root-level folder shows the house icon")
    func rootFolderShowsHouseIcon() {
        let label = FolderBackButtonLabel.resolve(parentId: nil, parentName: nil)

        #expect(label == .root)
        #expect(label.iconName == "house.fill")
        #expect(label.accessibilityLabel == "뒤로가기, 홈")
    }

    @Test("A nested folder shows the chevron icon, naming its parent folder only for accessibility")
    func nestedFolderShowsChevronIconWithParentNameForAccessibility() {
        let label = FolderBackButtonLabel.resolve(parentId: "parent-id", parentName: "일상")

        #expect(label == .parentFolder(name: "일상"))
        #expect(label.iconName == "chevron.left")
        #expect(label.accessibilityLabel == "뒤로가기, 일상")
    }

    @Test("A nested folder whose parent lookup failed falls back to the root label")
    func nestedFolderWithFailedParentLookupFallsBackToRoot() {
        let label = FolderBackButtonLabel.resolve(parentId: "missing-parent-id", parentName: nil)

        #expect(label == .root)
        #expect(label.iconName == "house.fill")
    }
}
