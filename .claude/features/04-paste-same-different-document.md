# Feature: 04-paste-same-different-document

## Source

- `tasks/NO-010.md` §2.1(같은/다른 문서 붙여넣기), §3.2(재작성
  항목 — id/orderKey/listGroupId/depth)
- `semiboldTests/CrossBlockSelection/README.md` — 시나리오 C1/C2/C3,
  공통 불변조건 5/6/7
- `semiboldTests/ListBlock/README.md` — "공통 불변조건 6"(인접 블록
  depth 차이 최대 1), §3.2/§4에서 재참조
- Wireframes: Figma Flows `Planning_Select_3_CopyPasteFlow`(②③번
  콜아웃 — id 재발급, depth 보정)
- 의존: `02-clipboard-payload-model`(`BlockClipboardPayload` 디코딩)

## Scope

- In scope:
  - `com.semibold.blocks-payload` 클립보드 데이터를 우선 확인해서
    있으면 그대로 디코드(Markdown 역파싱 불필요 — NO-010 §3.1)
  - 같은 문서/다른 문서 어디에 붙여넣든 모든 블록에 새 `id`를
    발급한다(불변조건 5)
  - 새 `orderKey`를 생성한다
  - `depth`는 상대적 중첩 단계라 그대로 복사(리매핑 불필요,
    `tasks/NO-009.md` §3.1 근거)
  - `listGroupId` 재배정: 선택 범위에 리스트 블록이 포함되고 원본에서
    같은 `listGroupId`를 공유했다면, 붙여넣은 곳에서도 하나의 새
    `ListGroup` 행(새 id, 붙여넣기 대상 문서의 `documentId`, 같은
    `listType`)을 함께 가리키도록 재배정한다(불변조건 6)
  - 다른 문서에 붙여넣을 땐 `documentId`를 붙여넣기 대상 문서의 id로
    재작성한다
  - 선택 범위 첫 블록의 depth 보정: 조상 없이 depth > 0으로 시작하면
    첫 블록을 depth 0으로 클램프하고, 나머지 블록은 원래의 상대적
    깊이 차이를 유지한 채 함께 당겨서 보정한다(불변조건 7,
    `semiboldTests/ListBlock/README.md` 공통 불변조건 6과 연계)
- Out of scope / deferred:
  - 외부 텍스트(마크다운 아닌 일반 텍스트) 붙여넣기(→ 05 브리프)
  - 복사 시점의 직렬화 로직(→ 03 브리프, 이 브리프는 붙여넣기만 담당)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| `Planning_Select_3_CopyPasteFlow` ②③ (Figma Flows) | 붙여넣기 처리 로직 | 화면 UI보다는 데이터 재작성 로직 중심 |

## Decisions & Deviations

- **붙여넣기 위치 규칙 (구현 중 판단, 문서에 명시 안 돼 있던 부분)** —
  `location.blockId`를 기준점으로, `location.offset <= 0`이면 붙여넣는
  범위를 그 블록 바로 앞에, 그 외에는 바로 뒤에 삽입한다. 커서가 블록
  텍스트 중간이어도 그 블록 자체를 쪼개지는 않는다 — 여러 블록을
  붙여넣는 상황에서 앵커 블록의 텍스트를 커서 위치로 분할하는 것은
  이 브리프의 AC/시나리오(C1-C3) 어디에도 요구된 적이 없어, 실제
  "붙여넣기" 메뉴 액션을 연결할 때(`tasks/NO-011.md` 쪽) 커서 위치
  기반 분할 여부를 다시 결정하기로 하고 지금은 단순하게 처리했다.

## Acceptance Criteria

- [ ] 같은 문서에 붙여넣으면 `com.semibold.blocks-payload`를 그대로
      디코드해 적용한다(C1)
- [ ] 다른 문서에 붙여넣으면 C1과 동일하되 `documentId`를 대상
      문서로 재작성한다(C2)
- [ ] 붙여넣은 모든 블록은 새 `id`를 받는다(불변조건 5)
- [ ] 원본에서 같은 `listGroupId`를 공유하던 리스트 항목들은 붙여넣은
      뒤에도 하나의 새 `ListGroup`을 함께 가리킨다(불변조건 6)
- [ ] 붙여넣은 조각의 첫 블록이 조상 없이 depth > 0으로 시작하면
      depth 0으로 클램프하고, 나머지 블록은 상대적 깊이 차이를
      유지한다(C3, 불변조건 7)
- [ ] 붙여넣기 후 인접한 두 블록의 depth 차이가 항상 최대 1이라는
      리스트 블록 불변조건이 깨지지 않는다(`ListBlock/README.md`
      공통 불변조건 6)

## Open Questions / Follow-ups

- 없음.
