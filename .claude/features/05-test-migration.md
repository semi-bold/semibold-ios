# Feature: 05-test-migration

## Source

- `tasks/NO-005.md` §8 Phase 6, §1.1 (테스트 재작성 + 마이그레이션 전용 테스트)
- 대상: `semiboldTests/` 전체 중 `DocumentBlock`/`BlockContent` 의존 테스트 —
  `BlockContentTests`, `BlockquoteConversionTests`, `ChecklistConversionTests`,
  `CodeBlockConversionTests`, `DetailViewModelTests`,
  `FolderDocumentPersistenceTests`, `HeadingConversionTests`,
  `InlineMarksConversionTests`, `InlineMarksTests`,
  `KeyboardShortcutConversionTests`, `ListConversionTests`,
  `MarkdownExporterTests`, `SlashCommandConversionTests`,
  `SwipeDeleteActionTests`, `Support/CoreDataTestStore.swift`

## Scope

- In scope:
  - 위 테스트 파일들을 01~04에서 만든 새 모델/Repository/ViewModel 기준으로 재작성
  - `Support/CoreDataTestStore.swift`가 새 model version으로 in-memory 스토어를
    만들도록 갱신
  - 01의 마이그레이션 정책(구 스키마 → 새 스키마)에 대한 전용 테스트 추가
    (새 파일, 예: `SchemaMigrationTests.swift`)
- Out of scope / deferred:
  - `RenameDocumentViewModelTests`, `RenameFolderViewModelTests`,
    `FolderBackButtonLabelTests`, `RootLaunchStateTests`,
    `ICloudAvailabilityTests`, `KeychainSessionStoreTests`,
    `DatabaseManagerContainerFactoryTests` — `DocumentBlock`/`BlockContent`에
    의존하지 않으므로 변경 불필요 (영향 있는 경우에만 최소 수정)

## Screens & Flows

해당 없음 — 테스트 전용.

## Decisions & Deviations

- 기존 테스트가 검증하던 "행동"(예: heading 변환 규칙, inline mark 파싱
  규칙, swipe delete 동작)은 그대로 유지하고, 대상 타입만 새 모델로
  교체한다 — 테스트 커버리지가 줄어들면 안 된다
- 마이그레이션 테스트는 01에서 이미 작성된 최소 1개를 확장해서, 서식이
  섞인 문서(bold+inline code 동시 적용 등) 케이스까지 커버한다

## Acceptance Criteria

- [ ] 위에 나열된 `DocumentBlock`/`BlockContent` 의존 테스트 파일이 모두
      새 모델(`DocumentItem`/`TextContent`/`TextMark`) 기준으로 재작성되어
      컴파일/통과한다
- [ ] `Support/CoreDataTestStore.swift`가 최신 model version을 사용한다
- [ ] 마이그레이션 전용 테스트가 다음을 검증한다:
      (a) 폴더/문서/여러 타입의 블록(서식 포함)을 가진 구 스키마 샘플을
      마이그레이션 후 데이터 개수·내용이 유실 없이 보존됨,
      (b) 알 수 없는/손상된 `contentJSON`을 만나도 마이그레이션이 앱을
      크래시시키지 않고 §7 예외 처리 정책대로 동작함
- [ ] `xcodebuild test` (또는 프로젝트의 기존 테스트 실행 방식)로 전체
      `semiboldTests` 타겟이 통과한다
- [ ] 마이그레이션 전/후 마크다운 export 결과를 비교하는 테스트가 최소
      1개 존재한다 (`tasks/NO-005.md` §4.2 "내용 손실 여부 확인")

## Open Questions / Follow-ups

- 없음
