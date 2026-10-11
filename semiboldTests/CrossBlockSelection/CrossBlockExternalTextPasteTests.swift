import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Tests for the `05-external-text-paste` brief —
/// `DetailViewModel.pasteExternalText(at:pasteboard:)`, called directly
/// (no `UIEditMenuInteraction`/menu UI involved, same convention as every
/// other paste/copy test in this directory). Covers:
/// - AC1 — this path only runs when the pasteboard has no
///   `com.semibold.blocks-payload` entry (`CrossBlockSelection/README.md`
///   C4's own precondition).
/// - AC2 — a multi-line plain-text paste splits into one paragraph block
///   per line at minimum.
/// - AC3/AC4 — each line is matched against the existing Markdown-prefix
///   conversion rules; a match converts to that block kind with the
///   prefix stripped, a non-match stays a full-text paragraph.
/// - AC6/README C5/common invariant 8 — confirms (doesn't newly
///   implement; see this brief's own completion report) that copying
///   content inside this app and reading the pasteboard's plain-text
///   representation back out yields valid Markdown.
///
/// AC5 (list-prefix runs sharing one new `ListGroup`) is split out into
/// `CrossBlockExternalPasteGroupingTests.swift` — same
/// `file_length`-headroom precedent `CrossBlockPasteListReconciliationTests`
/// already set for the `04` brief's own test suite.
@MainActor
struct CrossBlockExternalTextPasteTests {
    private func makeStore() throws -> CoreDataTestStore {
        try CoreDataTestStore()
    }

    private func makeViewModel(document: Document, store: CoreDataTestStore) -> DetailViewModel {
        DetailViewModel(
            document: document,
            documentItemRepository: DocumentItemRepository(context: store.context),
            textItemRepository: TextItemRepository(context: store.context),
            textMarkRepository: TextMarkRepository(context: store.context),
            mediaItemRepository: MediaItemRepository(context: store.context),
            listGroupRepository: ListGroupRepository(context: store.context),
            folderRepository: FolderRepository(context: store.context)
        )
    }

    /// A throwaway, uniquely-named pasteboard per test — never
    /// `UIPasteboard.general`, same precedent as every other paste test.
    private func makeTestPasteboard(name: String) -> UIPasteboard {
        guard let pasteboard = UIPasteboard(name: .init(name), create: true) else {
            Issue.record("Could not create a throwaway test pasteboard")
            return .general
        }
        return pasteboard
    }

    @discardableResult
    private func createItem(
        documentId: String,
        orderKey: String,
        textKind: String,
        plainText: String,
        documentItemRepository: DocumentItemRepository,
        textItemRepository: TextItemRepository
    ) throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: documentId, contentType: "text", orderKey: orderKey)
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: textKind, plainText: plainText))
        return item
    }

    // MARK: - AC1 — only runs when no app-format payload is present

    @Test("Pasting external text no-ops when the pasteboard ALSO carries this app's own blocks-payload")
    func externalTextPasteNoOpsWhenAppFormatPayloadPresent() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let payload = BlockClipboardPayload(
            items: [DocumentItem(id: "src-1", documentId: document.id, contentType: "text", orderKey: "01")],
            textContents: [TextContent(itemId: "src-1", textKind: TextItemKind.paragraph, plainText: "Internal")],
            listGroups: [],
            textMarks: []
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalTextPasteTests.appFormatPresent")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalTextPasteTests.appFormatPresent")) }
        let data = try BlockClipboardPayload.encode(
            items: payload.items, textContents: payload.textContents,
            listGroups: payload.listGroups, textMarks: payload.textMarks
        )
        // Both representations on the same item, exactly like a real
        // `copySelectionToClipboard` write — the plain-text one alone
        // must NOT be enough to trigger this external-text path.
        pasteboard.items = [[
            BlockClipboardPayload.utType.identifier: data,
            UTType.plainText.identifier: Data("Internal".utf8)
        ]]

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.isEmpty)
        #expect(viewModel.items.map(\.id) == [anchor.id])
    }

    // MARK: - AC2 — multi-line plain text splits into one paragraph per line

    @Test("Pasting multi-line plain text with no Markdown prefixes creates one paragraph block per line")
    func multiLinePlainTextCreatesOneParagraphPerLine() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalTextPasteTests.multiLine")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalTextPasteTests.multiLine")) }
        pasteboard.string = "First line\nSecond line\nThird line"

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        #expect(pasted.allSatisfy { viewModel.textContent(forItemId: $0.id).textKind == TextItemKind.paragraph })
        let pastedTexts = pasted.map { viewModel.textContent(forItemId: $0.id).plainText }
        #expect(pastedTexts == ["First line", "Second line", "Third line"])
        #expect(viewModel.items.map(\.id) == [anchor.id] + pasted.map(\.id))

        // Persisted, not just in-memory.
        #expect(try textItemRepository.find(itemId: pasted[0].id)?.plainText == "First line")
        #expect(try documentItemRepository.find(id: pasted[2].id)?.documentId == document.id)
    }

    // MARK: - AC3/AC4 — prefix-matched lines convert, unmatched lines stay full-text paragraphs

    @Test("A mix of heading/list/blockquote/code-fence/plain lines each convert to the matching block kind")
    func mixedPrefixLinesConvertToMatchingKinds() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalTextPasteTests.mixedPrefixes")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalTextPasteTests.mixedPrefixes")) }
        pasteboard.string = [
            "# Title",
            "Just a plain sentence.",
            "> A quote",
            "```swift",
            "---"
        ].joined(separator: "\n")

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 5)
        let contents = pasted.map { viewModel.textContent(forItemId: $0.id) }

        #expect(contents[0].textKind == TextItemKind.heading)
        #expect(contents[0].plainText == "Title")
        #expect(contents[0].headingLevel == 1)

        #expect(contents[1].textKind == TextItemKind.paragraph)
        #expect(contents[1].plainText == "Just a plain sentence.")

        #expect(contents[2].textKind == TextItemKind.quote)
        #expect(contents[2].plainText == "A quote")

        #expect(contents[3].textKind == TextItemKind.codeBlock)
        #expect(contents[3].plainText == "")

        #expect(contents[4].textKind == TextItemKind.divider)
    }

    @Test("A bulleted-list-prefix line strips the prefix and a numbered-list-prefix line strips its own prefix")
    func listPrefixLinesStripPrefixAndConvert() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let anchor = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.paragraph,
            plainText: "Anchor", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalTextPasteTests.listPrefixes")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalTextPasteTests.listPrefixes")) }
        pasteboard.string = "- bullet item\n1. numbered item\n- [ ] a task"

        let pasted = try viewModel.pasteExternalText(
            at: DocumentTextLocation(blockId: anchor.id, offset: 6), pasteboard: pasteboard
        )

        #expect(pasted.count == 3)
        let contents = pasted.map { viewModel.textContent(forItemId: $0.id) }

        #expect(contents[0].textKind == TextItemKind.bulletedListItem)
        #expect(contents[0].plainText == "bullet item")

        #expect(contents[1].textKind == TextItemKind.numberedListItem)
        #expect(contents[1].plainText == "numbered item")

        #expect(contents[2].textKind == TextItemKind.checklist)
        #expect(contents[2].plainText == "a task")
        #expect(contents[2].isChecked == false)

        // Every pasted list item starts at depth 0 — external text has no
        // indentation syntax this brief parses to nest on.
        #expect(pasted.allSatisfy { $0.depth == 0 })
    }

    // MARK: - AC6/README C5/common invariant 8 — copy fallback is valid Markdown

    @Test("Copying blocks inside this app writes a Markdown string as the pasteboard's plain-text representation")
    func copyWritesMarkdownAsPlainTextRepresentation() throws {
        let store = try makeStore()
        let documentRepository = DocumentRepository(context: store.context)
        let documentItemRepository = DocumentItemRepository(context: store.context)
        let textItemRepository = TextItemRepository(context: store.context)

        let document = try documentRepository.create(Document(title: "Notes"))
        let itemA = try createItem(
            documentId: document.id, orderKey: OrderKey.between(nil, nil), textKind: TextItemKind.heading,
            plainText: "Title", documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )
        let itemB = try createItem(
            documentId: document.id, orderKey: OrderKey.between(itemA.orderKey, nil),
            textKind: TextItemKind.paragraph, plainText: "Body text",
            documentItemRepository: documentItemRepository, textItemRepository: textItemRepository
        )

        let viewModel = makeViewModel(document: document, store: store)
        viewModel.load()

        let range = CrossBlockSelectionRange(
            start: DocumentTextLocation(blockId: itemA.id, offset: 0),
            end: DocumentTextLocation(blockId: itemB.id, offset: 9)
        )
        let pasteboard = makeTestPasteboard(name: "CrossBlockExternalTextPasteTests.copyMarkdownFallback")
        defer { UIPasteboard.remove(withName: .init("CrossBlockExternalTextPasteTests.copyMarkdownFallback")) }

        try viewModel.copySelectionToClipboard(range: range, pasteboard: pasteboard)

        let plainTextData = try #require(pasteboard.data(forPasteboardType: UTType.plainText.identifier))
        let plainText = try #require(String(data: plainTextData, encoding: .utf8))

        // Lossily, but faithfully — both blocks' literal text appear as
        // valid Markdown lines (heading `#`, plain paragraph), not the
        // app's own JSON shape.
        #expect(plainText.contains("# Title"))
        #expect(plainText.contains("Body text"))
        #expect(!plainText.contains("schemaVersion"))
    }
}
