# Feature: 03-copy-action

## Source

- `tasks/NO-010.md` §2.1(선택 범위를 복사), §3.1(전체 선택 블록/경계
  블록 구분, 클립보드 이중 표현), §4(선택 UI 커스텀 디자인)
- `semiboldTests/CrossBlockSelection/README.md` — 시나리오 B1/B2,
  공통 불변조건 3/4/8
- Wireframes: Figma Screens `TextSelectionMenu`/`TextSelectionMenu_States`
  (네이티브 항목 + Bold/Italic 통합 메뉴, 2026-09-30 기준),
  Figma Flows `Planning_Select_1_BlockSelectionFlow`(③번 콜아웃),
  `Planning_Select_3_CopyPasteFlow`(①번 콜아웃)
- 의존: `01-cross-block-selection-core`(선택 범위/전체·경계 블록 구분
  결과), `02-clipboard-payload-model`(`BlockClipboardPayload`)

## Scope

- In scope:
  - 선택 완료 시 뜨는 액션 메뉴 UI 컨테이너 구현(`Planning_Select_2`/
    `Planning_Select_3`의 `TextSelectionMenu` 자리)
  - "복사" 액션: 01에서 계산된 전체 선택 블록/경계 블록 구분에 따라
    직렬화(전체 블록은 그대로, 경계 블록은 선택된 텍스트만) →
    `BlockClipboardPayload` 인코딩 + `MarkdownExporter` 기반 Markdown
    폴백을 같은 `UIPasteboard` 항목에 함께 기록(불변조건 3/4/8)
  - 선택 범위 안에 리스트 블록의 일부만 포함된 경우(B2), 이 시점에는
    `listGroupId` 재배정이나 그룹 관계 처리를 하지 않는다 — 순수
    좌표/직렬화 상태만 다룬다(재배정은 04 붙여넣기 브리프 소관)
- Out of scope / deferred:
  - 붙여넣기 로직(→ 04 브리프)
  - Bold/Italic 버튼의 실제 서식 토글 동작 — 메뉴에 버튼이 보이더라도
    그 동작 자체는 `tasks/NO-011.md` 소유(NO-010 §4 마지막 항목).
    이 브리프는 메뉴 컨테이너와 Copy 버튼만 구현한다.
  - 외부 텍스트 붙여넣기(→ 05 브리프)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `TextSelectionMenu`/`TextSelectionMenu_States` (Figma Screens) | 선택 완료 후 뜨는 액션 메뉴 뷰 | 1페이지: 복사/잘라내기/붙여넣기+더보기, 2페이지: 전체 선택+Bold/Italic |
| `Planning_Select_1_BlockSelectionFlow` ③ / `Planning_Select_3_CopyPasteFlow` ① (Figma Flows) | 위와 동일 | 복사 시 직렬화 규칙 콜아웃 |

## Decisions & Deviations

- (없음 — 아래 Open Questions에서 먼저 확인 필요)

## Acceptance Criteria

- [ ] 선택을 완료하면 액션 메뉴가 뜬다
- [ ] "복사"를 탭하면 전체 선택 블록은 원본과 동일한 종류/스타일/
      텍스트 전부를 담아 직렬화한다(불변조건 3)
- [ ] 경계 블록은 선택된 문자 구간의 텍스트만 담되 원본의 종류/스타일
      (헤딩 레벨, 리스트 종류 등)은 유지한다(불변조건 4)
- [ ] 직렬화 결과가 `BlockClipboardPayload`로 인코딩되어
      `com.semibold.blocks-payload` 타입으로 클립보드에 기록된다
- [ ] 같은 클립보드 항목에 `MarkdownExporter` 기반 Markdown 문자열도
      plain-text 표현으로 함께 기록된다(불변조건 8, 이 앱 밖 붙여넣기
      대비)
- [ ] 선택 범위에 리스트 블록의 일부만 포함돼도 이 시점에는
      `listGroupId` 재배정을 하지 않는다(B2)

## Open Questions / Follow-ups

- **Figma 디자인과 NO-010.md 문서 스코프 사이 불일치 확인 필요** —
  Figma의 `TextSelectionMenu`는 복사/잘라내기/붙여넣기/전체 선택/
  Bold/Italic을 모두 보여주는 통합 메뉴로 만들어졌지만(2026-09-30
  기준, 단일 블록 선택과 크로스 블록 선택 메뉴를 동일하게 보이도록
  통일한 결정), `tasks/NO-010.md` §2.1의 문서화된 스코프는 "복사"와
  (별도 액션인) "붙여넣기"만 명시하고 "잘라내기"/"전체 선택"은
  언급하지 않는다. 이 브리프를 시작하기 전에: 크로스 블록 선택
  메뉴에서 잘라내기/전체 선택도 실제로 동작해야 하는지, 아니면
  시각적으로만 존재하고 이번 스코프에선 비활성화 상태로 둘지 사람에게
  확인이 필요하다.
