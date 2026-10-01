# Feature: 03-copy-action

## Source

- `tasks/NO-010.md` §2.1(선택 범위를 복사), §3.1(전체 선택 블록/경계
  블록 구분, 클립보드 이중 표현), §4(선택 UI 커스텀 디자인, 적용 범위
  확장)
- `tasks/NO-011.md` §2.1(텍스트 선택 메뉴를 `UIEditMenuInteraction`으로
  통일 — 메뉴 컨테이너 자체는 NO-011 소유, 2026-10-01 결정)
- `semiboldTests/CrossBlockSelection/README.md` — 시나리오 B1/B2,
  공통 불변조건 3/4/8/9
- Wireframes: Figma Screens `TextSelectionMenu`/`TextSelectionMenu_States`
  (네이티브 스타일 항목 + Bold/Italic 통합 메뉴, 2026-09-30 기준),
  Figma Flows `Planning_Select_1_BlockSelectionFlow`(③번 콜아웃),
  `Planning_Select_3_CopyPasteFlow`(①번 콜아웃)
- 의존: `01-cross-block-selection-core`(선택 범위/전체·경계 블록 구분
  결과), `02-clipboard-payload-model`(`BlockClipboardPayload`)

## Scope

- In scope:
  - **"복사" 액션의 데이터 처리 로직만 구현** — 01에서 계산된 전체
    선택 블록/경계 블록 구분에 따라 직렬화(전체 블록은 그대로, 경계
    블록은 선택된 텍스트만) → `BlockClipboardPayload` 인코딩 +
    `MarkdownExporter` 기반 Markdown 폴백을 같은 `UIPasteboard` 항목에
    함께 기록(불변조건 3/4/8). 이 함수는 `tasks/NO-011.md`가 구현하는
    `UIEditMenuInteraction` 메뉴의 "복사" `UIAction`에서 호출된다
  - 선택 범위 안에 리스트 블록의 일부만 포함된 경우(B2), 이 시점에는
    `listGroupId` 재배정이나 그룹 관계 처리를 하지 않는다 — 순수
    좌표/직렬화 상태만 다룬다(재배정은 04 붙여넣기 브리프 소관)
- Out of scope / deferred:
  - **선택 메뉴 UI 컨테이너 자체(`UIEditMenuInteraction` 부착, 메뉴
    노출 조건, 1/2페이지 구성)는 `tasks/NO-011.md` 소유다** — 더 이상
    NO-010이 만들지 않는다(2026-10-01 결정: 단일 블록/크로스 블록
    선택 모두 하나의 메뉴 컴포넌트를 쓰기로 하면서, 메뉴 컨테이너는
    이미 그 컴포넌트를 다루는 NO-011 쪽에 통합됐다). 이 브리프는
    "복사" 액션이 눌렸을 때 호출될 함수만 제공한다
  - 붙여넣기 로직(→ 04 브리프)
  - Bold/Italic 버튼의 실제 서식 토글 동작(`tasks/NO-011.md` 소유)
  - 외부 텍스트 붙여넣기(→ 05 브리프)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `TextSelectionMenu`/`TextSelectionMenu_States` (Figma Screens) | (참고용 — 실제 메뉴 컴포넌트는 `tasks/NO-011.md` 소유) | 1페이지: 복사/잘라내기/붙여넣기+더보기, 2페이지: 전체 선택+Bold/Italic |
| `Planning_Select_1_BlockSelectionFlow` ③ / `Planning_Select_3_CopyPasteFlow` ① (Figma Flows) | "복사" 액션의 데이터 처리 함수 | 복사 시 직렬화 규칙 콜아웃 |

## Decisions & Deviations

- 메뉴 컨테이너와 데이터 처리 로직을 분리했다 — 메뉴는 이제 단일
  블록/크로스 블록 어디서 열리든 같은 컴포넌트(`tasks/NO-011.md`
  소유)이고, 이 브리프는 그 컴포넌트가 "복사"를 호출할 때 실행될
  로직만 제공한다. (아래 Open Questions에서 Cut/Select All의 소유
  범위도 먼저 확인 필요.)

## Acceptance Criteria

- [ ] "복사" 액션 함수를 호출하면(메뉴 UI 없이 직접 호출하는 유닛
      테스트로 검증) 전체 선택 블록은 원본과 동일한 종류/스타일/
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

- **Cut/Select All 구현 범위 확인 필요** — 메뉴가
  `UIEditMenuInteraction`으로 통일되면서(2026-10-01) Copy/Cut/Paste/
  Select All 전부 iOS가 자동으로 채워주지 않고 직접 구현해야 하는
  항목이 됐다(더 이상 "네이티브라 공짜" 옵션이 없다). 그런데
  `tasks/NO-010.md` §2.1의 문서화된 스코프는 "복사"와 (별도 액션인)
  "붙여넣기"만 명시하고 "잘라내기"/"전체 선택"은 언급하지 않는다.
  Figma `TextSelectionMenu`는 이 네 항목을 모두 보여주므로, 착수 전:
  (a) Cut/Select All을 이번 NO-010 스코프에 포함해 실제로 구현할지,
  (b) 포함한다면 그 데이터 로직(Cut = 복사+블록 삭제, Select All =
  현재 문서 전체를 선택 범위로 설정)도 이 브리프가 구현할지, 사람에게
  확인이 필요하다.
