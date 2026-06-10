# Privacy and Tally

## 목적

이 문서는 `쑥쑥교실투표`의 비밀투표와 집계 원칙을 정리한다.

초기 MVP는 교실에서 교사 장치 하나로 진행하는 감독형 투표 도구다.
학생 개인 계정, PIN, 개인 단말은 사용하지 않는다.
그렇더라도 출석번호 진행 상태와 실제 후보 선택 결과는 분리해야 한다.

---

## 핵심 원칙

출석번호 진행 상태와 실제 투표 결과는 분리한다.

분리 대상:

- 누가 투표 차례인지
- 누가 투표를 완료했는지
- 누가 미참여 또는 기권 처리되었는지
- 어떤 후보가 몇 표를 받았는지
- 익명 투표 기록을 남긴다면 그 기록이 무엇인지

교사가 보는 진행 상태는 투표 운영과 복구를 위한 정보다.
실제 투표 결과는 후보자별 count 또는 익명 기록으로 별도 관리해야 한다.

---

## PollParticipant와 비밀투표

`PollParticipant`는 선거 시작 시점에 고정된 투표 참여자 명단이다.

`PollParticipant`가 저장하는 정보:

- `poll_id`
- `source_participant_slot_id`
- `number`
- `name`

`PollParticipant`가 저장하지 않는 정보:

- 진행 상태
- 실제 후보 선택 결과
- 후보자별 득표 정보
- 학생이 선택한 `poll_option_id`

현재 투표 진행 상태 모델은 `PollParticipant`를 참조한다.
하지만 실제 표를 저장하는 모델이 `poll_participant_id`와 `poll_option_id`를 직접 함께 저장하면 누가 누구에게 투표했는지 연결될 수 있다.
이 구조는 비밀투표 원칙에 맞지 않을 수 있으므로 신중히 피하거나, 별도의 정책 결정과 감사 목적을 명확히 해야 한다.

`PollProgress`은 초기 MVP의 투표 진행 상태 모델이다.
`PollProgress`은 현재 투표 위치 복구를 위해 `current_poll_participant_id`를 저장하지만, 후보 선택 결과나 득표수, 익명 vote record는 저장하지 않는다.
즉 `PollProgress`은 “지금 누구 차례인가”를 다루고, “그 학생이 누구에게 투표했는가”를 다루지 않는다.

---

## 위험한 설계

다음 구조는 기본 방향으로 삼지 않는다.

```text
VoteRecord
- poll_participant_id
- poll_option_id
```

위 구조는 구현이 단순하지만, 특정 출석번호 학생이 어떤 후보에게 투표했는지 직접 조회할 수 있다.
초기 MVP에서도 교사나 운영자가 개별 학생의 선택 결과를 알 수 있는 구조는 피하는 것이 안전하다.

---

## 현재 집계 방향

현재 MVP는 후보자별 count-only 집계를 사용한다.
`PollParticipation`은 참여자별 완료/미참여/기권 여부만 저장하고, `PollOptionTally`는 후보별 득표수만 저장한다.
두 모델은 같은 transaction에서 함께 처리될 수 있지만 학생별 후보 선택 결과를 직접 연결하지 않는다.

후속 검토 후보:

- `Tally`
- `VoteRecord`
- `Vote`
- `Ballot`

### 후보 A: 후보자별 count 중심 집계

방향:

- 제출 transaction 안에서 후보자별 득표 count를 증가시킨다.
- 동시에 해당 `PollParticipant`의 진행 상태를 완료 처리한다.
- 개별 학생과 후보 선택 결과를 직접 연결하는 row는 남기지 않는다.

장점:

- 비밀투표 원칙에 가장 단순하게 맞출 수 있다.
- 초기 MVP 구현 범위가 작다.

단점:

- 개별 익명 표 기록이 없으므로 사후 검증 정보가 제한된다.
- 장애 복구와 감사 수준을 어디까지 둘지 별도 정책이 필요하다.

### 후보 B: 익명 vote record

방향:

- 개별 표 기록을 남기되 `poll_participant_id`를 저장하지 않는다.
- 후보자와 선거 또는 투표 진행 정보 정도만 연결한다.

장점:

- count 집계보다 감사 가능한 데이터가 많다.
- 개별 학생과 선택 결과를 직접 연결하지 않는다.

단점:

- 중복 제출 방지는 별도 진행 상태/receipt 모델과 transaction으로 보장해야 한다.
- 익명 기록의 보존 범위와 삭제 정책이 필요하다.

### 후보 C: 진행 receipt와 tally 분리

방향:

- 진행 상태 또는 receipt는 `PollParticipant` 기준으로 완료 여부만 저장한다.
- 실제 후보 선택 결과는 tally 또는 익명 vote record에 반영한다.
- 둘은 같은 transaction에서 처리하되, 직접 조회 가능한 식별 연결은 만들지 않는다.

장점:

- 중단 복구와 중복 제출 방지를 다루면서 비밀투표 원칙을 유지할 수 있다.
- 초기 MVP와 후속 감사 요구 사이의 균형을 잡기 좋다.

단점:

- 모델 설계가 count-only 방식보다 복잡하다.

---

## 투표 제출 transaction 원칙

현재 구현에서 투표 제출은 transaction으로 처리한다.

최소 확인:

- 현재 투표 대상 `PollParticipant`가 맞는지 확인한다.
- 해당 학생이 아직 완료 처리되지 않았는지 확인한다.
- 선택한 후보자가 해당 `Poll`의 후보자인지 확인한다.
- 투표 진행 정보 또는 진행 상태가 제출 가능한 상태인지 확인한다.
- 진행 완료 처리와 득표 반영을 같은 transaction에서 처리한다.
- 실패하면 전체 rollback한다.

중복 제출 방지:

- transaction 내부에서 상태를 다시 확인한다.
- 필요한 row에 lock을 건다.
- 같은 `PollParticipant` 완료 처리가 두 번 일어나지 않도록 unique constraint를 검토한다.
- 같은 제출 요청이 후보별 count를 두 번 증가시키지 않도록 DB 제약 또는 idempotency key를 검토한다.

---

## 운영 기록과 비밀투표

`PollEvent`는 운영 이벤트만 기록한다.
`vote_completed` event details에는 `poll_option_id`, `candidate_name`, `candidate_number`를 저장하지 않는다.
후보별 득표 변화 상세도 로그에 남기지 않는다.
학생별 후보 선택은 저장, 표시, 로그 어느 쪽으로도 남기지 않는다.

---

## 후속 검토 사항

다음 항목은 현재 MVP 구현을 대체하지 않고, 감사 요구나 학생 투표 화면이 복잡해질 때 별도로 검토한다.

- 익명 vote record를 함께 둘지
- 진행 완료 receipt 모델을 별도로 둘지
- `VoteSession`을 별도로 둘지
- 중복 제출 방지를 unique constraint, row lock, idempotency key 중 어떤 조합으로 구현할지
- 감사 가능성을 위해 어떤 데이터를 얼마 동안 남길지

초기 기준은 현재 구현된 count-only tally와 participation 분리 구조를 유지하는 것이다.
