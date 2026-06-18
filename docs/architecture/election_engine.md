# Election Engine

## 목적

이 문서는 `쑥쑥교실투표`의 선거 기능을 기존 `Poll` 확장이 아니라 별도 범용
`Election` 엔진으로 설계하기 위한 기준 문서다.

이번 문서는 설계 기준만 정의한다. migration, model, controller, view, service,
spec 변경은 다음 커밋부터 다룬다.

---

## 설계 결정 요약

`Poll`과 `Election`은 분리한다.

`Poll`은 일반 수업 활동용 간단 투표, 토의, 토론 엔진으로 유지한다. 현재
`PollsController`와 view 흐름도 기존 Poll 활동을 계속 담당한다.

`Election`은 선거 준비, 진행, 개표, 무결성 확인을 중심으로 하는 별도 엔진으로
둔다. 선거는 여러 contest, contest별 선택 정책, 기권, 복수 선출, 무투표 당선,
찬반투표, 교사 감독 투표, 추후 PIN 기반 개별 투표까지 고려해야 한다. 이 요구를
기존 `Poll`에 계속 붙이면 Poll의 수업 활동 모델과 선거 도메인이 서로의 복잡도를
키운다.

기존 `Poll`을 더 확장하지 않는 이유:

- Poll은 단일 선택 중심의 간단 활동에 맞는 구조다.
- 다중 contest, contest별 선택 수, 좌석 수, 기권, 무결성 gate를 Poll에 계속
  추가하면 일반 Poll 흐름이 선거 예외 분기로 오염된다.
- `PollsController`와 view에 전교학생회 선거 분기를 더 넣으면 수업 활동과 선거
  운영 책임이 섞인다.
- 선거의 중복 제출 방지, tally, 운영 이벤트, 개표 정책은 Poll보다 더 강한
  도메인 규칙이 필요하다.

전교학생회 선거만을 위한 특수 구조도 만들지 않는다. 전교학생회 선거는 학급임원
선거, 사용자 자율 contest 구성, 복수 선택, PIN 로그인 기반 투표로 확장될 첫 번째
사용 사례로 본다. 따라서 `SchoolElection` 전용 구조가 아니라 범용 `Election`
엔진을 기준으로 설계한다.

현재 `SchoolElection` + `Poll` 재사용 기반 구현은 spike이자 기반 검증으로 본다.
검증된 개념은 `Election` 엔진으로 일반화하고, Poll-backed 전교학생회 흐름은
전환 완료 후 정리한다.

---

## Poll과 Election의 역할 구분

### Poll

`Poll`은 일반 수업 활동을 담당한다.

역할:

- 단일 선택 중심의 간단 투표
- 토의, 토론, 의견 수집
- 교사가 빠르게 만들고 진행하는 수업 활동
- 기존 `PollsController`와 Poll view 유지

Poll은 선거 전용 무결성 정책, 다중 contest 개표, 좌석 수 기반 당선 계산,
contest별 기권 정책을 핵심 책임으로 갖지 않는다.

### Election

`Election`은 선거와 개표를 담당한다.

역할:

- 선거 준비, 진행, 종료, 개표, 무결성 확인
- 하나의 선거 안에 여러 contest 구성
- contest별 선택 정책 설정
- contest별 단일 선택, 제한 복수 선택, approval, 찬반투표 수용
- 교사 감독 순번 투표와 추후 학생 PIN 개별 투표를 같은 도메인 구조로 수용
- 기존 Poll controller/view와 분리된 controller/view 흐름

Election은 수업 활동 Poll의 편의성보다 상태 무결성, 중복 제출 방지, 복구 가능성,
비밀투표 원칙을 우선한다.

---

## 목표 모델 구조

### Election

선거의 최상위 단위다.

책임:

- 선거 제목, 종류, 상태, 생성자 보관
- contest, candidate, session의 부모
- draft/in progress/closed/stopped 상태 전이의 기준
- 전체 집계와 admin 관리의 기준

### ElectionContest

선거 안의 개별 경선 또는 안건이다.

책임:

- 회장, 부회장, 학급회장, 학급부회장 같은 투표 단위 표현
- contest별 선택 방식과 선택 수 정책 보관
- 후보자 구성의 부모
- contest별 tally와 무결성 확인 기준 제공

### ElectionCandidate

contest에 출마한 후보자다.

책임:

- 후보자 이름, 번호, 표시 순서 등 후보 정보 보관
- 특정 `ElectionContest`에 소속
- 후보별 tally의 기준

### ElectionSession

실제 투표가 진행되는 단위다.

책임:

- 특정 election을 특정 교사와 participant group 단위로 운영
- 전교학생회 선거의 학급별 투표소, 학급임원 선거의 학급 투표소 표현
- supervised 또는 pin_login 같은 운영 방식 보관
- voter snapshot, progress, participation, tally의 부모

### ElectionVoter

session 안의 투표자 snapshot이다.

책임:

- `ParticipantSlot`에서 복사한 출석번호와 이름 보관
- 선거 시작 이후 원본 명단 변경과 투표 진행을 분리
- session 안의 투표 순서와 참여 대상 고정
- 학생 계정이 아니라 선거 진행용 명단 row로 동작

### ElectionProgress

session의 진행 복구 상태다.

책임:

- 현재 투표 위치 보관
- session 진행 상태와 started/closed 시각 보관
- 브라우저 상태가 아니라 DB 기준으로 복구 가능하게 함
- tally나 후보 선택 결과는 저장하지 않음

### ElectionParticipation

voter별 처리 상태다.

책임:

- pending, completed, absent, abstained 같은 처리 상태 관리
- 중복 제출 방지의 기준
- 투표 완료, 결석, 기권 여부 보관
- 어떤 후보를 선택했는지는 저장하지 않음

### ElectionCandidateTally

후보별 득표 누적이다.

책임:

- session, contest, candidate별 votes_count 보관
- 단일 선택과 복수 선택 모두 후보별 count-only 집계로 처리
- voter나 participation과 후보 선택을 직접 연결하지 않음

### ElectionContestTally

contest별 후보 외 집계다.

책임:

- session, contest별 abstentions_count 보관
- 후보 선택 없이 contest 단위로 확정되는 기권 수 관리
- contest별 무결성 확인에서 후보 득표 합계와 함께 사용

### ElectionEvent

운영 이벤트 기록이다.

책임:

- 시작, 제출 완료, 결석 처리, 기권 처리, 다음 투표자 진행, 종료 같은 운영 이벤트 기록
- actor와 대상 voter 등 운영상 필요한 정보 보관
- 후보 선택 상세, candidate_id, 선택 후보명, 득표 변화 상세는 저장하지 않음

---

## Election 모델 초안

`Election` 필드 초안:

- `title`
- `kind`
- `status`
- `user_id`

`kind` 후보:

- `school_council`: 전교학생회 선거
- `class_officer`: 학급임원 선거
- `custom`: 사용자가 직접 구성하는 선거

`status` 후보:

- `draft`: 준비 중
- `in_progress`: 하나 이상의 session이 진행 중이거나 선거가 운영 중
- `closed`: 종료 및 결과 확정
- `stopped`: 중단되었고 결과 확정 대상이 아님

초기 구현에서는 기존 상태 전이 원칙과 동일하게 서버 DB를 source of truth로 삼는다.

---

## ElectionContest 정책 필드 초안

`ElectionContest`는 단순 `title`과 `position`만 갖지 않는다. contest별 투표 정책을
명시적으로 보관해야 한다.

필드 초안:

- `title`
- `position`
- `vote_method`
- `min_selections`
- `max_selections`
- `seats_count`
- `allow_abstain`

`vote_method` 후보:

- `single_choice`: 후보 중 1명을 선택
- `limited_choice`: 후보 중 제한된 수만큼 선택
- `approval`: 후보별 승인 여부를 선택
- `yes_no`: 단독 후보 또는 안건에 대한 찬반 선택

필드별 이유:

- `title`: 화면과 결과에서 표시할 contest 이름이다.
- `position`: 선거 안에서 contest 표시 순서를 안정적으로 고정한다.
- `vote_method`: 단일 선택, 복수 제한 선택, approval, 찬반투표를 구분한다.
- `min_selections`: 유효 ballot에 필요한 최소 선택 수를 정한다.
- `max_selections`: 선택 가능한 최대 후보 수를 제한한다.
- `seats_count`: 실제 선출 인원 수를 나타낸다. `max_selections`와 같을 수도 있지만
  항상 같은 개념은 아니므로 분리한다.
- `allow_abstain`: 해당 contest에서 기권을 허용할지 정한다.

예시:

```text
회장
- vote_method: single_choice
- min_selections: 1
- max_selections: 1
- seats_count: 1
- allow_abstain: true

부회장 2명 선출
- vote_method: limited_choice
- min_selections: 1
- max_selections: 2
- seats_count: 2
- allow_abstain: true
```

후보자가 1명인 contest는 추후 정책에 따라 무투표 당선 또는 `yes_no` 찬반투표로
다룰 수 있다. 초기 Election 엔진은 이 가능성을 막지 않는 필드 구조를 둔다.

---

## ElectionSession 개념

`ElectionSession`은 실제 투표가 진행되는 단위다.

예:

- 전교학생회 선거의 6학년 1반 세션
- 전교학생회 선거의 6학년 2반 세션
- 학급임원 선거의 4학년 1반 세션

필드 초안:

- `election_id`
- `teacher_id`
- `participant_group_id`
- `status`
- `operation_mode`

`operation_mode` 후보:

- `supervised`: 교사 장치 앞에서 순번대로 진행
- `pin_login`: 학생이 PIN 또는 token으로 본인 ballot에 접근

초기 구현은 `supervised`만 한다. `pin_login`은 같은 voter, participation, tally
구조를 재사용할 수 있게 필드와 흐름만 열어 둔다.

---

## 투표자와 비밀투표 정책

`ElectionVoter`는 session 안의 투표자 snapshot이다.

보관 정보:

- `session_id`
- `source_participant_slot_id`
- `number`
- `name`

`ElectionVoter`는 `ParticipantSlot`에서 복사한다. 원본 명단이 수정되거나 삭제되어도
이미 시작된 session의 투표 대상과 순서는 바뀌지 않는다.

`ElectionParticipation`은 voter별 처리 상태를 보관한다.

상태 후보:

- `pending`
- `completed`
- `absent`
- `abstained`

중요 정책:

- 개별 학생이 어떤 후보를 선택했는지는 저장하지 않는다.
- 제출 시 후보별 tally 또는 contest별 abstention tally만 증가시킨다.
- 중복 제출 방지는 `ElectionParticipation`으로 한다.
- `ElectionEvent`에도 선택 상세를 저장하지 않는다.
- voter와 candidate를 직접 연결하는 vote record는 기본 구조로 두지 않는다.

이 구조는 현재 `PollParticipant`, `PollParticipation`, count-only tally, `PollEvent`
원칙을 Election 엔진으로 일반화한 것이다.

---

## Tally 구조

### ElectionCandidateTally

필드 초안:

- `session_id`
- `contest_id`
- `candidate_id`
- `votes_count`

복수 선택 투표에서도 `ElectionCandidateTally`는 후보별 득표 누적만 가진다. 예를 들어
부회장 2명 선출에서 한 학생이 후보 2명을 선택하면, 선택된 각 후보의
`votes_count`만 1씩 증가한다. 어떤 voter가 어떤 후보 조합을 선택했는지는 저장하지
않는다.

### ElectionContestTally

필드 초안:

- `session_id`
- `contest_id`
- `abstentions_count`

기권은 후보자가 아니라 contest 단위의 결과이므로 후보별 tally와 분리한다.
contest별 무결성 확인에서는 후보별 득표 합계, 기권 수, participation 상태를 함께
대조한다.

---

## 현재 구현 상태

### Implemented

현재 Election 엔진의 기반 모델은 구현되어 있다.

- `Election`
- `ElectionContest`
- `ElectionCandidate`
- `ElectionSession`
- `ElectionVoter`
- `ElectionParticipation`
- `ElectionProgress`
- `ElectionCandidateTally`
- `ElectionContestTally`
- `ElectionEvent`

현재 supervised operation을 위한 service도 구현되어 있다.

- `Elections::StartSession`
- `Elections::OpenBallot`
- `Elections::LockBallot`
- `Elections::SubmitBallot`
- `Elections::MarkVoterAbsent`
- `Elections::AdvanceVoter`
- `Elections::CloseSession`

### Not Implemented Yet

다음 항목은 아직 구현하지 않았거나 의도적으로 미룬다.

- `Election` 전체 close service와 전역 종료 정책
- `IntegrityReport` 또는 tally consistency report
- controller, route, UI 연결
- teacher supervised voting screen
- admin session result view
- `yes_no` 찬반투표 제출 처리
- `pin_login` voting mode
- 기존 Poll-backed `SchoolElection` 흐름의 Election 엔진 전환
- 개별 선택 기록 모델

개별 선택 기록 모델은 현재 계획에서도 만들지 않는다. 비밀투표 원칙상 voter와
candidate를 직접 연결하는 row나 association은 두지 않는다.

---

## 교사 감독 투표 흐름

현재 구현된 정상 제출 흐름:

```text
StartSession
-> OpenBallot
-> SubmitBallot
-> AdvanceVoter
-> 반복
-> CloseSession
```

현재 구현된 결석 처리 흐름:

```text
StartSession
-> MarkVoterAbsent
-> AdvanceVoter
-> 반복
-> CloseSession
```

수동 잠금 흐름:

```text
OpenBallot
-> LockBallot
```

`LockBallot`은 제출 없이 ballot을 닫는 운영 제어용이다. `SubmitBallot`은 제출 성공
시 `ElectionProgress.ballot_state`를 `locked`로 바꾸므로, 정상 제출 뒤 별도
`LockBallot` 호출이 필수는 아니다.

진행 복구 기준은 브라우저가 아니라 `ElectionProgress`, `ElectionVoter`,
`ElectionParticipation`이다.

### Service Responsibilities

`Elections::StartSession`:

- session을 `in_progress`로 변경한다.
- `ParticipantSlot` snapshot으로 `ElectionVoter`를 생성한다.
- 각 voter의 `ElectionParticipation`을 `pending`으로 생성한다.
- `ElectionProgress`를 생성하고 첫 voter를 현재 voter로 지정한다.
- `ElectionCandidateTally`, `ElectionContestTally`를 0으로 초기화한다.
- `session_started` event를 기록한다.

`Elections::OpenBallot`:

- `ElectionProgress.ballot_state`를 `locked`에서 `open`으로 변경한다.
- 현재 voter가 `pending`일 때만 열 수 있다.
- `ballot_opened` event를 기록한다.

`Elections::LockBallot`:

- `ElectionProgress.ballot_state`를 `open`에서 `locked`로 변경한다.
- 제출 없이 ballot을 닫는 운영 제어용이다.
- `ballot_locked` event를 기록한다.

`Elections::SubmitBallot`:

- `open` 상태의 현재 voter ballot만 제출할 수 있다.
- 선택된 후보의 `ElectionCandidateTally.votes_count`만 증가시킨다.
- 기권한 contest의 `ElectionContestTally.abstentions_count`만 증가시킨다.
- 개별 선택 record를 만들지 않는다.
- voter와 candidate를 연결하지 않는다.
- 모든 contest가 기권이면 participation을 `abstained`로 변경한다.
- 하나라도 후보 선택이 있으면 participation을 `completed`로 변경한다.
- 제출 성공 시 progress를 `locked`로 변경한다.
- current voter는 유지한다. 다음 voter 이동은 `AdvanceVoter`가 담당한다.
- `ballot_submitted` event를 기록한다.
- `yes_no` 제출은 현재 지원하지 않는다.

`Elections::MarkVoterAbsent`:

- `locked` 상태에서 현재 `pending` voter를 `absent`로 처리한다.
- current voter는 유지한다.
- progress는 `locked`로 유지한다.
- `voter_marked_absent` event를 기록한다.

`Elections::AdvanceVoter`:

- `completed`, `absent`, `abstained` 상태의 현재 voter에서만 다음으로 이동한다.
- position 오름차순으로 다음 `pending` voter를 찾는다.
- 이미 처리된 voter는 건너뛴다.
- 다음 pending voter가 없으면 `current_election_voter`를 `nil`로 설정한다.
- session은 닫지 않는다.
- `voter_advanced` event를 기록한다.

`Elections::CloseSession`:

- 모든 voter가 final 상태이고 `current_election_voter`가 `nil`일 때만 session을
  `closed`로 변경한다.
- `Election` 전체 status는 변경하지 않는다.
- `ElectionSession.closed_at`과 `ElectionProgress.closed_at`을 설정한다.
- progress는 `locked`, current voter는 `nil`로 유지한다.
- `session_closed` event를 기록한다.

### State Summary

`ElectionSession.status`:

- `draft`
- `in_progress`
- `closed`
- `stopped`

`ElectionProgress.ballot_state`:

- `locked`
- `open`

`ElectionParticipation.status`:

- `pending`
- `completed`
- `absent`
- `abstained`

`CloseSession` 조건:

- session이 `in_progress`일 것
- operation mode가 `supervised`일 것
- progress가 존재할 것
- progress가 `locked`일 것
- `current_election_voter`가 `nil`일 것
- voter가 1명 이상 있을 것
- 모든 voter에 participation이 있을 것
- 모든 participation이 `completed`, `absent`, `abstained` 중 하나일 것
- `pending` participation이 없을 것

---

## PIN 개별 투표 확장 방향

`pin_login` operation은 지금 구현하지 않는다. 다만 구조상 같은 session, voter,
participation, tally를 재사용할 수 있게 둔다.

방향:

- 학생이 PIN 또는 token으로 본인 voter를 인증한다.
- 인증된 학생은 본인 ballot만 접근한다.
- 한 번 제출하면 `ElectionParticipation` 기준으로 재제출할 수 없다.
- 교사는 개별 선택 내용이 아니라 전체 진행률만 확인한다.
- 후보 선택 상세는 저장하지 않고 동일한 candidate tally와 contest tally만 증가시킨다.

PIN 기반 투표를 구현할 때도 학생 계정 도입 여부, token 만료, 재발급, 감사 로그,
교사 감독 권한은 별도 spec에서 다룬다.

---

## 비밀투표와 이벤트 정책

Election 엔진은 count-only tally를 기본으로 한다.

- `SubmitBallot`은 개별 선택 record를 만들지 않는다.
- voter와 candidate를 연결하는 row나 association을 만들지 않는다.
- 후보 선택 결과는 `ElectionCandidateTally.votes_count` 증가로만 반영한다.
- contest-level abstain은 `ElectionContestTally.abstentions_count` 증가로만 반영한다.
- `ElectionParticipation`은 voter별 처리 상태만 저장한다.
- `ElectionEvent`는 운영 로그이며 선택 로그가 아니다.

`ElectionEvent.metadata`에는 후보 선택 상세를 저장하지 않는다. 금지되는 정보의 예:

- `candidate_id`
- `candidate_ids`
- `election_candidate_id`
- `election_candidate_ids`
- `selected_candidate_id`
- `selected_candidate_ids`
- `selected_candidates`
- `choices`
- `ballot_choices`
- `vote_choices`
- contest별 선택 후보 목록

event metadata에는 voter id, voter number, 진행 전후 voter, count 요약, 운영 사유 같은
운영 정보만 저장한다.

---

## yes_no 제출 미지원 이유

`ElectionContest.vote_method`에는 `yes_no`가 열려 있지만, 현재 `SubmitBallot`은
`yes_no` 제출을 실패 처리한다.

이유:

- 현재 tally 구조는 후보별 득표수와 contest-level 기권 수를 저장한다.
- 찬반투표의 "반대" count를 표현할 별도 구조가 아직 없다.
- 후보 tally를 억지로 찬성표처럼 사용하면 반대표와 무응답/기권의 의미가 흐려진다.
- 따라서 `yes_no` 제출은 tally schema 또는 contest tally 구조를 보강한 뒤 별도
  커밋에서 구현한다.

---

## 기존 구현의 유지, 대체, 정리 후보

현재 `SchoolElection` + `Poll` 기반 구현은 spike이자 기반 검증으로 본다. 삭제는 지금
하지 않는다. 새 Election 엔진 전환 완료 후 정리한다.

### 유지 또는 일반화

- `SchoolElection` -> `Election`
- `SchoolElectionContest` -> `ElectionContest`
- `SchoolElectionCandidate` -> `ElectionCandidate`
- `SchoolElectionClassroomSession` -> `ElectionSession`
- contest/candidate admin 관리 개념
- session 배정 개념
- 다중 contest decision count 개념
- 전체 집계는 closed + integrity OK session만 합산한다는 정책

### 대체

- `SchoolElections::CreateClassroomPoll`
- Poll source link 기반 집계
- Poll-backed classroom session 생성
- `Polls::SubmitBallot`의 선거 제출 구현 위치

### 삭제 또는 정리 후보

- 전교학생회 용도로 추가된 Poll source link
- 전교학생회 Poll start guard
- Poll 기반 `SchoolElections::ResultSummary`
- `PollsController`와 Poll view에 전교학생회 분기를 더 추가하는 방향

위 항목은 지금 삭제하지 않는다. 새 Election 엔진 전환 완료 후 정리한다.

---

## Next Implementation Steps

다음 구현 후보:

- controller/route/UI 연결
- teacher supervised voting screen
- admin session result view
- `IntegrityReport` 또는 tally consistency check
- `Election` 전체 close policy
- `yes_no` tally schema 보강
- `pin_login` operation mode
- 기존 Poll-backed `SchoolElection` flow에서 Election 엔진으로 전환

이번 문서는 위 항목을 구현하지 않는다.

---

## 현재 전환 단계에서 명시하는 금지사항

- 지금 당장 Poll을 삭제하지 않는다.
- 지금 당장 SchoolElection 관련 코드를 삭제하지 않는다.
- 현재 구현된 Election service를 controller/view/route에 바로 연결하지 않는다.
- `IntegrityReport` 없이 전체 집계 정책을 확정하지 않는다.
- `yes_no` 제출을 현재 tally 구조에 억지로 끼워 넣지 않는다.
- 개별 선택 기록 모델을 만들지 않는다.
