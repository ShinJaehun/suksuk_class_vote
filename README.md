# 쑥쑥교실투표

`쑥쑥교실투표`는 교사가 한 대의 장치로 학생 투표를 감독하고, 학급투표와 전교투표를 운영하는 Rails 애플리케이션이다. 학생은 로그인 계정을 사용하지 않으며 교사가 학생별 진행을 제어한다.

## 핵심 구조

- `School`, `Classroom`, `Student`: 학교 조직과 학년도별 학급·학생 명단
- `User`, `SchoolMembership`: `login_id`로 로그인하는 교사·관리자와 학교 내 대표 선생님 역할
- `Poll`, `PollContest`, `PollOption`: 투표 정의와 항목·선택지
- `PollSession`: 한 학급의 실제 투표 실행 단위
- `PollParticipant`, `PollParticipation`, `PollContestCompletion`, `PollProgress`: 시작 시점 학생 snapshot과 참여·진행 상태
- `PollOptionTally`, `PollContestTally`: 개인 선택과 분리된 count-only 집계
- `PollEvent`: 선택 내용이 아닌 운영 이벤트

학급투표는 한 Classroom의 PollSession으로 운영한다. 전교투표는 별도 선거 runtime을 사용하지 않고 `school_managed: true`인 Poll 아래에 대상 학급별 PollSession을 둔다.

## 인증과 권한

계정 식별자는 `login_id`다. global admin은 전체 관리 권한을 가지며, 학교의 manager는 자기 학교 범위에서 선생님·교실과 전교투표를 관리한다. 일반 teacher는 담당 Classroom과 자신이 운영하는 PollSession 범위에서 작업한다.

학생은 인증 주체가 아니다. 모든 권한의 최종 판단은 controller와 Pundit policy에서 수행한다. 사용자는 상단 계정 링크에서 현재 비밀번호를 확인한 뒤 자기 비밀번호만 변경할 수 있다.

## 투표와 기록 보존

PollSession 시작 시 active Student를 PollParticipant로 복사한다. 학생명·번호, 학급명과 운영자명 등 당시 snapshot은 진행과 역사 표시의 기준이며, 이후 Classroom·Student·User 변경으로 과거 기록을 덮어쓰지 않는다.

학생별 화면에서는 `completed`와 `abstained`를 모두 `투표 완료`로 표시한다. `absent`는 `미참여`, 참여 기록이 없으면 `대기`다. 누가 기권했는지는 표시하지 않으며 기권 수는 익명 결과 집계에서만 제공한다.

## Realtime과 복구

Turbo Stream과 Action Cable은 빠른 화면 갱신 수단이다. DB가 authoritative state이며 HTTP polling과 recovery endpoint가 Cable 유실이나 오래 열린 stale 화면을 DB 상태로 수렴시키는 안전망이다.

PollSession 운영 화면의 `operation_screen` stream은 `PollSessionPolicy#operate?`가 허용한 사용자만 구독한다. 조회 권한만 있는 school manager는 이 stream을 구독하지 않고 HTTP polling으로 진행 정보를 갱신한다. 학생 ballot도 realtime 갱신과 HTTP recovery를 함께 사용한다.

## 문서

- [현재 시스템](docs/architecture/current_system.md)
- [학교 기반 투표 아키텍처](docs/architecture/school_voting_platform.md)
- [비밀투표와 집계](docs/architecture/privacy_and_tally.md)
- [복구와 무결성](docs/architecture/recovery_and_integrity.md)
- [역할과 권한](docs/architecture/roles_and_permissions.md)
- [RSpec 전략](docs/testing/rspec_strategy.md)

개발 에이전트와 기여자는 [AGENTS.md](AGENTS.md)의 작업 원칙을 먼저 따른다.
