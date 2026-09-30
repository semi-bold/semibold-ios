# Feature: 05-external-text-paste

## Source

- `tasks/NO-010.md` §2.2(제외 — 완벽한 상호운용은 아님), §4(외부 텍스트
  붙여넣기, 결정됨 2026-08-21)
- `semiboldTests/CrossBlockSelection/README.md` — 시나리오 C4/C5,
  공통 불변조건 8
- `semiboldTests/ListBlock/README.md` §A. 텍스트 타이핑, 시나리오
  A2("Prefix 문법으로 리스트 전환") 및 C2/E1(헤딩 프리픽스) — 이번
  브리프가 재사용할 프리픽스 판정 규칙의 원본
- 기존 구현: `semibold/ViewModels/Detail/DetailViewModel+
  MarkdownConversion.swift` — `headingConversion(forTypedText:)`/
  `listConversion(forTypedText:)`/`checklistConversion(forTypedText:)`/
  `blockquoteConversion(forTypedText:)`/`codeBlockConversion(forTypedText:)`/
  `isDividerTrigger(forTypedText:)` 등 프리픽스 판정 함수가 이미 존재
- 의존: `04-paste-same-different-document`(새 블록 삽입 시 id/orderKey
  발급 경로 재사용)

## Scope

- In scope:
  - 붙여넣을 클립보드 항목에 `com.semibold.blocks-payload`가 **없고**
    plain text만 있을 때(= 이 앱 밖에서 복사된 일반 텍스트)에만
    동작한다 — 이 앱 내부 복사본은 04 브리프가 처리(§3.1, 역파서
    불필요)
  - 줄바꿈(`\n`) 기준으로 최소한 문단 블록으로 나눠 받는다
  - 각 줄에 대해 기존 `DetailViewModel+MarkdownConversion.swift`의
    프리픽스 판정 함수(`headingConversion`/`listConversion`/
    `checklistConversion`/`blockquoteConversion`/`codeBlockConversion`/
    `isDividerTrigger`)를 그대로 호출해, 매칭되면 해당 종류의 블록으로
    변환하고 매칭 안 되면 일반 문단으로 둔다(C4)
  - 리스트 프리픽스가 매칭된 연속된 줄들은 `ListBlock/README.md` A2의
    그룹/depth 규칙(b~e)을 따라 같은 `listGroupId`로 묶인다 — 이미
    타이핑 시 쓰는 규칙을 붙여넣기의 각 줄에도 순서대로 적용하는
    수준이다
  - 이 앱에서 복사한 내용을 이 앱 밖(메모/메일 등)에 붙여넣을 때는
    `MarkdownExporter`가 생성한 Markdown 문자열이 그대로 쓰인다(C5,
    불변조건 8) — 기존 `MarkdownExporter` 존재 여부/동작을 확인만
    하고 재사용, 새로 만들지 않는다
- Out of scope / deferred:
  - 완전한 Markdown 문서 임포터(중첩 인용, 테이블, 각주 등) — 줄 단위
    프리픽스 매칭 이상의 문법 파싱은 스코프 밖(NO-010 §4에서 명시적
    제외)
  - 표현 못 하는 서식/블록의 근사 변환 품질 보장 — 손실 허용(불변조건
    8, §2.2)

## Screens & Flows

없음 — 화면 UI 변경 없이 기존 붙여넣기 동작 경로에 붙는 파싱 로직.

## Decisions & Deviations

- 프리픽스 판정은 `DetailViewModel+MarkdownConversion.swift`의 기존
  함수를 그대로 재사용한다 — 새 파서를 만들지 않는다. 이 함수들은
  이미 "타이핑 중 프리픽스 감지"용으로 순수하게 분리돼 있어(그룹/depth
  부기 로직과 결합돼 있지 않음), 붙여넣기 시 한 줄씩 순서대로 호출하는
  용도에 그대로 맞는다.

## Acceptance Criteria

- [ ] 클립보드에 `com.semibold.blocks-payload`가 없고 plain text만
      있을 때만 이 경로가 동작한다(내부 복사본은 04가 처리)
- [ ] 줄바꿈 기준으로 최소 문단 블록으로 나눠 받는다
- [ ] 각 줄이 `"- "`/`"# "`/`"1. "`/`"> "`/`` ``` `` 등 기존 프리픽스
      규칙에 매칭되면 해당 종류의 블록으로 변환된다(C4)
- [ ] 매칭되지 않는 줄은 일반 문단 블록이 된다
- [ ] 연속된 리스트 프리픽스 줄들은 `ListBlock/README.md` A2 규칙에
      따라 같은 `listGroupId`로 묶인다
- [ ] 이 앱에서 복사한 내용을 이 앱 밖에 붙여넣으면 Markdown 문자열이
      쓰인다(C5, 불변조건 8)

## Open Questions / Follow-ups

- 없음.
