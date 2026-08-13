import Foundation

/// The block types a user can jump to via the Slash Command bottom sheet
/// (`tasks/NO-001.md` §12.2 "Slash Command는 bottom sheet 가능", §13.1 "/:
/// Slash Command 열기"), in the order they're listed.
///
/// Plain paragraph isn't included — it's the default type every block
/// starts as, so there's nothing to "convert to."
enum SlashCommandOption: String, CaseIterable, Identifiable {
    case heading1
    case heading2
    case heading3
    case bulletedList
    case numberedList
    case checklist
    case blockquote
    case codeBlock
    case divider

    var id: String { rawValue }

    /// The label shown for this option in the bottom sheet.
    var title: String {
        switch self {
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletedList: return "Bulleted list"
        case .numberedList: return "Numbered list"
        case .checklist: return "Checklist"
        case .blockquote: return "Blockquote"
        case .codeBlock: return "Code block"
        case .divider: return "Divider"
        }
    }

    /// The SF Symbol shown before this option's label in the bottom sheet.
    var iconName: String {
        switch self {
        case .heading1: return "1.square"
        case .heading2: return "2.square"
        case .heading3: return "3.square"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .checklist: return "checklist"
        case .blockquote: return "quote.opening"
        case .codeBlock: return "curlybraces"
        case .divider: return "minus"
        }
    }
}

extension DetailViewModel {
    /// Detects whether `text` (the block's full text right after this
    /// keystroke) is exactly `"/"` — i.e. the user just typed a lone slash
    /// into an empty paragraph block, per §13.1's "/: Slash Command 열기".
    ///
    /// Returns `false` for `/` typed anywhere else (a non-empty block, or a
    /// block that isn't a paragraph) so this never fires mid-sentence — only
    /// a `/` as the very first character of an empty block opens the sheet,
    /// matching how `headingConversion`/`listConversion`/etc. only convert
    /// on a complete leading prefix.
    static func isSlashCommandTrigger(forTypedText text: String, currentTextKind: String) -> Bool {
        currentTextKind == TextItemKind.paragraph && text == "/"
    }

    /// Converts the block identified by `blockId` to `option`'s
    /// `TextContent.textKind`, clearing its text — the slash that
    /// triggered the sheet has already been consumed by `updateBlockText`,
    /// and the user types the block's real content fresh in its new type.
    ///
    /// Mirrors the structural conversions in
    /// `DetailViewModel+MarkdownConversion.swift`/`updateBlockText`: the
    /// block type changes immediately and is persisted right away rather
    /// than going through the debounce (PLANNING §11.2 "블록 생성/삭제/순서
    /// 변경: 즉시 저장"). Does nothing if `blockId` doesn't exist.
    func convertBlock(_ blockId: String, toSlashCommandOption option: SlashCommandOption) {
        guard items.contains(where: { $0.id == blockId }) else { return }

        switch option {
        case .heading1, .heading2, .heading3:
            textContents[blockId] = TextContent(
                itemId: blockId, textKind: TextItemKind.heading, plainText: "", headingLevel: option.headingLevel
            )
        case .bulletedList:
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.bulletedListItem, plainText: "")
        case .numberedList:
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.numberedListItem, plainText: "")
        case .checklist:
            textContents[blockId] = TextContent(
                itemId: blockId, textKind: TextItemKind.checklist, plainText: "", isChecked: false
            )
        case .blockquote:
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.quote, plainText: "")
        case .codeBlock:
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.codeBlock, plainText: "")
        case .divider:
            // `plainText` is the literal `"---"` (not empty) so tapping
            // the rendered rule to edit it (`DividerBlockView.body`'s
            // `ParagraphTextField`, `Views/Components/Block/DividerBlockView.swift`)
            // has real Markdown source text to show, matching Obsidian's "tap a
            // rule to reveal/edit its raw `---` line" behavior.
            // `blockIdToDefocus` drops keyboard focus right away so it
            // shows as the rendered rule immediately instead of staying
            // in text-edit mode.
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.divider, plainText: "---")
            blockIdToDefocus = blockId
        }

        cancelPendingSave(blockId)
        persistBlock(blockId)
        dismissSlashCommand()
    }
}

private extension SlashCommandOption {
    /// The heading level (1-3) for `.heading1`/`.heading2`/`.heading3`.
    /// Only meaningful for those three cases.
    var headingLevel: Int {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return 1
        }
    }
}
