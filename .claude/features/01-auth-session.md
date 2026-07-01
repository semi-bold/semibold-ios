# Feature: 01-auth-session

## Source

- 작업 스펙: `tasks/NO-004.md` §4.1 (세션 저장 구조 Keychain), §3.2 (iCloud 가용성 확인 순서)
- Wireframes: 해당 없음 (데이터 레이어 전용)
- PLANNING.md 섹션: 해당 없음

## Scope

- In scope:
  - `AuthSession` 구조체 + `SessionMode` 열거형 정의
  - Keychain 읽기/쓰기/삭제 래퍼 (`KeychainSessionStore`)
  - `ICloudAvailability.isAvailable()` / `unavailableReason()` 기존 로직은 변경 없이 유지
- Out of scope / deferred:
  - UI 화면 (03, 04 브리프에서 처리)
  - `DatabaseManager` 초기화 변경 (02 브리프)
  - Apple 자격증명 취소 감지 UI 처리 (03 브리프)

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| — | `AuthSession.swift` | `semibold/App/` 또는 `semibold/Data/` 하위 |
| — | `KeychainSessionStore.swift` | Keychain I/O 래퍼 |

## Decisions & Deviations

- `AuthSession`은 `appleUserID: String`과 `mode: SessionMode` 두 필드만 가진다.
  `appleUserID`는 "로컬로 이용" 선택 시 빈 문자열 `""` 또는 nil로 저장하지 않는다 —
  mode=.local이면 appleUserID 필드 자체를 저장하지 않아도 무방하도록
  `mode` 단독 저장 경로도 허용. 구현 시 판단하여 일관된 방식 선택.
- Keychain 항목: `service = "com.semibold.auth"`, `key = "session"`,
  `accessibility = kSecAttrAccessibleAfterFirstUnlock`
- `KeychainSessionStore`는 `static` 또는 `@Observable singleton` 중 팀 컨벤션에 맞게 선택.
  `SyncModeStore`처럼 UserDefaults 없이 Keychain만 사용.

## Acceptance Criteria

- [ ] `SessionMode: String` enum (`.icloud`, `.local`) 정의
- [ ] `AuthSession` 구조체 정의: `appleUserID: String`, `mode: SessionMode`
- [ ] `KeychainSessionStore.save(_ session: AuthSession)` — Keychain에 세션 저장
- [ ] `KeychainSessionStore.load() -> AuthSession?` — Keychain에서 세션 복원, 없으면 nil
- [ ] `KeychainSessionStore.delete()` — 세션 삭제 (자격증명 취소 시 사용)
- [ ] 단위 테스트: save → load 왕복, delete 후 load == nil

## Open Questions / Follow-ups

- 없음. 데이터 레이어이므로 UI 결정 불필요.
