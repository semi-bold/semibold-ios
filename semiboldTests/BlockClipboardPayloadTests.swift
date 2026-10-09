import Testing
import UIKit
import UniformTypeIdentifiers

@testable import semibold

/// Tests for `BlockClipboardPayload`'s `Codable` conformance, its
/// schema-extension resilience (`tasks/NO-010.md` §3.1), and its round
/// trip through `UIPasteboard` under the app's custom
/// `com.semibold.blocks-payload` UTType.
struct BlockClipboardPayloadTests {
    private func sampleItems() -> [DocumentItem] {
        [
            DocumentItem(id: "item-1", documentId: "doc-1", orderKey: "01"),
            DocumentItem(
                id: "item-2",
                documentId: "doc-1",
                depth: 1,
                listGroupId: "list-1",
                contentType: "text",
                orderKey: "02"
            )
        ]
    }

    private func sampleTextContents() -> [TextContent] {
        [
            TextContent(itemId: "item-1", textKind: "paragraph", plainText: "Hello"),
            TextContent(
                itemId: "item-2",
                textKind: "bulleted_list_item",
                plainText: "World",
                headingLevel: nil,
                alignment: "leading",
                isChecked: false,
                customStyleId: "style-1"
            )
        ]
    }

    private func sampleListGroups() -> [ListGroup] {
        [ListGroup(id: "list-1", documentId: "doc-1", listType: "bulleted_list_item")]
    }

    private func sampleTextMarks() -> [TextMark] {
        [
            TextMark(
                id: "mark-1",
                itemId: "item-1",
                startOffset: 0,
                endOffset: 5,
                markType: "bold"
            ),
            TextMark(
                id: "mark-2",
                itemId: "item-2",
                startOffset: 0,
                endOffset: 5,
                markType: "link",
                valueMode: "url",
                valueText: "https://example.com"
            )
        ]
    }

    private func samplePayload() -> BlockClipboardPayload {
        BlockClipboardPayload(
            items: sampleItems(),
            textContents: sampleTextContents(),
            listGroups: sampleListGroups(),
            textMarks: sampleTextMarks()
        )
    }

    // MARK: - AC1/AC2 — Codable conformance and basic round trip

    @Test("BlockClipboardPayload encodes and decodes back to an equal value")
    func codableRoundTrip() throws {
        let payload = samplePayload()

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(BlockClipboardPayload.self, from: data)

        #expect(decoded == payload)
        #expect(decoded.schemaVersion == BlockClipboardPayload.currentSchemaVersion)
    }

    // MARK: - AC2 — missing-key resilience

    @Test("Decoding succeeds with every array field defaulting to empty when its key is entirely absent")
    func decodeSucceedsWhenAllArrayKeysAreMissing() throws {
        let json = #"{"schemaVersion": 1}"#
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(BlockClipboardPayload.self, from: data)

        #expect(decoded.items.isEmpty)
        #expect(decoded.textContents.isEmpty)
        #expect(decoded.listGroups.isEmpty)
        #expect(decoded.textMarks.isEmpty)
    }

    @Test("Decoding succeeds when only some array keys are missing, leaving the others intact")
    func decodeSucceedsWhenSomeArrayKeysAreMissing() throws {
        // Simulates a clipboard payload written by an older app version
        // that doesn't yet know about `listGroups`/`textMarks`.
        let json = """
        {
            "schemaVersion": 1,
            "items": [
                {
                    "id": "item-1",
                    "documentId": "doc-1",
                    "depth": 0,
                    "contentType": "text",
                    "orderKey": "01",
                    "revision": 1,
                    "createdAt": 0,
                    "updatedAt": 0
                }
            ],
            "textContents": []
        }
        """
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(BlockClipboardPayload.self, from: data)

        #expect(decoded.items.count == 1)
        #expect(decoded.textContents.isEmpty)
        #expect(decoded.listGroups.isEmpty)
        #expect(decoded.textMarks.isEmpty)
    }

    // MARK: - AC4/AC5 — encode/decode helper functions

    @Test("encode/decode helpers restore every field of every model instance exactly")
    func encodeDecodeHelpersRoundTripExactly() throws {
        let items = sampleItems()
        let textContents = sampleTextContents()
        let listGroups = sampleListGroups()
        let textMarks = sampleTextMarks()

        let data = try BlockClipboardPayload.encode(
            items: items,
            textContents: textContents,
            listGroups: listGroups,
            textMarks: textMarks
        )
        let restored = try BlockClipboardPayload.decode(data)

        #expect(restored.items == items)
        #expect(restored.textContents == textContents)
        #expect(restored.listGroups == listGroups)
        #expect(restored.textMarks == textMarks)
    }

    // MARK: - AC3 — UIPasteboard round trip under the custom UTType

    @Test("Writing and reading the payload through UIPasteboard under com.semibold.blocks-payload round-trips")
    func pasteboardRoundTrip() throws {
        let payload = samplePayload()
        let data = try JSONEncoder().encode(payload)

        let pasteboard = UIPasteboard(name: .init("BlockClipboardPayloadTests"), create: true)!
        pasteboard.setData(data, forPasteboardType: BlockClipboardPayload.utType.identifier)

        let readBack = pasteboard.data(forPasteboardType: BlockClipboardPayload.utType.identifier)
        #expect(readBack != nil)

        let decoded = try JSONDecoder().decode(BlockClipboardPayload.self, from: readBack!)
        #expect(decoded == payload)

        UIPasteboard.remove(withName: .init("BlockClipboardPayloadTests"))
    }

    @Test("The com.semibold.blocks-payload UTType is registered and conforms to public.data")
    func utTypeIsRegistered() {
        let utType = UTType("com.semibold.blocks-payload")

        #expect(utType != nil)
        #expect(utType?.conforms(to: .data) == true)
    }
}
