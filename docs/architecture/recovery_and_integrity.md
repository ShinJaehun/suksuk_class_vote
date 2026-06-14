# Recovery and Integrity

## 목적

이 문서는 `쑥쑥교실투표`의 가장 중요한 품질 목표인 투표 중단 복구와 데이터 무결성 원칙을 정의한다.

이 프로젝트는 많은 기능보다 안정적인 투표 진행을 우선한다.  
투표 도중 어떤 이유로 화면이 끊기더라도, 교사가 다시 로그인하면 정확히 이전 진행 위치로 돌아올 수 있어야 한다.

---

## 핵심 원칙

브라우저 상태를 믿지 않는다.

투표 진행의 source of truth는 서버 DB다.

다음 상태를 브라우저 JS, localStorage, 세션에만 의존해서는 안 된다.

- 현재 몇 번 학생이 투표 중인지
- 어떤 학생이 투표 완료인지
- 어떤 학생이 미참여 처리되었는지
- 투표 진행 정보가 진행 중인지 종료되었는지
- 현재 복구 기준 참여자가 누구인지

선거가 시작된 뒤의 복구 기준은 원본 `ParticipantGroup`이 아니다.
복구는 선거 시작 시점에 고정된 `PollParticipant` snapshot과 후속 투표 진행 상태 모델을 기준으로 한다.
원본 `ParticipantGroup`이나 `ParticipantSlot`이 변경되어도 이미 시작된 선거의 투표 순서와 투표 대상은 바뀌면 안 된다.
진행 중이거나 종료된 선거는 `PollParticipant` snapshot 기준으로 진행·보존하므로 원본 그룹 이름 수정, 학생 추가/수정/삭제, 원본 명단 삭제를 허용한다.
draft 선거는 아직 원본 `ParticipantGroup`을 참조하므로 해당 원본 명단 삭제를 막는다.
선거 종료 뒤에도 `PollParticipant` snapshot과 선거 시작 당시 그룹명 snapshot이 선거 자료 보존 기준이다.
closed 선거는 `participant_group` 또는 `source_participant_slot` 참조가 비어도 `PollParticipant.number/name` 기준으로 투표 참여자 명단을 유지한다.

---

## 복구 목표

교사가 다시 접속했을 때 시스템은 DB 상태를 기준으로 다음 중 하나를 판단할 수 있어야 한다.

- 아직 투표가 시작되지 않음
- 특정 출석번호 학생이 투표 중
- 마지막 학생까지 처리되었고 투표 종료 전
- 투표 종료 완료
- 결과 확인 가능

예시:

```text
1번 김민준 completed
2번 이서연 completed
3번 박지호 absent
4번 최지우 voting
5번 한서준 waiting
```

이 상태에서 컴퓨터가 재부팅되어도, 교사가 다시 로그인하면 4번 최지우 학생의 투표 위치로 복구되어야 한다.

---

## 현재 상태 모델

초기 MVP의 투표 진행 상태 모델명은 `PollProgress`이다.

현재 구현된 `PollParticipant`는 투표 참여자 고정 명단이다.
`PollParticipant`는 실제 투표 결과나 출석번호 진행 상태를 저장하지 않는다.
투표 진행은 `PollProgress`, `PollParticipation`, `PollOptionTally`가 분리해서 담당한다.

### PollProgress

학급 선거가 실제로 진행되는 투표 진행 정보다.
초기 MVP에서는 `Poll` 1개당 `PollProgress` 1개를 둔다.
`PollProgress.current_poll_participant_id`는 현재 투표 위치 복구의 기준이다.

현재 구현 컬럼:

- `poll:references, null: false, foreign_key: true`
- `current_poll_participant:references, null: true, foreign_key to poll_participants`
- `status:integer, null: false, default: 0`
- `started_at:datetime`
- `closed_at:datetime`

DB index:

- `[poll_id]` unique

상태:

- `active: 0`
- `closed: 10`

`ready` 상태는 두지 않는다.
`Poll`이 이미 `draft` 상태를 가지며, `PollProgress`은 `Poll`이 `in_progress`가 된 뒤 생성된다.

`PollProgress`은 원본 `ParticipantGroup` 또는 `ParticipantSlot`을 직접 참조하지 않는다.
복구와 진행은 `PollParticipant` snapshot을 기준으로 한다.

현재 구현에서는 `Polls::Start` transaction 안에서 `PollParticipant` snapshot 생성,
후보별 `PollOptionTally` 0표 생성, 선거 시작 당시 그룹명 snapshot 저장, `Poll`의 `in_progress` 전이, `PollProgress` 생성을 함께 처리한다.
선거 시작 성공 시 `PollProgress.current_poll_participant_id`는 첫 번째 `PollParticipant`를 가리킨다.
현재 구현에서는 투표 제출, 미참여/기권 처리, 다음 학생 진행, 선거 종료, 후보별 count-only 결과 표시까지 이 구조를 기준으로 진행한다.

### PollParticipation

출석번호별 투표 완료/미참여/기권 기록이다.
이 모델은 특정 `PollParticipant`가 투표 절차상 확정 상태가 되었는지만 저장한다.
후보 선택 결과는 절대 저장하지 않는다.
현재 구현 모델명은 `PollParticipation`이다.
`waiting` 상태는 row를 미리 만들지 않고 participation row가 없는 상태로 표현한다.

현재 역할:

- `completed`: 투표 완료
- `absent`: 미참여
- `abstained`: 기권/무투표
- `recorded_at`: 확정 처리 시각

중요 원칙:

- A 학생이 투표했다는 기록은 남긴다.
- A 학생이 누구에게 투표했는지는 남기지 않는다.
- `PollParticipation`에는 `poll_option_id`를 저장하지 않는다.
- `poll_participant_id`와 `poll_option_id`를 직접 연결하지 않는다.
- `PollProgress`은 완료 목록을 저장하지 않는다.

### PollOptionTally

`PollOptionTally`는 후보별 총 득표수만 저장한다.
학생 정보나 개별 참여자의 선택 결과를 저장하지 않는다.
현재 구현에서는 `Polls::Start` 성공 시 후보자별 `PollOptionTally`가 0표로 생성된다.
`Polls::SubmitVote`는 `PollOptionTally` 증가와 `PollParticipation(completed)` 생성을 하나의 transaction으로 처리한다.
후보자 추가/수정/삭제는 draft 상태에서만 허용해 시작 후 `PollOptionTally` 기준 후보 구성이 바뀌지 않도록 한다.

중요 원칙:

- count-only 구조를 기본으로 한다.
- `PollOptionTally`는 `PollParticipant`와 직접 연결하지 않는다.
- `PollOptionTally`에는 `poll_participant_id`를 저장하지 않는다.
- 후보별 득표 증가 시각을 특정 학생의 `recorded_at`과 연결해 추정할 수 있는 화면 흐름을 피한다.
- Rails timestamps가 남더라도 비밀투표를 깨는 근거로 사용하거나 화면에 노출하지 않는다.

### IntegrityReport / ResumeCurrentVoter

`Polls::IntegrityReport`는 선거 상세 화면의 상태 점검 카드와 운영 요약을 만든다.

현재 점검 대상:

- 진행 중/종료 상태에 맞는 `PollProgress` 존재 여부
- `PollProgress` 상태 불일치
- 현재 참여자 포인터 누락
- 현재 참여자가 다른 선거의 `PollParticipant`를 가리키는 문제
- 후보 수와 `PollOptionTally` 수 불일치
- 다른 선거 후보가 연결된 `PollOptionTally`
- `completed` 수와 후보별 득표 합계 불일치
- 처리 상태 합계가 전체 참여자 수를 초과하는 문제
- 종료된 선거에 미처리 참여자가 남은 문제

상태 점검 카드는 `draft`, `in_progress`, `closed` 모두에서 표시한다.
다만 숫자 운영 요약은 선거 시작 전에는 숨기고, `in_progress`와 `closed`에서만 표시한다.
운영 요약은 전체 참여자 수, 투표 완료 수, 미참여 수, 기권 수, 미처리 수, 후보별 득표 합계를 보여준다.

`Polls::ResumeCurrentVoter`는 매우 제한적인 복구 액션이다.
진행 중인 선거에서 `PollProgress`이 active이고, `current_poll_participant`가 비어 있으며,
다른 무결성 문제가 없고, 미처리 학생이 남아 있을 때만 첫 미처리 학생을 현재 참여자로 지정한다.
이 서비스는 `PollProgress.current_poll_participant_id` 포인터만 복원한다.
`PollParticipation`과 `PollOptionTally`는 변경하지 않는다.

### PollEvent / 운영 기록

`PollEvent`는 선거 운영 이벤트를 DB에 기록한다.
현재 구현된 이벤트:

- `election_started`
- `vote_completed`
- `voter_marked_absent`
- `voter_marked_abstained`
- `current_participant_advanced`
- `current_participant_resumed`
- `election_closed`

각 이벤트는 성공 transaction 안에서 함께 기록된다.
`current_participant_advanced`는 DB에는 남지만 교사용 운영 기록 화면에서는 표시하지 않는다.
교사용 운영 기록 화면은 표시 가능한 최근 10개 이벤트만 보여준다.
선거 단위 이벤트는 actor를 대상으로 표시하고, 학생 처리 이벤트는 `PollParticipant`를 대상으로 표시한다.
운영 기록은 후보 정보를 저장하거나 표시하지 않는다.

### VoteSession

특정 participant slot에 대해 열린 1회용 투표 세션이다.
학생 투표 화면과 제출 흐름이 복잡해질 때 후속 검토한다.
현재 MVP 구현은 `VoteSession` 없이 `PollProgress`, `PollParticipant`, `PollParticipation`, `PollOptionTally`를 기준으로 진행한다.
따라서 `VoteSession`은 현재 필수 구조가 아니라 학생 개별 투표 화면, 토큰, 제출 세션이 복잡해질 때 검토할 후속 항목이다.

---

## 복구 시나리오

### 1. 교사 진행 화면 새로고침

상황:

- 교사가 진행 화면에서 새로고침한다.

기대 동작:

- 서버는 polling station 상태를 다시 읽는다.
- `PollProgress.current_poll_participant_id`가 있으면 해당 위치를 보여준다.
- `PollProgress.current_poll_participant_id`가 없고 제한 조건을 모두 만족하면 `ResumeCurrentVoter`로 첫 미처리 학생을 현재 위치로 복원할 수 있다.

---

### 2. 학생 투표 화면 새로고침

상황:

- 학생이 후보 선택 중 화면을 새로고침한다.

DB 상태:

```text
PollProgress: active
current_poll_participant: 현재 학생
PollParticipation: 없음
```

기대 동작:

- 같은 `PollParticipant`의 투표 화면으로 복구한다.
- 아직 제출 전이므로 다시 후보를 선택할 수 있다.
- 후보 선택 정보는 DB에 저장되어 있지 않으므로 복구하지 않는다.

---

### 3. 컴퓨터 재부팅

상황:

- 학생 투표 중 컴퓨터가 꺼지거나 재부팅된다.

기대 동작:

- 교사가 다시 로그인한다.
- 시스템은 DB에서 진행 중인 polling station을 찾는다.
- `PollProgress.current_poll_participant_id`가 있으면 해당 학생의 투표 위치로 복구한다.

---

### 4. 교사 세션 만료 또는 로그아웃

상황:

- 교사 로그인 세션이 만료되거나 로그아웃된다.

기대 동작:

- 교사가 다시 로그인하면 본인의 진행 중인 선거 또는 투표 진행 정보 목록을 보여준다.
- 진행 중인 투표 진행 정보를 선택하면 `PollProgress.current_poll_participant_id` 기준으로 현재 학생 위치를 복구한다.

---

### 5. 투표 완료 요청 중 네트워크 끊김

상황:

- 학생이 `투표 완료`를 눌렀지만 네트워크가 끊겼다.

가능한 결과는 두 가지뿐이어야 한다.

#### 서버 트랜잭션 성공

```text
PollParticipation: completed
PollOptionTally: 후보 득표 +1
```

복구 시:

- 해당 `PollParticipant`는 이미 완료 상태로 표시한다.
- 다시 투표시키지 않는다.

#### 서버 트랜잭션 실패

```text
PollParticipation: 변경 없음
PollOptionTally: 변화 없음
```

복구 시:

- 해당 `PollParticipant`의 투표를 다시 진행한다.

중간 상태가 남으면 안 된다.

---

### 6. 투표 완료 버튼 중복 클릭

상황:

- 학생이 투표 완료 버튼을 두 번 누른다.
- 브라우저가 같은 제출 요청을 두 번 보낸다.

기대 동작:

- 첫 번째 요청만 성공한다.
- 두 번째 요청은 이미 확정 처리된 현재 참여자로 거부한다.
- 득표수는 한 번만 증가한다.

---

### 7. 종료된 투표 진행 정보에 제출 요청

상황:

- 투표 진행 정보가 이미 종료되었는데 이전 화면에서 제출 요청이 다시 들어온다.

기대 동작:

- 제출을 거부한다.
- 득표수를 변경하지 않는다.
- 사용자에게 이미 종료된 투표라는 안내를 제공한다.

---

## 트랜잭션 원칙

투표 제출은 반드시 하나의 DB 트랜잭션 안에서 처리한다.

현재 투표 제출 시 함께 처리되는 작업:

1. `Poll`이 `in_progress` 상태인지 확인
2. `PollProgress`이 있고 active 상태인지 확인
3. 현재 투표 대상 `PollParticipant`가 있는지 확인
4. 후보가 해당 선거에 속하는지 확인
5. 후보별 `PollOptionTally`가 있는지 확인
6. 해당 `PollParticipant`의 participation이 아직 없는지 확인
7. `PollProgress`, 현재 `PollParticipant`, `PollOptionTally`를 transaction 안에서 lock
8. 후보별 `PollOptionTally.votes_count` 증가
9. `PollParticipation(completed)` 생성

이 중 하나라도 실패하면 전체가 rollback되어야 한다.
`PollOptionTally` 증가와 `PollParticipation` 완료 기록은 함께 성공하거나 함께 실패해야 한다.

---

## 멱등성 원칙

투표 제출은 중복 처리되지 않아야 한다.

같은 현재 참여자에 대해 제출 요청이 여러 번 들어와도 최종 결과는 한 번 제출된 것과 같아야 한다.

필요한 장치:

- DB unique constraint 또는 lock
- 트랜잭션 내부 재확인
- 같은 `PollParticipant`에 대한 participation 완료 처리 중복 방지
- 같은 제출 요청이 후보별 득표를 두 번 증가시키지 않도록 하는 DB 제약

---

## Lock 원칙

동시에 여러 요청이 들어와도 상태가 꼬이지 않아야 한다.

고려할 방법:

- polling station 또는 진행 상태 row lock
- `PollParticipant` 진행 row lock
- transaction 내부에서 상태 재확인
- DB unique index

현재 및 후속 제약:

- 한 `PollParticipant`에 participation은 하나만 존재
- 한 선거 후보에 `PollOptionTally`는 하나만 존재
- 후속 `VoteSession` 도입 시 open/submitted session 중복 방지 제약 검토

---

## 현재 / 후속 DB 제약

현재 유지하거나 후속 구현 시 검토할 제약:

- `poll_participants`
  - `[poll_id, number]` unique
  - `[poll_id, source_participant_slot_id]` unique는 원본 slot 링크가 남아 있을 때 중복 snapshot을 막기 위한 제약
  - 원본 `ParticipantSlot` 삭제 시 `source_participant_slot_id`는 `nil`이 될 수 있음

- `poll_progresses`
  - `[poll_id]` unique
  - `current_poll_participant_id` foreign key to `poll_participants`

- `poll_participations`
  - 같은 `PollParticipant` 완료 처리 중복 방지
  - `poll_option_id` 저장 금지

- `poll_option_tallies`
  - `[poll_id, poll_option_id]` unique
  - `PollParticipant` 직접 참조 금지

- `vote_sessions`
  - 현재 미구현
  - 도입 시 open 상태 session 중복 방지와 submitted session 재제출 방지 제약 검토

---

## 다음 학생 진행 원칙

단순히 현재 번호에 1을 더해 다음 학생으로 넘기는 구조는 위험하다.
새로고침, 뒤로가기, 중복 제출, 미참여 처리 실패 상황에서 실제 완료 상태와 진행 위치가 어긋날 수 있기 때문이다.

다음 학생 진행은 현재 학생이 `completed`, `absent`, `abstained` 등 확정 상태가 된 뒤에만 허용한다.
`PollProgress`은 현재 위치만 저장한다.
완료 목록, 후보 선택 결과, 후보별 득표수는 `PollProgress`에 저장하지 않는다.

명시적으로 배제하는 구조:

- `PollParticipant`에 `poll_option_id` 저장
- `PollParticipation`에 `poll_option_id` 저장
- `PollOptionTally`에 `poll_participant_id` 저장
- `VoteRecord(poll_participant_id, poll_option_id)` 형태
- `PollProgress`에 후보 선택 결과 저장
- `PollProgress`에 완료 목록 저장
- `PollOptionTally`와 `PollParticipant` 직접 연결
- 학생 `recorded_at`과 후보별 득표 증가 정보를 화면에서 직접 연결해 보여주는 구조

`IntegrityReport`와 `ResumeCurrentVoter`도 학생별 후보 선택 정보를 다루지 않는다.
`IntegrityReport`는 후보별 득표 합계와 `completed` 수의 숫자 비교만 수행한다.
`ResumeCurrentVoter`는 현재 참여자 포인터만 복원한다.
학생별 후보 선택은 저장, 표시, 로그 어느 쪽으로도 남기지 않는다.

---

## 복구 가능 범위와 비복구 범위

현재 구현에서 복구 가능한 것:

- 브라우저 새로고침
- 교사 재로그인
- 서버 재시작 후 DB 상태 기준 재진입
- `current_poll_participant`가 nil이고, 다른 무결성 문제가 없으며, 미처리 학생이 남아 있는 경우 첫 미처리 학생으로 재개

현재 자동 복구하지 않는 것:

- `poll_option_tallies` 수 불일치
- `completed` 수와 `votes_count` 합계 불일치
- `current_poll_participant`가 다른 election의 voter를 가리키는 경우
- `closed` 상태인데 미처리 학생이 남은 경우
- `poll_progress` 자체가 없는 경우
- `poll_progress` 상태 불일치
- 후보별 득표 재계산

위 문제는 상태 점검 카드에서 확인 대상으로 표시하되, 자동 수정하지 않는다.
추가 복구 액션은 비밀투표와 무결성에 영향을 줄 수 있으므로 별도 설계 후 도입한다.

---

## 테스트 우선순위

이 문서의 원칙은 테스트로 고정해야 한다.

우선 테스트 대상:

- 투표 중 새로고침해도 같은 `PollParticipant` 위치로 복구된다.
- 교사 재로그인 후 진행 중인 `PollParticipant` 위치로 복구된다.
- 같은 현재 참여자에 대해 두 번 제출해도 득표수는 한 번만 증가한다.
- 제출 성공 시 `PollParticipation` 완료와 tally 증가가 함께 반영된다.
- 제출 실패 시 `PollParticipation` 완료와 tally 증가가 모두 반영되지 않는다.
- 완료된 `PollParticipant`는 다시 투표할 수 없다.
- 종료된 polling station에는 추가 투표를 할 수 없다.
- 후속 `VoteSession` 도입 시 open/submitted session 중복 방지 테스트를 별도로 추가한다.

---

## 미구현 / 후속 검토

- 고도화된 감사 로그 / 외부 감사 기능
- `IntegrityReport` issue code 도입
- 시작 전 checklist / freeze UX 고도화
- 결과 snapshot / 인쇄 또는 export
- 추가 복구 액션
- `VoteSession` 후속 검토

---

## 비목표

이 문서는 암호학적 검증이나 외부 감사 수준의 선거 무결성을 다루지 않는다.

초기 목표는 다음이다.

- 교실에서 안정적으로 투표가 진행될 것
- 중단 후 복구될 것
- 중복 제출되지 않을 것
- DB 상태가 꼬이지 않을 것

공식 전교 선거 수준의 감사 가능성, 외부 신뢰, 개표 승인 절차는 별도 문서에서 다룬다.
