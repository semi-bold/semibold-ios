import Foundation

/// A single point inside a document's text content — which block, plus the
/// character offset into that block's plain text. Matches
/// `CrossBlockSelection/README.md`'s "문서 좌표" (document coordinate)
/// term: "어느 블록의 몇 번째 문자 위치인지, '블록 + 그 블록 안에서의
/// 문자 오프셋' 쌍으로 나타냅니다."
///
/// Used to describe where a cross-block drag-selection starts/ends,
/// independent of which block instance happens to be on screen at a given
/// moment — `offset` is a UTF-16 count, matching `NSRange`/`UITextView`
/// conventions (`TextContent.plainText`'s own string isn't guaranteed to
/// be all-ASCII).
struct DocumentTextLocation: Hashable {
    let blockId: String
    let offset: Int
}
