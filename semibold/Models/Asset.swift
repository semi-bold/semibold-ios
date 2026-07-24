import Foundation

/// A locally stored file backing one or more `MediaContent` items — an
/// image, video, audio clip, or other attachment
/// (`DOCUMENT_MODEL.md` §4.3 "실제 파일 데이터는 문서 모델 밖의 Asset
/// 저장소에서 관리한다").
struct Asset: Identifiable, Hashable, Codable {
    var id: String
    /// Where the file lives on disk, relative to the app's document
    /// storage root.
    var localPath: String
    var mimeType: String
    var fileName: String
    /// The file's size in bytes, if known.
    var fileSize: Int?
    /// A content hash (e.g. for de-duplicating identical files uploaded
    /// more than once), if computed.
    var contentHash: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        localPath: String,
        mimeType: String,
        fileName: String,
        fileSize: Int? = nil,
        contentHash: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.localPath = localPath
        self.mimeType = mimeType
        self.fileName = fileName
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
