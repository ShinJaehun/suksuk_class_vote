# AGENTS.md

## 목적

이 문서는 `suksuk_class_vote` 저장소에서 작업하는 에이전트가 현재 코드와 기준 문서를 우선하고, 작은 범위로 안전하게 변경하도록 안내한다.

`쑥쑥교실투표`는 교사가 한 대의 장치로 학생 투표를 감독하는 Rails 애플리케이션이다. 현재 runtime은 `School` / `Classroom` / `Student`와 `Poll` / `PollSession`을 중심으로 한다.

## 문서 참조 순서

작업 전에 다음 순서로 관련 문서를 확인한다.

1. `AGENTS.md`
2. `docs/architecture/*.md`
3. 작업과 직접 관련된 `docs/specs/*.md`
4. `docs/testing/*.md`

명백히 역사·전환 문서로 표시된 문서는 현재 구현의 기준으로 사용하지 않는다. 현재 문서와 구현이 다르면 임의로 추측하지 말고 사용자에게 확인한다.

주요 기준 문서:

- `docs/architecture/current_system.md`
- `docs/architecture/school_voting_platform.md`
- `docs/architecture/privacy_and_tally.md`
- `docs/architecture/recovery_and_integrity.md`
- `docs/architecture/roles_and_permissions.md`
- `docs/testing/rspec_strategy.md`

## 현재 도메인 기준

- 조직·명단: `School`, `Classroom`, `Student`
- 계정·학교 역할: `User`, `SchoolMembership`
- 정의: `Poll`, `PollContest`, `PollOption`
- 학급 실행: `PollSession`
- snapshot·진행: `PollParticipant`, `PollParticipation`, `PollContestCompletion`, `PollProgress`
- 익명 집계·운영 기록: `PollOptionTally`, `PollContestTally`, `PollEvent`

전교투표는 `school_managed: true`인 Poll과 학급별 PollSession으로 구현한다. 새 기능은 실제 모델·route·controller·policy 구조를 확인한 뒤 Rails 관례에 맞는 가장 단순한 형태로 추가한다.

## 핵심 불변조건

- 학생은 로그인 User가 아니라 Classroom의 명단 데이터다.
- PollSession 시작 시 active Student를 PollParticipant snapshot으로 고정한다.
- 시작 뒤 투표 정의, 대상, snapshot과 결과 의미를 임의로 바꾸지 않는다.
- 당시 학생명·번호, 학급명, 운영자명 snapshot이 있으면 역사 기록에는 snapshot을 우선한다.
- 현재 Classroom·Student·User 값으로 과거 snapshot을 덮어쓰지 않는다.
- 학생별 선택이나 기권 여부를 이름과 연결해 저장·표시하지 않는다.
- 학생별 UI에서 `completed`와 `abstained`는 `투표 완료`, `absent`는 `미참여`, 참여 기록 없음은 `대기`로 표시한다.
- 후보별 표와 기권 수는 개인과 연결되지 않은 count-only tally로 유지한다.
- 중복 제출 방지, transaction, lock 순서, 상태 전이와 replacement 이력 보존을 편의성보다 우선한다.
- 진행 중 Poll에 연결된 Classroom·운영 구조 변경은 기존 model/service guard를 우회하지 않는다.

## 권한과 realtime

권한은 controller와 Pundit policy가 최종 방어선이다. view의 버튼 숨김이나 stream 구독 조건을 서버 권한 검증의 대체물로 사용하지 않는다.

Turbo Stream과 Action Cable은 빠른 갱신 수단이지 authoritative state가 아니다. DB 상태와 HTTP polling/recovery가 Cable 유실과 stale UI의 최종 복구 기준이다. PollSession의 `operation_screen` 구독은 `operate?` 권한에 맞추고, 읽기 전용 사용자는 polling으로 갱신한다. broadcast, polling, recovery를 변경할 때는 수신자 권한과 HTML/Turbo 응답을 함께 확인한다.

## 구현 원칙

- Rails way와 현재 코드의 naming·partial·controller 책임을 우선한다.
- 불필요한 계층, 추상화, 메타프로그래밍과 ActionCable channel을 추가하지 않는다.
- controller는 인증·권한·흐름을 담당하고, 불변식은 model, 중요한 상태 전이는 작은 service object에 둔다.
- view에는 계산·권한·도메인 판단을 늘리지 않는다.
- 문자열 변경 시 locale 반영 여부를 확인한다.
- 기존 public behavior와 HTML/Turbo 응답을 함부로 바꾸지 않는다.
- 코드 변경으로 기준 문서의 현재 상태가 달라지면 관련 문서만 함께 갱신한다.

## 변경 승인

기본적으로 쓰기 전에 변경 목적, 대상 파일, 핵심 변경과 위험을 짧게 제시하고 사용자 승인을 기다린다. 사용자가 즉시 반영을 명시한 경우에만 바로 수정한다. 문서도 같은 원칙을 따른다.

변경 대상이 3개 파일을 넘거나 새 route/model/service/migration이 필요하면 수정 전에 범위를 재확인한다. 작업 중 예상보다 범위가 커져도 멈추고 확인한다. 전체 diff는 사용자가 명시적으로 요청한 경우에만 제시한다.

## 토큰 절약

- 작업 전 `git status --short`만 먼저 확인한다.
- 관련 파일과 필요한 줄 범위만 읽고 수정한다.
- 검색은 controller/action/model/spec 이름 등 좁은 단서부터 시작한다.
- 사용자가 제공한 로그·diff·문서를 반복 출력하지 않는다.
- 전체 diff, 전체 route, 긴 로그와 backtrace를 출력하지 않는다.
- 변경 파일은 가능하면 1~3개로 제한한다.
- 긴 계획과 대안 나열을 피하고 권장안 하나를 짧게 제시한다.

## 테스트와 검증

테스트 목적은 coverage가 아니라 confidence다. 핵심 도메인 규칙, 권한, 상태 전이, 멱등성, request 흐름을 우선하고 brittle한 HTML 구조 검증과 과한 shared abstraction을 피한다.

Codex/에이전트는 다음 작업을 직접 실행하지 않는다.

- `bundle exec rspec`
- `bin/rails test`
- 그 밖의 테스트와 RuboCop
- 서버와 브라우저 실행
- migration 실행

검증 명령은 사용자에게 제시하고 사용자가 직접 실행한다. `git status`, 필요한 `grep`/`find`, 제한된 `git diff`처럼 상태를 바꾸지 않는 범위 확인은 수행할 수 있다. 테스트 전략은 `docs/testing/rspec_strategy.md`를 따른다.

## 작업 보존과 Git

- dirty worktree의 사용자 변경과 작업 범위 밖 파일을 보존한다.
- 사용자 변경을 임의로 되돌리지 않는다.
- 삭제·복구 대상은 반영 전에 목록을 제시한다.
- `main`에 직접 작업하지 않고, 관련 브랜치가 있으면 그 브랜치를 이어 쓴다.
- commit, push, merge를 직접 실행하지 않는다.
- `git add`를 포함한 staging도 직접 수행하지 않고 사용자가 처리한다.
- destructive command와 광범위한 reset을 사용하지 않는다.

## 완료 보고

특별한 사유가 없으면 15줄 이내로 다음을 보고한다.

```text
수정 파일:
- ...

핵심 변경:
- ...

건드리지 않음:
- ...

사용자 실행:
- ...

커밋하지 않음.
```
