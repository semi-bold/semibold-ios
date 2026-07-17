# Feature: 06-migration-rehearsal

## Source

- `tasks/NO-005.md` §8 Phase 7, §5 (마이그레이션 플로우), §7 (예외 처리)
- 데이터: `.database/cloud.sqlite`(+ `-wal`/`-shm`) — `/sync-data` 스킬로 받은
  실기기(이진혁의 iPhone) 스냅샷. `.gitignore` 대상이라 저장소에는 없으며,
  이 브리프를 진행하는 사람이 로컬에서 `/sync-data`를 다시 실행해 준비해야 한다

## Scope

- In scope:
  - `.database/cloud.sqlite` 스냅샷을 01의 마이그레이션 정책으로 실제 변환해
    데이터 개수·내용이 보존되는지 확인
  - 마이그레이션 실패를 인위로 유발해(예: 손상된 파일 복사본) 01에서 만든
    롤백 경로가 실제로 동작하는지 확인
  - 위 리허설 결과를 재현 가능한 테스트/스크립트로 남기기
- Out of scope / deferred:
  - 실제 버전업(`v0.2.0`) 배포, App Store 제출 — 이 브리프는 마이그레이션이
    "안전하다"는 근거를 만드는 것까지이고, 실제 배포는 `/release` 스킬로
    별도 진행 (이 저장소의 릴리스 절차, 사용자 승인 필요)

## Screens & Flows

해당 없음 — 검증 전용.

## Decisions & Deviations

- 실사용자 데이터를 다루므로 원본 `.database/cloud.sqlite`를 직접 변형하지
  않는다 — 반드시 복사본에 대해서만 마이그레이션을 실행한다
- 이 리허설은 01의 마이그레이션 테스트(합성 샘플 데이터 기준)와 별개로,
  "실제 운영 데이터 형태"에 대한 추가 검증이다 — 01의 테스트를 대체하지 않음

## Acceptance Criteria

- [ ] `.database/cloud.sqlite`의 복사본에 대해 01의 마이그레이션을 실행하는
      스크립트 또는 XCTest가 작성되어 있다 (예: `semiboldTests/Support/`
      아래 실기기 스냅샷을 fixture로 로드하는 헬퍼)
- [ ] 마이그레이션 전후 `ZFOLDER`/`ZDOCUMENT`/`ZDOCUMENTBLOCK` row 수와 새
      스키마의 `Folder`/`Document`/`DocumentItem`/`TextItem` row 수를 비교해
      데이터 유실이 없음을 확인하는 결과가 기록되어 있다 (테스트 assertion
      또는 리허설 로그)
- [ ] 마이그레이션 전/후 각 문서의 마크다운 export 결과를 비교해 내용이
      동일함을 확인한다 (`tasks/NO-005.md` §4.2)
- [ ] 손상된/불완전한 스토어 파일로 마이그레이션을 시도했을 때, 01에서
      구현한 롤백 경로가 실제로 백업에서 복구하고 `DatabaseManager.openError`
      (또는 동등 경로)로 실패가 드러남을 확인하는 테스트가 있다
- [ ] 위 검증 결과를 요약한 내용이 PR 설명 또는 브리프 커밋 메시지에 남아있다
      (다음 사람이 "이 마이그레이션이 왜 안전하다고 판단했는지" 알 수 있도록)

## Open Questions / Follow-ups

- 리허설이 끝나고 실제 배포로 진행할 때는 `/release` 스킬을 통해 버전을
  올리고 사용자 승인 하에 push해야 한다 — 이 브리프의 범위가 아니다
