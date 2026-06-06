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
- 투표소가 진행 중인지 종료되었는지
- 현재 열려 있는 투표 세션이 무엇인지

선거가 시작된 뒤의 복구 기준은 원본 `VoterGroup`이 아니다.
복구는 선거 시작 시점에 고정된 `ElectionVoter` snapshot과 후속 투표 진행 상태 모델을 기준으로 한다.
원본 `VoterGroup`이나 `VoterSlot`이 변경되어도 이미 시작된 선거의 투표 순서와 투표 대상은 바뀌면 안 된다.

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

## 상태 모델 초안

초기 MVP의 투표 진행 상태 모델명은 `PollingStation`으로 확정한다.

현재 구현된 `ElectionVoter`는 선거용 고정 명단이다.
`ElectionVoter`는 실제 투표 결과나 출석번호 진행 상태를 저장하지 않는다.
후속 진행 상태 모델은 `ElectionVoter`를 참조해 현재 투표 위치와 완료 여부를 복구한다.

### PollingStation

학급 선거가 실제로 진행되는 투표소다.
초기 MVP에서는 `Election` 1개당 `PollingStation` 1개를 둔다.
`PollingStation.current_election_voter_id`는 현재 투표 위치 복구의 기준이다.

현재 구현 컬럼:

- `election:references, null: false, foreign_key: true`
- `current_election_voter:references, null: true, foreign_key to election_voters`
- `status:integer, null: false, default: 0`
- `started_at:datetime`
- `closed_at:datetime`

DB index:

- `[election_id]` unique

상태:

- `active: 0`
- `closed: 10`

`ready` 상태는 두지 않는다.
`Election`이 이미 `draft` 상태를 가지며, `PollingStation`은 `Election`이 `in_progress`가 된 뒤 생성된다.

`PollingStation`은 원본 `VoterGroup` 또는 `VoterSlot`을 직접 참조하지 않는다.
복구와 진행은 `ElectionVoter` snapshot을 기준으로 한다.

현재 구현에서는 `Elections::Start` transaction 안에서 `ElectionVoter` snapshot 생성,
`Election`의 `in_progress` 전이, `PollingStation` 생성을 함께 처리한다.
선거 시작 성공 시 `PollingStation.current_election_voter_id`는 첫 번째 `ElectionVoter`를 가리킨다.
다음 학생 진행, 투표 제출, 후보 선택, 득표수 집계는 아직 구현하지 않았다.

### ElectionVoterParticipation / ElectionVoterReceipt

출석번호별 투표 완료/미참여/기권 기록이다.
구현 모델명은 후속 구현에서 `ElectionVoterParticipation` 또는 `ElectionVoterReceipt` 중 하나로 확정한다.
이 모델은 특정 `ElectionVoter`가 투표 절차상 확정 상태가 되었는지만 저장한다.
후보 선택 결과는 절대 저장하지 않는다.
현재 구현 모델명은 `ElectionVoterParticipation`이다.
`waiting` 상태는 row를 미리 만들지 않고 participation row가 없는 상태로 표현한다.

예상 컬럼:

- `election_voter_id`
- `status`
- `completed_at` 또는 `recorded_at`

중요 원칙:

- A 학생이 투표했다는 기록은 남긴다.
- A 학생이 누구에게 투표했는지는 남기지 않는다.
- participation/receipt에는 `candidate_id`를 저장하지 않는다.
- `election_voter_id`와 `candidate_id`를 직접 연결하지 않는다.
- `PollingStation`은 완료 목록을 저장하지 않는다.

예상 상태:

- `completed`
  - 투표 완료

- `absent`
  - 결석, 조퇴 등으로 미참여

- `abstained`
  - 기권/무투표

- `skipped`
  - 필요한 경우 후속 검토

### VoteSession

특정 voter slot에 대해 열린 1회용 투표 세션이다.
학생 투표 화면과 제출 흐름이 복잡해질 때 후속 검토한다.
초기 구현에서 반드시 먼저 만들 필요는 없다.

예상 상태:

- `open`
  - 현재 투표 가능

- `submitted`
  - 제출 완료

- `cancelled`
  - 제출 전 취소

---

## 복구 시나리오

### 1. 교사 진행 화면 새로고침

상황:

- 교사가 진행 화면에서 새로고침한다.

기대 동작:

- 서버는 polling station 상태를 다시 읽는다.
- `PollingStation.current_election_voter_id`가 있으면 해당 위치를 보여준다.
- 없으면 첫 번째 `ElectionVoter` 또는 다음 미완료 `ElectionVoter`를 계산하는 방향을 검토한다.

---

### 2. 학생 투표 화면 새로고침

상황:

- 학생이 후보 선택 중 화면을 새로고침한다.

DB 상태:

```text
ElectionVoter progress: voting
VoteSession: open
```

기대 동작:

- 같은 `ElectionVoter`의 투표 화면으로 복구한다.
- 아직 제출 전이므로 다시 후보를 선택할 수 있다.

---

### 3. 컴퓨터 재부팅

상황:

- 학생 투표 중 컴퓨터가 꺼지거나 재부팅된다.

기대 동작:

- 교사가 다시 로그인한다.
- 시스템은 DB에서 진행 중인 polling station을 찾는다.
- `PollingStation.current_election_voter_id`가 있으면 해당 학생의 투표 위치로 복구한다.

---

### 4. 교사 세션 만료 또는 로그아웃

상황:

- 교사 로그인 세션이 만료되거나 로그아웃된다.

기대 동작:

- 교사가 다시 로그인하면 본인의 진행 중인 선거 또는 투표소 목록을 보여준다.
- 진행 중인 투표소를 선택하면 `PollingStation.current_election_voter_id` 기준으로 현재 학생 위치를 복구한다.

---

### 5. 투표 완료 요청 중 네트워크 끊김

상황:

- 학생이 `투표 완료`를 눌렀지만 네트워크가 끊겼다.

가능한 결과는 두 가지뿐이어야 한다.

#### 서버 트랜잭션 성공

```text
VoteSession: submitted
ElectionVoterParticipation/Receipt: completed
Tally: 후보 득표 +1
```

복구 시:

- 해당 `ElectionVoter`는 이미 완료 상태로 표시한다.
- 다시 투표시키지 않는다.

#### 서버 트랜잭션 실패

```text
VoteSession: open
ElectionVoterParticipation/Receipt: 변경 없음
Tally: 변화 없음
```

복구 시:

- 해당 `ElectionVoter`의 투표를 다시 진행한다.

중간 상태가 남으면 안 된다.

---

### 6. 투표 완료 버튼 중복 클릭

상황:

- 학생이 투표 완료 버튼을 두 번 누른다.
- 브라우저가 같은 제출 요청을 두 번 보낸다.

기대 동작:

- 첫 번째 요청만 성공한다.
- 두 번째 요청은 이미 제출된 vote session으로 처리한다.
- 득표수는 한 번만 증가한다.

---

### 7. 종료된 투표소에 제출 요청

상황:

- 투표소가 이미 종료되었는데 이전 화면에서 제출 요청이 다시 들어온다.

기대 동작:

- 제출을 거부한다.
- 득표수를 변경하지 않는다.
- 사용자에게 이미 종료된 투표라는 안내를 제공한다.

---

## 트랜잭션 원칙

투표 제출은 반드시 하나의 DB 트랜잭션 안에서 처리한다.

투표 제출 시 함께 처리되어야 하는 작업:

1. vote session이 open 상태인지 확인
2. 현재 투표 대상 `ElectionVoter`가 `PollingStation.current_election_voter_id`와 일치하는지 확인
3. polling station이 active 상태인지 확인
4. 후보가 해당 선거에 속하는지 확인
5. 해당 `ElectionVoter`의 participation/receipt가 아직 완료되지 않았는지 확인
6. 후보별 `CandidateTally.votes_count` 증가
7. participation/receipt를 `completed`로 기록
8. vote session을 submitted로 변경
9. submitted_at 기록

이 중 하나라도 실패하면 전체가 rollback되어야 한다.
`CandidateTally` 증가와 participation/receipt 완료 기록은 함께 성공하거나 함께 실패해야 한다.

### CandidateTally

`CandidateTally`는 후보별 총 득표수만 저장한다.
학생 정보나 개별 투표자의 선택 결과를 저장하지 않는다.

예상 컬럼:

- `election_id`
- `candidate_id`
- `votes_count`

중요 원칙:

- count-only 구조를 기본으로 한다.
- `CandidateTally`는 `ElectionVoter`와 직접 연결하지 않는다.
- `CandidateTally`에는 `election_voter_id`를 저장하지 않는다.
- 후보별 득표 증가 시각을 특정 학생의 `completed_at`과 연결해 추정할 수 있는 화면 흐름을 피한다.
- Rails timestamps가 남더라도 비밀투표를 깨는 근거로 사용하거나 화면에 노출하지 않는다.

---

## 멱등성 원칙

투표 제출은 멱등적이어야 한다.

같은 vote session에 대해 제출 요청이 여러 번 들어와도 최종 결과는 한 번 제출된 것과 같아야 한다.

필요한 장치:

- vote session 상태 확인
- submitted_at 존재 여부 확인
- DB unique constraint 또는 lock
- 트랜잭션 내부 재확인
- 같은 `ElectionVoter`에 대한 participation/receipt 완료 처리 중복 방지
- 같은 제출 요청이 후보별 득표를 두 번 증가시키지 않도록 하는 DB 제약

---

## Lock 원칙

동시에 여러 요청이 들어와도 상태가 꼬이지 않아야 한다.

고려할 방법:

- polling station 또는 진행 상태 row lock
- `ElectionVoter` 진행 row lock
- vote session row lock
- transaction 내부에서 상태 재확인
- DB unique index

예상 제약:

- 한 polling station에 open vote session은 하나만 존재
- 한 `ElectionVoter`에 완료 participation/receipt는 하나만 존재
- submitted vote session은 다시 submitted 처리 불가

---

## DB 제약 후보

구현 시 검토할 제약:

- `election_voters`
  - `[election_id, number]` unique
  - `[election_id, source_voter_slot_id]` unique

- `polling_stations`
  - `[election_id]` unique
  - `current_election_voter_id` foreign key to `election_voters`

- 완료 receipt 또는 제출 모델
  - 같은 `ElectionVoter` 완료 처리 중복 방지
  - `candidate_id` 저장 금지

- `vote_sessions`
  - open 상태 session 중복 방지
  - submitted session 재제출 방지

- `candidate_tallies`
  - `[election_id, candidate_id]` 또는 `[polling_station_id, candidate_id]` unique
  - `ElectionVoter` 직접 참조 금지

정확한 index 설계는 실제 모델 정의 시 확정한다.

---

## 다음 학생 진행 원칙

단순히 현재 번호에 1을 더해 다음 학생으로 넘기는 구조는 위험하다.
새로고침, 뒤로가기, 중복 제출, 미참여 처리 실패 상황에서 실제 완료 상태와 진행 위치가 어긋날 수 있기 때문이다.

다음 학생 진행은 현재 학생이 `completed`, `absent`, `abstained` 등 확정 상태가 된 뒤에만 허용한다.
`PollingStation`은 현재 위치만 저장한다.
완료 목록, 후보 선택 결과, 후보별 득표수는 `PollingStation`에 저장하지 않는다.

명시적으로 배제하는 구조:

- `ElectionVoter`에 `candidate_id` 저장
- `VoteRecord(election_voter_id, candidate_id)` 형태
- `PollingStation`에 후보 선택 결과 저장
- `PollingStation`에 완료 목록 저장
- `CandidateTally`와 `ElectionVoter` 직접 연결
- 학생 `completed_at`과 후보별 득표 증가 정보를 화면에서 직접 연결해 보여주는 구조

---

## 테스트 우선순위

이 문서의 원칙은 테스트로 고정해야 한다.

우선 테스트 대상:

- 투표 중 새로고침해도 같은 `ElectionVoter` 위치로 복구된다.
- 교사 재로그인 후 진행 중인 `ElectionVoter` 위치로 복구된다.
- open vote session은 한 투표소에 하나만 존재한다.
- 같은 vote session을 두 번 제출해도 득표수는 한 번만 증가한다.
- 제출 성공 시 participation/receipt 완료와 tally 증가가 함께 반영된다.
- 제출 실패 시 participation/receipt 완료와 tally 증가가 모두 반영되지 않는다.
- 완료된 `ElectionVoter`는 다시 투표할 수 없다.
- 종료된 polling station에는 추가 투표를 할 수 없다.

---

## 비목표

이 문서는 암호학적 검증이나 외부 감사 수준의 선거 무결성을 다루지 않는다.

초기 목표는 다음이다.

- 교실에서 안정적으로 투표가 진행될 것
- 중단 후 복구될 것
- 중복 제출되지 않을 것
- DB 상태가 꼬이지 않을 것

공식 전교 선거 수준의 감사 가능성, 외부 신뢰, 개표 승인 절차는 별도 문서에서 다룬다.
