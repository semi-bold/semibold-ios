# Feature: 01-core-data-model

## Source

- `tasks/NO-005.md` §3 (새 데이터 모델 개요), §4.1 (Core Data 마이그레이션), §5 (마이그레이션 플로우), §6 (상태 정의), §7 (예외 처리)
- `STORAGE_ARCHITECTURE.md` §3 (권장 테이블), §9 (마이그레이션 원칙)
- 참고(변경 대상 아님): `semibold/Data/SemiboldModel.xcdatamodeld/SemiboldModel.xcdatamodel/contents` (현재 Folder/Document/DocumentBlock 정의)

## Scope

- In scope:
  - `SemiboldModel.xcdatamodeld`에 새 model version 추가, 새 엔터티(Document/DocumentItem/TextItem/TextMark/Asset/MediaItem) 정의
  - `Folder` 엔터티는 기존 정의 그대로 유지 (변경 없음)
  - 기존 `DocumentBlock.contentJSON` → `TextItem`/`TextMark`로 분해하는 Custom `NSEntityMigrationPolicy` 작성
  - 마이그레이션 전 백업(구 버전 스토어 보존) 로직
- Out of scope / deferred:
  - Repository/도메인 모델/ViewModel 변경 (02~04에서 진행)
  - 실사용자 실기기 데이터로의 리허설 (06에서 진행 — 이 브리프는 Core Data 모델과 마이그레이션 정책만 다룸)
  - Sync Provider, `sync_changes` 큐 (NO-006)

## Screens & Flows

해당 없음 — 데이터 레이어 전용, 화면 변경 없음.

## Decisions & Deviations

- 새 엔터티는 `tasks/NO-005.md` §3의 필드 정의를 그대로 따른다 (`id`, `documentId`,
  `parentItemId`, `contentType`, `orderKey`, `revision`, `createdAt`, `updatedAt`,
  `deletedAt` 등 — CLAUDE.md §3 원칙대로 `tasks/<work-code>.md` 스키마 명명을
  그대로 사용, 파생 네이밍 금지)
- `TextItem`/`MediaItem`은 `DocumentItem`과 1:1 관계로 모델링한다 (Core Data
  서브엔터티 상속이 아니라 STORAGE_ARCHITECTURE.md §5가 규정한 "타입별 상세
  테이블 batch 조회" 패턴을 그대로 반영하기 위함)
- Lightweight Migration으로 처리 불가능한 1:N 분해(`DocumentBlock` 1개 →
  `TextItem` 1개 + `TextMark` N개)가 있으므로 반드시 Custom Mapping Model +
  `NSEntityMigrationPolicy`를 사용한다 — Lightweight Migration만으로 시도하지 말 것

## Acceptance Criteria

- [ ] `SemiboldModel.xcdatamodeld`에 새 model version이 추가되고, 이전 버전이
      삭제되지 않고 보존되어 있다
- [ ] 새 엔터티(`Document`, `DocumentItem`, `TextItem`, `TextMark`, `Asset`,
      `MediaItem`)가 `tasks/NO-005.md` §3의 필드 정의와 정확히 일치한다
- [ ] `Folder` 엔터티는 변경되지 않았다 (`git diff`로 기존 정의와 동일함을 확인)
- [ ] Custom `NSEntityMigrationPolicy`가 `DocumentBlock.contentJSON`(BlockContent
      JSON)을 파싱해서 `TextItem` 1개 + 필요한 만큼의 `TextMark`로 분해한다
- [ ] 마이그레이션 매핑 모델이 `Folder`→`Folder`(변경 없음), `Document`→`Document`,
      `DocumentBlock`→`DocumentItem`+`TextItem`(+`TextMark`)의 관계를 모두 커버한다
- [ ] 마이그레이션 실행 전 기존 스토어 파일을 별도 위치에 백업 복사하는 로직이
      `DatabaseManager` 또는 전용 마이그레이션 헬퍼에 구현되어 있다
- [ ] 마이그레이션 실패 시 백업에서 롤백하는 경로가 구현되어 있고, 실패는
      조용히 무시되지 않고 `DatabaseManager.openError`(또는 동등한 경로)로
      전달된다 (§15.2 "DB 열기 실패" 패턴 재사용)
- [ ] in-memory Core Data 스토어에 구 스키마 샘플 데이터를 넣고 마이그레이션을
      실행해 새 스키마로 정확히 변환되는지 확인하는 단위 테스트가 최소 1개
      존재한다 (Folder 1개 + Document 1개 + DocumentBlock 2개 이상, 서식 포함)

## Open Questions / Follow-ups

- Core Data Custom Migration Policy는 XCTest에서 실행 시간이 길 수 있다 —
  swift-reviewer가 테스트 성능이 문제되는지 확인 필요
