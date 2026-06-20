# Feature: 01-coredata-migration

Status: draft

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: none (data-layer only, no UI change)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-002.md` §8 Step 1,
  §4.1 (저장 컨테이너 분기 code reference, NSPersistentContainer 부분만)
- PLANNING.md sections (legacy fallback): §9 (저장 및 동기화 설계)
- SERVICE.md sections: none

## Scope

- In scope:
  - 기존 GRDB(SQLite) 스키마(`folders`/`documents`/`document_blocks`)를
    Core Data `.xcdatamodeld` Entity로 변환
  - `NSPersistentContainer` 기반 로컬 전용 동작으로 전환 (이 브리프에서는
    `NSPersistentCloudKitContainer` 분기는 다루지 않음 — 02번 브리프 범위)
  - 기존 Repository 레이어(`FolderRepository`, `DocumentRepository`,
    `DocumentBlockRepository`)를 Core Data 방식으로 재작성하되, 외부
    호출부(ViewModel)에서 보는 인터페이스(메서드 시그니처)는 최대한 유지
  - `DatabaseManager`를 Core Data `NSPersistentContainer` 래퍼로 교체
  - 기존 GRDB 마이그레이션(`AppMigrations.swift`)을 대체하는 Core Data
    모델 정의로 전환 — 시뮬레이터에 남아있는 기존 SQLite 데이터는
    마이그레이션 대상에서 제외(새 스토어로 새로 시작), 데이터 보존은
    요구하지 않음
  - GRDB 의존 테스트(`FolderDocumentPersistenceTests.swift`,
    `DetailViewModelTests.swift`)를 Core Data in-memory
    (`NSPersistentContainer(inMemory: true)`) 방식으로 재작성
  - `project.yml`에서 GRDB SPM 패키지 의존성 제거
- Out of scope / deferred:
  - `NSPersistentCloudKitContainer` 분기, iCloud 가용성 감지, `sync_mode`
    관리 → 02-icloud-sync-branching
  - 온보딩 동의 UX, 설정 화면 → 03/04번 브리프
  - 실제 CloudKit 컨테이너 연동 테스트 (Developer Console 설정 진행 중)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| (없음 — 데이터 레이어 전환만) | `DatabaseManager`, `FolderRepository`, `DocumentRepository`, `DocumentBlockRepository` | UI 변경 없음, 화면 동작은 기존과 동일하게 유지되어야 함 |

## Decisions & Deviations

- CLAUDE.md §2 "Do not introduce Core Data ... without an explicit
  decision to do so" — NO-002 진행을 위해 Core Data 도입이 명시적으로
  결정됨 (Apple Developer Program 등록 완료, CloudKit 동기화가 제품
  요구사항). 이 브리프 완료 시 CLAUDE.md §2 Tech Stack 표를 갱신할 것.
- 기존 시뮬레이터에 남아있는 GRDB SQLite 데이터는 보존하지 않음 — 로컬
  전용 신규 스토어로 시작. 사용자 대상 마이그레이션 정책은 아직 출시
  전이라 불필요하다고 판단.
- Repository 레이어의 외부 인터페이스(예: `FolderRepository.create(_:)`,
  `children(of:)`, `softDelete(id:)`)는 유지하되, 내부 구현만 Core Data
  `NSFetchRequest`/`NSManagedObjectContext`로 교체. ViewModel 레이어
  (`HomeViewModel`, `DetailViewModel` 등)는 가능한 한 수정 없이 동작해야
  함 — Repository가 같은 계약을 지키는 한 ViewModel을 바꿀 필요는 없음.

## Acceptance Criteria

- [ ] `semibold/Data/SemiboldModel.xcdatamodeld`에 `Folder`/`Document`/
      `DocumentBlock` Entity가 기존 GRDB 스키마의 모든 컬럼
      (`id`, `parentId`/`folderId`, `name`/`title`, `sortOrder`,
      `createdAt`, `updatedAt`, `deletedAt`, block의 `type`,
      `contentJSON`, `markdownSource` 등)을 1:1로 반영해 정의됨
- [ ] `DatabaseManager`가 `NSPersistentContainer` 기반으로 재작성되고,
      `shared`/`sharedOrFallbackQueue`에 대응하는 접근 지점이 기존과
      동일한 실패 처리(열기 실패 시 `DatabaseUnavailableView` 분기)를
      유지함
- [ ] `FolderRepository`, `DocumentRepository`, `DocumentBlockRepository`가
      Core Data로 재작성되고 기존 메서드 시그니처를 유지하며, soft
      delete(`deletedAt`) 동작이 기존과 동일하게 보존됨
- [ ] `FolderDocumentPersistenceTests.swift`, `DetailViewModelTests.swift`
      등 GRDB 의존 테스트가 Core Data in-memory 컨테이너 기준으로
      재작성되어 전체 테스트 스위트가 통과함
- [ ] `project.yml`에서 GRDB SPM 패키지 의존성이 제거되고
      `xcodegen generate` 후 빌드가 정상 동작함

## Open Questions / Follow-ups

- CloudKit 실연동 테스트는 Apple Developer Console 설정(Team ID 발급
  대기 중) 완료 후 02번 브리프에서 진행
