# Feature: 02-icloud-sync-branching

Status: in-progress

## Source

- Feature spec (if provided externally): none
- Wireframes / planning specs: none (data-layer/infra only, no UI change —
  UI consumes this brief's output in 03/04)
- `tasks/<work-code>.md` section (primary): `docs/tasks/NO-002.md` §4
  (기술 접근 방식 전체), §6 (상태 정의), §7 (예외 처리)
- PLANNING.md sections (legacy fallback): §9 (저장 및 동기화 설계)
- SERVICE.md sections: none

## Scope

- In scope:
  - `DatabaseManager`(01번 브리프에서 `NSPersistentContainer`로 전환된
    상태)를 `syncEnabled` 여부에 따라 `NSPersistentCloudKitContainer` /
    `NSPersistentContainer`로 분기하는 팩토리로 확장 (NO-002 §4.1)
  - iCloud 가용성 감지 유틸리티: `FileManager.ubiquityIdentityToken`
    기반으로 로그인/사용 가능 여부 확인 (NO-002 §4.2)
  - `sync_mode` 관리 레이어: `UserDefaults` 키 `sync_mode`에
    `"icloud"`/`"local"`/`nil`(미설정) 저장·조회 (NO-002 §4.3, §6)
  - 모드 전환 로직: 로컬→iCloud, iCloud→로컬 전환 시 컨테이너 재초기화
    (NO-002 §3.2 흐름의 데이터 처리 부분 — UI 경고/확인 다이얼로그는
    04번 브리프에서 붙임)
  - 예외 처리: iCloud quota 초과, 일시 장애, 모드 전환 실패 시 폴백 동작
    (NO-002 §7)
- Out of scope / deferred:
  - 동의 팝업 UI, 설정 화면 UI → 03/04번 브리프 (이 브리프는 그 UI가
    호출할 수 있는 로직/API만 제공)
  - 실제 CloudKit 컨테이너의 레코드 단위 동작 검증 — entitlements/Team ID
    설정이 완료된 이후에만 기기/시뮬레이터에서 의미 있게 테스트 가능.
    Developer Console 설정이 끝나지 않았다면 로컬 전용
    (`NSPersistentContainer`) 경로만 실제로 검증하고, CloudKit 경로는
    컴파일 통과 + 분기 로직 단위 테스트로 대체

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| (없음 — 03/04번 브리프의 UI가 이 브리프의 API를 소비) | `SyncModeStore` (신규), `DatabaseManager` 확장 | |

## Decisions & Deviations

- CloudKit 컨테이너 식별자는 `iCloud.com.semibold.semibold`로 고정
  (Developer Console에 등록될 식별자와 일치시킬 것). 이 브리프 작업
  시점에 `project.yml`의 `DEVELOPMENT_TEAM`이 아직 빈 값이고
  `semibold.entitlements` 파일도 없음 — Apple Developer Console
  설정(Team ID 발급)이 완료되지 않은 상태이므로, 분기 로직은 구현하되
  실제 CloudKit 컨테이너 연동은 entitlements 설정 후로 미룸
- iCloud 가용성 재확인 시점: 설정 화면 진입 시마다 재확인 (실시간 토글
  반응이 아니라 화면 재진입 시 갱신) — Team ID 미확정 상태에서도 분기
  로직 자체는 구현/테스트 가능하도록 설계
- Developer Console 설정(Team ID, entitlements)이 아직 완료되지 않은
  경우, `NSPersistentCloudKitContainer` 초기화 코드는 작성하되 실제
  iCloud 동작 검증은 보류하고 그 사실을 Open Questions에 기록할 것

## Acceptance Criteria

- [x] `DatabaseManager.makeContainer(syncEnabled:)`(또는 동등한 팩토리)가
      `syncEnabled`에 따라 `NSPersistentCloudKitContainer` /
      `NSPersistentContainer`를 반환함 (NO-002 §4.1)
- [x] iCloud 가용성 감지 유틸리티가 `FileManager.ubiquityIdentityToken`
      기반으로 동작하며 단위 테스트로 가용/불가 두 경로 모두 검증됨
- [x] `SyncModeStore`(또는 동등 타입)가 `UserDefaults`의 `sync_mode` 키를
      `"icloud"`/`"local"`/미설정 3가지 상태로 읽고 쓰며, 미설정 상태는
      "최초 실행"으로 간주됨 (NO-002 §4.3, §6)
- [ ] 모드 전환 함수가 로컬→iCloud, iCloud→로컬 양방향으로 컨테이너를
      재초기화하고, 전환 실패 시 원래 모드로 롤백함 (NO-002 §7 "모드
      전환 실패")

## Open Questions / Follow-ups

- Developer Console 설정(Team ID/CloudKit 컨테이너 연결)이 이 브리프
  작업 시점까지 완료되지 않았다면, 실제 iCloud 레코드 동기화 검증은
  보류 — 완료 후 별도로 검증 필요
