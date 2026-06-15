import Foundation
import CoreTransferable

/// A `Transferable` wrapper around one document's blocks, for `ShareLink`'s
/// "파일 저장 또는 공유" (§10.3) export button in `DetailView`.
///
/// Holding just the document's title and its already-loaded blocks (cheap —
/// `DetailViewModel.blocks` is already in memory) defers the actual
/// `MarkdownExporter.render` + temporary-file write to `exporting(...)`'s
/// closure, which `ShareLink` only calls once the user taps the share button
/// and the system asks for the file. This keeps `DetailView.body` — which
/// SwiftUI re-evaluates on every `@Observable` edit to `viewModel` — free of
/// any rendering or disk I/O.
struct MarkdownDocumentExport: Transferable {
    let documentTitle: String
    let blocks: [DocumentBlock]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .text) { export in
            let markdown = MarkdownExporter.render(documentTitle: export.documentTitle, blocks: export.blocks)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.fileName(forDocumentTitle: export.documentTitle))
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return SentTransferredFile(fileURL)
        }
        .suggestedFileName { export in
            Self.fileName(forDocumentTitle: export.documentTitle)
        }
    }

    /// The suggested `<title>.md` file name for `export`'s document.
    ///
    /// The document's title (PLANNING §6.2's free-text `documents.title`)
    /// may contain characters that aren't valid in a file name, or be blank
    /// — sanitized to a single safe `.md` file name so "Save to Files" never
    /// produces an invalid or untitled file.
    static func fileName(forDocumentTitle documentTitle: String) -> String {
        var sanitizedTitle = documentTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedTitle.isEmpty {
            sanitizedTitle = "Untitled"
        }
        return "\(sanitizedTitle).md"
    }
}
