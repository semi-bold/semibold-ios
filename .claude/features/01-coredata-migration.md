# Feature: 01-coredata-migration

Status: in-progress

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
- FK(`parentId`/`folderId`/`documentId`)는 스칼라 컬럼이 아니라 Core
  Data 관례에 따라 `NSRelationship`(`Folder.parent`/`children`,
  `Document.folder`, `DocumentBlock.document`/`parent`)으로만 모델링함.
  AC의 "1:1 컬럼 반영" 요구는 named 관계로 충족된 것으로 간주 — 기존
  GRDB 저장소가 `Column("parentId")`/`Column("documentId")` 같은 플랫
  컬럼에 직접 필터/정렬을 걸던 부분은, 이어지는 Repository 재작성 AC
  항목에서 관계 keypath 기반 `NSFetchRequest` 술어(predicate)와
  `NSSortDescriptor`로 옮겨 처리한다(예: `parentId == nil` →
  `parent == nil`, `.order(Column("documentId"), Column("parentId"), …)`
  → `NSSortDescriptor(keyPath: \DocumentBlockEntity.document.id, …)`
  류). 관계와 중복되는 스칼라 FK 속성은 추가하지 않음.
- `DatabaseManager`는 `NSPersistentContainer`(model name `"SemiboldModel"`)
  래퍼로 재작성됨. 기존 `init(path:) throws` → `init(storeURL:) throws`로
  바뀌었고, `dbQueue: DatabaseQueue` → `persistentContainer:
  NSPersistentContainer`, `sharedOrFallbackQueue` →
  `sharedOrFallbackContext: NSManagedObjectContext`로 대응시킴.
  `shared: DatabaseManager?` / `openError: Error?` 패턴과
  `defaultDatabasePath()` → `defaultStoreURL()`(Application Support 내
  `semibold.sqlite`, 동일 경로 유지)는 그대로 보존해 `SemiboldApp.swift`의
  `DatabaseManager.shared == nil` 분기가 코드 수정 없이 그대로 동작함.
  `loadPersistentStores`는 콜백 기반이지만 로컬 SQLite/in-memory 스토어는
  호출이 반환되기 전에 동기적으로 완료되므로, 콜백에서 에러를 캡처해
  `init`이 반환하기 직전에 던지는 방식으로 기존 `throws` 시그니처를
  유지함.
- 이 AC 항목 완료 시점에 `FolderRepository`/`DocumentRepository`/
  `DocumentBlockRepository`는 아직 GRDB `DatabaseQueue`/
  `DatabaseManager.sharedOrFallbackQueue`를 참조하므로 전체 타겟 빌드는
  실패하는 것이 의도된 전환기 상태임(다음 AC 항목인 Repository
  Core Data 재작성에서 해소). `DatabaseManager.swift` 자체는
  격리 상태로 컴파일 에러 없이 빌드됨 — 실제 컴파일 에러는
  `FolderRepository.swift:12`, `DocumentRepository.swift:12`,
  `DocumentBlockRepository.swift:12`의 `sharedOrFallbackQueue` 참조뿐임.
- 삭제 규칙(`deletionRule`): FK를 들고 있는 to-one 쪽
  (`Document.folder`, `DocumentBlock.document`, `Folder.parent`,
  `DocumentBlock.parent`)은 `Nullify`를 유지해 기존 GRDB가 갖고 있던
  "자동 cascade 없음" 동작을 보존함. to-many 역방향 쪽
  (`Folder.children`, `Folder.documents`, `Document.blocks`,
  `DocumentBlock.children`)은 `Nullify` 대신 `Deny`로 설정함. Core
  Data는 객체가 **삭제되는 쪽**에서 선언된 관계의 삭제 규칙을 따르므로
  (예: `Folder`를 삭제할 때 적용되는 규칙은 `Folder.children`/
  `Folder.documents`에 선언된 것이고, 그 역방향인 `DocumentBlock.parent`/
  `Document.folder`의 규칙이 아님), 자식이 남아있는 상태로 부모를
  삭제하면 `Deny`가 저장을 막아 "자동 cascade도, 묵시적 orphan도
  없음"을 보장함. 이에 따라 Repository 재작성 AC에서 구현할
  `hardDelete`는 부모를 삭제하기 전에 자식 행을 먼저 직접 삭제하거나
  연결을 끊어야 함 — Core Data가 대신 cascade해주지 않음.

## Acceptance Criteria

- [x] `semibold/Data/SemiboldModel.xcdatamodeld`에 `Folder`/`Document`/
      `DocumentBlock` Entity가 기존 GRDB 스키마의 모든 컬럼
      (`id`, `parentId`/`folderId`, `name`/`title`, `sortOrder`,
      `createdAt`, `updatedAt`, `deletedAt`, block의 `type`,
      `contentJSON`, `markdownSource` 등)을 1:1로 반영해 정의됨
- [x] `DatabaseManager`가 `NSPersistentContainer` 기반으로 재작성되고,
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
- `DatabaseManager`의 `loadPersistentStores` 동기 완료 가정은 현재
  local SQLite/in-memory 구성(`shouldAddStoreAsynchronously` 미설정,
  `NSPersistentCloudKitContainer` 미사용)에서만 유효함. 02번 브리프에서
  `NSPersistentCloudKitContainer`로 교체할 때 이 가정이 깨지지 않는지
  반드시 재확인할 것 (swift-reviewer Suggested 항목).
- `AppMigrations.swift`가 더 이상 `DatabaseManager.init`에서 호출되지
  않아 죽은 코드가 됨 — GRDB 의존성 제거(5번 AC 항목)와 같은 패스에서
  함께 삭제할 것.
