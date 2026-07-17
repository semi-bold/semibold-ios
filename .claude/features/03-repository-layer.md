# Feature: 03-repository-layer

## Source

- `tasks/NO-005.md` §4.3 (Repository/도메인 모델 재편)
- 참고(패턴): `semibold/Data/FolderRepository.swift` (context 주입, `NSFetchRequest`+`NSPredicate` 조회, `apply(_:to:)`/`init(entity:)` 매핑, 소프트 삭제 패턴 — 새 Repository들도 이 패턴을 그대로 따름)

## Scope

- In scope:
  - `Data/DocumentRepository.swift` — 기존 파일 유지하되 `blocks` 관련 로직 제거, `items`(→`DocumentItemRepository`) 관계로 대체
  - `Data/DocumentItemRepository.swift` 신규 (공통 위치/계층/순서 CRUD)
  - `Data/TextItemRepository.swift`, `Data/TextMarkRepository.swift` 신규
  - `Data/MediaItemRepository.swift`, `Data/AssetRepository.swift` 신규
  - `Data/DocumentBlockRepository.swift` 폐기(삭제)
- Out of scope / deferred:
  - `Data/FolderRepository.swift` 자체는 변경하지 않는다 (내부 구현 조정이
    필요하면 최소화 — Folder는 이번 마이그레이션의 대상이 아님)
  - ViewModel 변경 (04에서 진행)

## Screens & Flows

해당 없음 — 데이터 접근 레이어 전용, 화면 변경 없음.

## Decisions & Deviations

- Repository는 `FolderRepository.swift`의 기존 관례를 그대로 따른다:
  `NSManagedObjectContext`를 생성자에서 기본값(`DatabaseManager.sharedOrFallbackContext`)으로
  주입받고, Core Data 엔터티는 Repository 밖으로 절대 노출하지 않는다
  (CLAUDE.md §3)
- 소프트 삭제(`deletedAt`)와 순서 정렬(`orderKey` 기준 `NSSortDescriptor`) 로직은
  기존 `FolderRepository`/`DocumentRepository`의 패턴을 재사용한다
- `DocumentItemRepository`는 `parentItemId`/`documentId` 기준 자식 조회,
  `TextItemRepository`/`MediaItemRepository`는 `itemId` 기준 1:1 조회를
  제공한다 (STORAGE_ARCHITECTURE.md §5 "타입별 상세 데이터 batch 조회" 패턴)

## Acceptance Criteria

- [ ] `DocumentItemRepository`가 문서 내 콘텐츠 요소의 생성/조회(부모별
      자식 목록, 순서 정렬)/수정/소프트 삭제/재귀 하드 삭제를 제공한다
- [ ] `TextItemRepository`가 `itemId` 기준 단건 조회 및 여러 `itemId`에
      대한 batch 조회(N+1 방지, STORAGE_ARCHITECTURE.md §5.2 패턴)를 제공한다
- [ ] `TextMarkRepository`가 `itemId` 기준 서식 batch 조회(§5.3 패턴,
      `start_offset` 정렬)를 제공한다
- [ ] `MediaItemRepository`/`AssetRepository`가 §5.4 패턴대로 join 조회를 제공한다
- [ ] `DocumentRepository`에서 `blocks`/`DocumentBlock` 관련 코드가 모두
      제거되고 `items`(`DocumentItem`) 기준으로 대체되어 있다
- [ ] `Data/DocumentBlockRepository.swift`가 삭제되어 있다
- [ ] 모든 새 Repository가 Core Data 타입(`NSManagedObject` 서브클래스)을
      반환하거나 파라미터로 받지 않는다 — 공개 API는 02에서 만든 plain
      struct만 사용한다
- [ ] 각 Repository에 대해 최소 1개의 CRUD 단위 테스트가 있다 (in-memory
      Core Data 스토어 기준 — 새 테스트 스위트는 05에서 본격 재작성하지만,
      이 브리프에서 작성한 Repository가 최소한 동작함을 검증하는 스모크
      테스트는 포함)

## Open Questions / Follow-ups

- 없음
