# Feature: 04-viewmodel-view-migration

## Source

- `tasks/NO-005.md` §1.1 (포함 — "화면 동작·UX 자체는 기존과 동일하게 유지"), §8 Phase 5
- 대상 파일: `semibold/ViewModels/Home/HomeViewModel.swift`, `semibold/ViewModels/FolderContents/FolderContentsViewModel.swift`, `semibold/ViewModels/Detail/DetailViewModel.swift` (+ `DetailViewModel+KeyboardShortcuts.swift`, `+MarkdownConversion.swift`, `+SlashCommand.swift`), `semibold/ViewModels/FolderManagement/NewFolderViewModel.swift`, `RenameFolderViewModel.swift`, `semibold/ViewModels/DocumentManagement/NewDocumentViewModel.swift`, `RenameDocumentViewModel.swift`, `semibold/Models/MarkdownExporter.swift`, `MarkdownDocumentExport.swift`

## Scope

- In scope:
  - 위 ViewModel들의 `DocumentBlockRepository`/`DocumentBlock`/`BlockContent`
    참조를 03에서 만든 새 Repository/02에서 만든 새 모델로 교체
  - `MarkdownExporter`를 `TextItem`/`TextMark` 구조 기준으로 재작성
  - `DetailViewModel+MarkdownConversion.swift`, `+SlashCommand.swift`,
    `+KeyboardShortcuts.swift`의 블록 변환 로직을 새 모델 기준으로 재작성
- Out of scope / deferred:
  - View(SwiftUI) 파일 자체의 레이아웃/UX 변경 — `tasks/NO-005.md` §1.1이
    명시한 대로 화면에 보이는 동작은 기존과 동일해야 한다. View 파일은
    ViewModel의 새 타입 시그니처에 맞춰 컴파일되도록 하는 최소 변경만 허용
  - 새 콘텐츠 타입(Table 등) UI — 범위 밖

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Screen_Home | HomeView (ViewModel만 변경) | 화면 동작 동일 유지 |
| Screen_FolderContents | FolderContentsView (ViewModel만 변경) | 화면 동작 동일 유지 |
| Screen_Editor / iOS_Editor | DetailView (ViewModel만 변경) | 블록 편집·마크다운 변환 동작 동일 유지 |

## Decisions & Deviations

- 이 브리프는 "리팩터링"에 해당한다 — 사용자가 보는 동작이 바뀌면 안 되므로,
  변경 전/후 동일 시나리오(문서 생성 → 블록 추가 → 서식 적용 → 마크다운
  export)에 대해 결과가 같아야 한다
- `DetailViewModel`의 내부 상태 표현(현재 `[DocumentBlock]` 배열 등)이
  `[DocumentItem]`+연관 `TextItem`/`TextMark` 조합으로 바뀌므로, 편집기가
  메모리에서 조립하는 방식은 `STORAGE_ARCHITECTURE.md` §5.5(메모리 조립
  순서)를 따른다

## Acceptance Criteria

- [ ] `HomeViewModel`, `FolderContentsViewModel`이 새 `DocumentRepository`
      (blocks 제거된 버전)만 참조하고 컴파일된다
- [ ] `DetailViewModel`이 `DocumentItemRepository`/`TextItemRepository`/
      `TextMarkRepository`/`MediaItemRepository`를 사용해 문서를 로드/저장한다
- [ ] `DetailViewModel+MarkdownConversion.swift`의 heading/list/checklist/
      blockquote/code block 변환 로직이 새 `TextContent.textKind` 기준으로
      동작한다 (기존 `semiboldTests`의 관련 변환 테스트가 05에서 재작성될 때
      이 로직을 검증한다)
- [ ] `DetailViewModel+SlashCommand.swift`가 새 `textKind`로 블록 타입을
      전환한다
- [ ] `DetailViewModel+KeyboardShortcuts.swift`(macOS 단축키)가 새 모델
      기준으로 동작한다
- [ ] `MarkdownExporter`가 `TextItem`+`TextMark`로부터 마크다운을 생성하며,
      기존 `BlockContent` 기준 출력과 동일한 마크다운 결과를 낸다 (bold/
      italic/inline code/link 등 서식 보존 확인)
- [ ] `NewFolderViewModel`/`RenameFolderViewModel`/`NewDocumentViewModel`/
      `RenameDocumentViewModel`이 새 Repository 시그니처로 컴파일된다
      (이 4개는 콘텐츠 구조 변경의 영향을 거의 안 받으므로 변경량이 적을 것)
- [ ] 앱이 빌드되고, 시뮬레이터에서 폴더 생성 → 문서 생성 → 블록 추가/서식
      적용 → 앱 재시작 후 내용 유지까지 수동으로 확인된다 (verify 스킬 사용)

## Open Questions / Follow-ups

- `DetailViewModel`이 상당히 큰 파일(600줄+)이라 한 번에 다 바꾸기보다
  내부를 먼저 어댑터로 감싸고 점진 전환할지, 한 번에 재작성할지는
  feature-implementer 재량 — 단, 최종 상태는 `DocumentBlock`/`BlockContent`
  참조가 전혀 없어야 한다
