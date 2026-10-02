import UIKit

/// Tracks every currently-mounted block's live `UITextView` by block id, so
/// the cross-block selection overlay (`CrossBlockSelectionOverlay`) can
/// translate a raw touch point — delivered to its own gesture recognizer,
/// not to any particular block's text view — into a `DocumentTextLocation`
/// (`tasks/NO-010.md` §4's `closestPosition(to:)`-based approach;
/// `CrossBlockSelectionHitTester` is what actually does that translation
/// once it has a candidate text view from here).
///
/// One shared instance for the whole app, the same pattern
/// `AccessoryToolbarCoordinator.shared` already uses for a similar
/// problem (one piece of UIKit state that needs to be reachable from
/// anywhere in the block list, independent of any single block's own
/// view) — see that type's doc comment.
///
/// **Only knows about currently-mounted blocks.** `DetailScreen`'s block
/// list is a `LazyVStack` inside a `ScrollView` — rows scrolled off screen
/// are torn down (`ParagraphTextField.dismantleUIView` unregisters them)
/// and have no live `UITextView` to look up at all. That's fine for this
/// brief's A2/A3 scope (a drag that's still visible on screen), but it's a
/// hard constraint whoever implements A5 (auto-scroll while dragging off
/// the viewport edge) needs to know: resolving a touch point into a
/// location inside a block that isn't mounted yet isn't possible through
/// this registry alone. A5 will need the scroll to actually happen
/// (mounting the next row) before a location inside it can be resolved —
/// this registry doesn't (and can't, without more information than a
/// block id gives it) synthesize geometry for an unmounted row.
///
/// Not marked `@MainActor` (unlike `CrossBlockSelectionTracker`) — matches
/// `AccessoryToolbarCoordinator`'s existing convention of a plain class
/// whose callers (all `UIViewRepresentable`/`UIKit` callback contexts, all
/// already on the main thread in practice) are trusted to stay on it,
/// rather than introducing actor-isolation friction at `ParagraphTextField
/// .dismantleUIView`'s static context.
final class BlockTextViewRegistry {
    static let shared = BlockTextViewRegistry()

    private init() {}

    private var textViewsByBlockId: [String: WeakTextViewBox] = [:]

    func register(blockId: String, textView: UITextView) {
        textViewsByBlockId[blockId] = WeakTextViewBox(textView)
    }

    func unregister(blockId: String) {
        textViewsByBlockId.removeValue(forKey: blockId)
    }

    /// The live text view for `blockId`, or `nil` if it's not currently
    /// mounted (scrolled off screen, or never registered — e.g. a stale
    /// id left over from a deleted block).
    func textView(for blockId: String) -> UITextView? {
        textViewsByBlockId[blockId]?.textView
    }
}

/// A non-retaining box so `BlockTextViewRegistry` never keeps a
/// `UITextView` alive past the `ParagraphTextField` row that owns it —
/// SwiftUI/`LazyVStack` manage that lifetime, not this registry.
private final class WeakTextViewBox {
    weak var textView: UITextView?
    init(_ textView: UITextView) { self.textView = textView }
}
