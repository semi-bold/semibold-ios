# Feature: 02-clipboard-payload-model

## Source

- `tasks/NO-010.md` §3.1 (클립보드 이중 표현 — 앱 자체 포맷 우선,
  스키마 확장 대비)
- 관련 모델: `semibold/Models/DocumentItem.swift`,
  `semibold/Models/TextContent.swift`, `semibold/Models/ListGroup.swift`,
  `semibold/Models/TextMark.swift` (모두 기존 `Codable`)
- Wireframes: 없음 — 순수 데이터 계층, 화면 없음

## Scope

- In scope:
  - `BlockClipboardPayload` (가칭) `Codable` 구조체 신설:
    `schemaVersion: Int`, `items: [DocumentItem]`,
    `textContents: [TextContent]`, `listGroups: [ListGroup]`,
    `textMarks: [TextMark]`
  - 커스텀 `init(from:)`으로 네 배열 필드 모두
    `decodeIfPresent(...) ?? []` 방식으로 디코드 — 향후 필드 추가 시
    옛 데이터 디코드 실패 방지(NO-010 §3.1 "스키마 확장 대비" 4가지
    규칙 중 배열 필드 규칙)
  - 커스텀 UTType 등록: `com.semibold.blocks-payload`
    (`Info.plist`/`project.yml`의 `UTExportedTypeDeclarations`,
    `bundleIdPrefix: com.semibold`와 일치하는 네이밍)
  - 선택된 블록 배열 → `BlockClipboardPayload` 인코딩 함수, 그
    역방향(디코딩) 함수
- Out of scope / deferred:
  - 실제 `UIPasteboard` 읽기/쓰기 로직(→ 03/04 브리프에서 이 구조체를
    사용)
  - 전체 선택 블록/경계 블록 구분 로직 자체(→ 03 브리프, 이 브리프는
    "이미 구분된 배열을 받아서 인코드/디코드"만 담당)
  - `DocumentItem`/`TextContent`/`ListGroup`/`TextMark` 구조체 자체의
    필드 추가 — 이번 스코프는 없음, 있다면 항상 옵셔널로 추가한다는
    원칙만 문서화(NO-010 §3.1)

## Screens & Flows

없음 — 데이터 계층 전용 브리프.

## Decisions & Deviations

- UTType 식별자는 `com.semibold.blocks-payload`로 정한다 —
  `project.yml`의 `bundleIdPrefix: com.semibold`를 그대로 따른 역DNS
  네이밍이다. 다른 이름을 쓸 특별한 이유가 없다면 이 값을 그대로
  채택한다.
- `contentType`/`textKind`/`listType`은 손대지 않는다 — 이미 plain
  `String`이라 모르는 값을 만나도 디코드 전체가 실패하지 않는다(NO-010
  §3.1). enum으로 바꾸지 않는다.
- `schemaVersion`은 지금 스코프에선 항상 `1`로 인코드하되, 디코드
  시점에 사용은 안 해도 된다(호환 불가능한 구조 변경이 실제로
  생기기 전까지는 값을 읽고 분기할 필요가 없다) — 다만 필드 자체는
  반드시 있어야 미래에 의미가 생긴다.

## Acceptance Criteria

- [ ] `BlockClipboardPayload` 구조체가 정의돼 있고 `Codable`을
      만족한다
- [ ] 커스텀 `init(from:)`이 `items`/`textContents`/`listGroups`/
      `textMarks` 중 하나 이상의 키가 JSON에 없어도 디코드에 성공하고
      해당 필드는 빈 배열이 된다 (유닛 테스트로 검증)
- [ ] `com.semibold.blocks-payload` UTType이 등록돼 있고, 이 타입으로
      데이터를 `UIPasteboard`에 쓰고 읽는 왕복 테스트가 성공한다
- [ ] `[DocumentItem]`/`[TextContent]`/`[ListGroup]`/`[TextMark]`
      배열을 받아 `BlockClipboardPayload`로 인코딩하는 함수가 있다
- [ ] `BlockClipboardPayload`를 디코딩해서 원래 배열 4종을 그대로
      복원하는 함수가 있다 (인코드 → 디코드 왕복 시 모든 필드 값이
      정확히 일치하는지 유닛 테스트로 검증)

## Open Questions / Follow-ups

- 없음 — 데이터 계층이라 디자인/UX 판단이 필요한 지점이 없다.
