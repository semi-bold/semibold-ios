# Feature: 02-domain-models

## Source

- `tasks/NO-005.md` §3 (새 데이터 모델 개요), §4.2 (contentJSON 분해 규칙)
- `DOCUMENT_MODEL.md` §3 (핵심 엔터티), §4 (콘텐츠 타입)
- 참고(패턴): `semibold/Models/Folder.swift` (plain `Codable` struct 패턴 — 이 형태를 새 모델에도 유지)

## Scope

- In scope:
  - `Models/Document.swift`, `DocumentItem.swift`, `TextContent.swift`, `TextMark.swift`, `MediaContent.swift`, `Asset.swift` 신규 작성 (plain `Codable` struct, `Folder.swift`와 동일한 패턴)
  - 기존 `Models/DocumentBlock.swift`, `BlockContent.swift`, `BlockContent+InlineMarks.swift` 대체(삭제 또는 이번 브리프에서 미사용 표시 — 03에서 Repository가 새 모델을 쓰게 되면 완전히 삭제)
- Out of scope / deferred:
  - Core Data 엔터티 자체 (01에서 이미 완료된 것을 전제)
  - Repository/ViewModel 변경 (03, 04에서 진행)

## Screens & Flows

해당 없음 — 도메인 모델 전용, 화면 변경 없음.

## Decisions & Deviations

- 새 struct들은 `Folder.swift`와 동일하게 `Identifiable, Hashable, Codable`을
  채택하고, Core Data 타입을 노출하지 않는다 (CLAUDE.md §3 원칙)
- 필드명은 `tasks/NO-005.md` §3의 camelCase 매핑을 그대로 따른다
- `TextContent`는 `textKind`(`paragraph`/`heading`/`quote`/`checklist`/`caption`)를
  가지며, 기존 `BlockContent`의 case-분기 로직을 참고하되 정규화된 필드
  구조(`headingLevel`, `alignment`, `isChecked` 등 optional 필드)로 재작성한다
- `TextMark`는 `markType`(`bold`/`italic`/`underline`/`strike`/`inline_code`/
  `link`/`text_color`/`background_color`)과 `startOffset`/`endOffset`(UTF-16
  code unit, `tasks/NO-005.md` §2.3)을 갖는다

## Acceptance Criteria

- [ ] `Models/Document.swift`가 `id`, `folderId`, `title`, `schemaVersion`,
      `revision`, `createdAt`, `updatedAt`, `deletedAt`을 갖는 `Codable` struct로
      작성되어 있다
- [ ] `Models/DocumentItem.swift`가 `id`, `documentId`, `parentItemId`,
      `contentType`, `orderKey`, `revision`, `createdAt`, `updatedAt`,
      `deletedAt`을 갖는다
- [ ] `Models/TextContent.swift`가 `itemId`, `textKind`, `plainText`,
      `headingLevel`, `alignment`, `isChecked`, `customStyleId`를 갖는다
- [ ] `Models/TextMark.swift`가 `id`, `itemId`, `startOffset`, `endOffset`,
      `markType`, `valueMode`, `valueText`를 갖는다
- [ ] `Models/MediaContent.swift`가 `itemId`, `assetId`, `mediaType`, `altText`,
      `captionItemId`, `width`, `height`를 갖는다
- [ ] `Models/Asset.swift`가 `id`, `localPath`, `mimeType`, `fileName`,
      `fileSize`, `contentHash`, `createdAt`, `updatedAt`, `deletedAt`을 갖는다
- [ ] 새 모델 전체에 대해 기존 `Folder.swift`와 동일한 기본값 이니셜라이저
      패턴(예: `id: String = UUID().uuidString`)이 적용되어 있다
- [ ] 기존 `BlockContent`/`BlockContent+InlineMarks`가 더는 참조되지 않으면
      삭제되어 있다 (참조가 남아있다면 03/04 완료 후 정리해도 무방 — 이
      브리프에서는 새 모델 작성이 우선)

## Open Questions / Follow-ups

- `TextContent.textKind`의 정확한 case 목록(및 raw value 문자열)이
  `DocumentBlock`의 기존 block type과 1:1 대응되는지 01의 마이그레이션
  정책과 이름이 어긋나지 않는지 상호 검증 필요
