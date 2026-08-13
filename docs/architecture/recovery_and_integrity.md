# Recovery and Integrity

## 목적

이 문서는 `쑥쑥교실투표`의 가장 중요한 품질 목표인 투표 도중 장애 복구와 데이터 무결성 원칙을 정의한다.

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
- 투표 진행 정보가 진행 중인지, 중단되었는지, 종료되었는지
- 현재 복구 기준 참여자가 누구인지

선거가 시작된 뒤의 복구 기준은 원본 `ParticipantGroup`이 아니다.
복구는 선거 시작 시점에 고정된 `PollParticipant` snapshot과 후속 투표 진행 상태 모델을 기준으로 한다.
원본 `ParticipantGroup`이나 `ParticipantSlot`이 변경되어도 이미 시작된 선거의 투표 순서와 투표 대상은 바뀌면 안 된다.
진행 중이거나 종료된 선거는 `PollParticipant` snapshot 기준으로 진행·보존하므로 원본 그룹 이름 수정, 학생 추가/수정/삭제, 원본 명단 삭제를 허용한다.
draft 선거는 아직 `PollParticipant` snapshot이 없고 원본 `ParticipantGroup`을 직접 참조한다.
draft 상태에서도 원본 그룹 이름 수정과 `ParticipantSlot` 학생 추가/수정/삭제는 허용한다.
다만 draft 선거가 현재 참조 중인 원본 `ParticipantGroup` 자체 삭제는 준비 중인 `Poll`이 필수 명단 설정을 잃지 않게 막는다.
이 단락의 중단·삭제 정책은 교사 주도 일반 `Poll`에 대한 것이다.
일반 `Poll` 중단 뒤에는 진행 중간 데이터를 보존 대상으로 보지 않는다.
`stopped` Poll은 결과 확정 상태가 아니며 복구 또는 재개 대상이 아니다.
`stopped` Poll을 삭제할 때는 `poll_progress`가 `poll_participants`를 참조하는 FK 문제를 피하기 위해 `poll_progress`를 먼저 정리한다.
전교임원선거의 stopped `ElectionSession`은 이와 달리 감사 이력으로 보존한다.
선거 종료 뒤에는 `PollParticipant` snapshot과 선거 시작 당시 그룹명 snapshot이 선거 자료 보존 기준이다.
closed 선거는 `participant_group` 또는 `source_participant_slot` 참조가 비어도 `PollParticipant.number/name` 기준으로 투표 참여자 명단을 유지한다.
보관 전 closed 선거는 삭제 또는 `archived_at` 기반 보관을 선택할 수 있다.
보관된 closed 선거는 기록으로 남기기로 한 상태이므로 삭제하지 않는다.

---

## 복구 목표

교사가 다시 접속했을 때 시스템은 DB 상태를 기준으로 다음 중 하나를 판단할 수 있어야 한다.

- 아직 투표가 시작되지 않음
- 특정 출석번호 학생이 투표 중
- 투표가 중단되어 재개하지 않음
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
투표 시작 직후 ballot은 locked 상태이며, 교사가 첫 학생에 대해 `open_current_participant_ballot`을 실행해야 열린다.
두 번째 이후 학생은 `advance_current_participant`가 다음 `PollParticipant`로 이동하면서 ballot을 열린 상태로 둔다.
학생이 후보 선택 또는 기권을 완료하면 ballot은 다시 locked 상태가 된다.

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
- 기권은 학생의 의사표시이므로 운영 화면에서 별도 항목으로 드러내지 않는다.
- 표시용 투표 완료 수는 `completed + abstained`로 계산한다.
- 후보별 tally와 종료 직전 무결성 gate에서 쓰는 `completed` 수는 후보 선택 완료 수로 유지한다.

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

상태 점검 카드는 `draft`, `in_progress`, `stopped`, `closed` 모두에서 표시한다.
다만 숫자 운영 요약은 선거 시작 전에는 숨기고, `in_progress`, `stopped`, `closed`에서 표시한다.
운영 요약은 전체 참여자 수, 투표 완료 수, 미참여 수, 대기 수를 보여준다.
화면 표시용 투표 완료 수는 `completed + abstained`이며, 대기 수는 participation이 없는 `PollParticipant` 기준이다.
기권 항목은 별도로 표시하지 않는다.
학생 submit, 기권, 미참여, 다음 투표자 진행이 성공하면 상태 점검 카드도 Turbo로 갱신되어 오래된 요약 HTML이 남지 않도록 한다.

### Admin Election 운영 무결성

Admin `Election`은 여러 학급 `ElectionSession`을 묶는 운영 단위다.
admin이 `Election`을 시작하면 parent 상태만 `in_progress`로 바뀌며, 각 학급 세션은 교사 흐름에서 별도로 시작한다.

`Election` 시작 조건:

- `Election`이 `draft` 상태여야 한다.
- 학급 `ElectionSession`이 1개 이상 배정되어야 한다.
- `ElectionContest`가 1개 이상 있어야 한다.
- 모든 `ElectionContest`에 `ElectionCandidate`가 1명 이상 있어야 한다.

`Election`이 시작된 뒤에는 결과 무결성을 위해 구성을 변경하지 않는다.
학급 세션 추가/삭제와 후보자 등록/수정/삭제는 서버측 guard에서 차단하며,
admin 상세 화면에서도 해당 UI를 숨기고 읽기 전용 목록으로 표시한다.
학급 세션 삭제는 parent `Election`이 `draft`이고, 삭제 대상 세션이 `draft`이며,
같은 `Election` 안에 draft가 아닌 세션이 하나도 없을 때만 허용한다.

`ElectionSession` 종료는 parent `Election`을 자동 종료하지 않는다.
중단 이력이 아닌 세션이 1개 이상이고 모두 `closed`이면 admin 화면에서 명시적 `선거 종료`를 허용한다.
admin이 종료를 확정하기 전까지 parent `Election`은 `in_progress`를 유지한다.

Admin 결과 집계는 parent `Election`이 `closed` 된 뒤 `closed` `ElectionSession`의 `ElectionCandidateTally`와
`ElectionContestTally`만 읽어 합산한다.
결과 페이지의 학급별 목록도 `closed` 세션만 표시한다.
draft/in_progress/stopped 세션은 결과 합산과 results 화면에서 제외하고,
stopped 이력은 Admin 선거 상세에서 확인한다.

후보자 사진은 Admin `ElectionCandidate`의 후보 식별 보조 자료이며 결과/집계/검산에는 사용하지 않는다.
사진은 선거 진행 중 사용하는 임시 자료로 보고, parent `Election`이 `closed`가 된 뒤 해당 Election 후보자들의
사진 attachment/blob를 purge하는 기능을 향후 별도 작업으로 검토한다.
이때 `ElectionCandidate` record, 후보자 이름/기호/소속, tally, result, event log는 유지하고
사진 attachment/blob만 삭제하는 방향을 우선 검토한다.

Admin `Election` 상세 화면은 Turbo Stream `admin_overview`를 구독한다.
학급 세션 시작/종료 뒤에는 `admin_summary`, `admin_status_report`, `admin_sessions` 영역을 replace해
상단 상태, 상태점검 카드, 학급 세션 목록이 같은 DB 상태를 기준으로 보이게 한다.

### ElectionSession 화면 복구

전교임원선거 교사 화면은 `ElectionProgress`와 `ElectionParticipation`을 source of
truth로 사용한다.

- 교사 진행 영역은 Turbo Stream broadcast를 우선 사용한다.
- broadcast를 놓치거나 WebSocket이 재연결되어도 2~3초 polling으로 해당 진행
  Turbo Frame을 다시 읽는다.
- polling은 교사 진행 영역에만 적용하며 학생 ballot이나 Admin summary에는 붙이지 않는다.
- 새로고침, 재로그인, 브라우저 재실행, 컴퓨터 재부팅 뒤에도 DB의 current voter,
  ballot state, participation을 기준으로 화면을 복구한다.

Ballot 창은 세션별 named window를 사용한다. 같은 교사 화면에서 반복해서 열면 새
창을 만들지 않고 기존 창을 focus한다. Ballot 창의 `pagehide`는 서버의 ballot
상태를 잠그며, 창을 닫은 뒤 다시 열면 정상 ballot 화면을 새로 열 수 있다.

클라이언트의 창 reference는 보조 장치일 뿐이다. 제출 시 서버는 session이
`in_progress`인지, 현재 voter가 일치하는지, ballot이 열렸는지, participation이
pending인지 다시 검증한다. 오래 열린 이전 ballot이나 중복 요청은 이 검증으로
거부하고 tally를 변경하지 않는다.

`stopped` `ElectionSession`은 복구하거나 재개하지 않는다. 당시 voter,
participation, tally, progress, event를 보존하고 read-only 상세만 제공한다.
재투표는 기존 세션을 `stopped` 이력으로 남기고 replacement `draft` 세션에서
새로 시작한다. 자세한 운영 정책은 `docs/specs/school_council_election.md`를 따른다.

### PollSession runtime 복구와 terminal 일관성

PollSession 교사 operation 화면과 학생 ballot 화면은 ActionCable/Turbo Stream을 primary 갱신
수단으로 사용한다. 연결 단절이나 broadcast 누락에 대비한 10초 간격 polling은 DB 상태로 화면을
수렴시키는 safety net이며, 정상 상태에는 `204 No Content`를 반환하고 stale 또는 terminal 상태일
때만 필요한 작은 Turbo Stream 영역을 교체한다. 투표 중인 ballot form 전체는 교체하지 않아 학생이
선택 중인 값을 잃지 않게 한다.

학생 ballot recovery는 화면의 Session·Poll·ballot·현재 참여자·참여 완료·현재 Contest fingerprint를
서버 상태와 비교한다. 일치하면 `204`로 끝내고, Cable 갱신을 놓쳐 의미가 달라진 경우에만 ballot
frame을 교체한다. 따라서 선택 중 form의 주기적 교체 없이 locked 전환과 다음 참여자 진행에 수렴한다.

Realtime payload 렌더 실패는 투표 transaction을 되돌리지 않는다. 실패 로그에는 Poll/Session,
broadcast 종류, 예외 class와 최초 애플리케이션 위치만 남기며 학생·선택 내용과 예외 message는 남기지 않는다.

페이지가 hidden이면 polling callback만 건너뛰지 않고 interval timer 자체를 중단한다. 다시 visible이
되면 즉시 한 번 확인하고 interval을 재시작한다. 따라서 WebSocket이 끊긴 상태에서 오래 열린 교사
시작 화면이나 학생 제출 화면도 서버의 terminal 상태로 안전하게 복귀한다.

전교투표 전체 종료·중단은 관련 operation과 ballot 화면을 terminal 상태로 갱신한다. 원본 종료로
실행 중인 child Test Poll을 강제 중단할 때도 ballot을 잠그고 terminal 상태를 broadcast하며, 이미
closed인 Session의 상태와 결과는 변경하지 않는다. 화면의 실시간 전달 여부와 관계없이 DB 상태가
최종 source of truth다.

`Polls::ResumeCurrentVoter`는 매우 제한적인 복구 액션이다.
진행 중인 선거에서 `PollProgress`이 active이고, `current_poll_participant`가 비어 있으며,
다른 무결성 문제가 없고, 미처리 학생이 남아 있을 때만 첫 미처리 학생을 현재 참여자로 지정한다.
이 서비스는 `PollProgress.current_poll_participant_id` 포인터만 복원한다.
`PollParticipation`과 `PollOptionTally`는 변경하지 않는다.
`stopped` 선거에는 적용하지 않는다.

`Polls::IntegrityReport`는 운영/점검용 report다.
상세 화면에서 현재 상태를 설명하고 제한적인 재개 가능 여부를 판단하는 데 사용하지만, 그 자체가 `closed` 전환을 수행하거나 막는 transaction gate는 아니다.
`Polls::Close`는 종료 전환 직전에 별도의 내부 무결성 gate를 실행한다.

### PollEvent / 운영 기록

`PollEvent`는 선거 운영 이벤트를 DB에 기록한다.
현재 구현된 이벤트:

- `election_started`
- `vote_completed`
- `voter_marked_absent`
- `voter_marked_abstained`
- `current_participant_advanced`
- `current_participant_resumed`
- `election_stopped`
- `election_closed`

각 이벤트는 성공 transaction 안에서 함께 기록된다.
`current_participant_advanced`는 DB에는 남지만 교사용 운영 기록 화면에서는 표시하지 않는다.
교사용 운영 기록 화면은 표시 가능한 최근 10개 이벤트만 보여준다.
선거 단위 이벤트는 actor를 대상으로 표시하고, 학생 처리 이벤트는 `PollParticipant`를 대상으로 표시한다.
운영 기록은 후보 정보를 저장하거나 표시하지 않는다.
`PollEvent.details`에도 선택지 id, 이름, 번호를 저장하지 않는다.

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

### 8. 중단된 투표 진행 정보에 제출 요청

상황:

- 투표가 중단되었는데 이전 화면에서 제출 요청이 다시 들어온다.

기대 동작:

- 제출을 거부한다.
- 득표수를 변경하지 않는다.
- 중단된 투표라는 안내를 제공한다.

`stopped`는 복구/재개 대상이 아니므로 현재 참여자 포인터를 복원하지 않는다.

---

## 트랜잭션 원칙

투표 제출은 반드시 하나의 DB 트랜잭션 안에서 처리한다.

현재 투표 제출 시 함께 처리되는 작업:

1. `Poll`이 `in_progress` 상태인지 확인
2. `PollProgress`이 있고 active 상태인지 확인
3. 현재 투표 대상 `PollParticipant`가 있는지 확인
4. 후보가 해당 선거에 속하는지 확인
5. 후보별 `PollOptionTally`가 있는지 확인
6. 요청의 `current_poll_participant_id`가 현재 참여자와 일치하는지 확인
7. 해당 `PollParticipant`의 participation이 아직 없는지 확인
8. `PollProgress`, 현재 `PollParticipant`, `PollOptionTally`를 transaction 안에서 lock
9. lock 이후 `PollProgress.current_poll_participant`를 다시 읽어 요청 id와 일치하는지 재확인
10. 후보별 `PollOptionTally.votes_count` 증가
11. `PollParticipation(completed)` 생성

이 중 하나라도 실패하면 전체가 rollback되어야 한다.
`PollOptionTally` 증가와 `PollParticipation` 완료 기록은 함께 성공하거나 함께 실패해야 한다.

기권/미참여 처리를 담당하는 `Polls::RecordParticipationOutcome`도 같은 current participant 재검증 원칙을 따른다.
후보별 tally는 증가시키지 않고 `PollParticipation(abstained|absent)`만 transaction 안에서 생성한다.
학생 투표 화면에서는 기권만 가능하고 미참여 처리는 교사 투표 정보 화면에서만 수행한다.
현재 학생이 기권하면 화면 표시는 투표 완료와 동일하게 처리한다.

다음 학생 진행과 투표 종료도 stale 운영 요청을 방어한다.
`Polls::AdvanceCurrentParticipant`와 `Polls::Close`는 요청의 `current_poll_participant_id`를 받고,
transaction 안에서 `PollProgress`를 lock한 뒤 DB의 현재 참여자를 다시 읽어 요청 id와 비교한다.
오래 열린 화면, 뒤로가기 화면, 늦게 도착한 요청처럼 current participant가 달라진 요청은 실패 처리한다.
이때 다음 참여자 포인터 변경, 종료 전환, `PollEvent` 생성은 수행하지 않는다.

### 종료 직전 무결성 gate

`Polls::Close`는 `closed` 상태로 전환하기 직전에 transaction 내부에서 숫자 일관성을 검증한다.
이 gate는 `Polls::IntegrityReport`와 같은 문제를 일부 다루지만, 목적은 운영 표시가 아니라 종료 전환을 막는 안전장치다.

현재 검증 항목:

- `completed`, `absent`, `abstained` 합계가 전체 `PollParticipant` 수와 일치
- `completed` 수와 `PollOptionTally.votes_count` 합계 일치
- `PollOption` 수와 `PollOptionTally` row 수 일치
- 다른 투표의 `PollOption`에 연결된 `PollOptionTally` 없음
- 음수 `votes_count` 없음

검증에 실패하면 `Poll`은 `in_progress`, `PollProgress`는 active 상태로 남는다.
`poll_closed` 이벤트도 생성하지 않는다.
이 검증은 참여자별 선택을 저장하거나 비교하지 않고, count-only 숫자 일관성만 확인한다.

---

## 멱등성 원칙

투표 제출은 중복 처리되지 않아야 한다.

같은 현재 참여자에 대해 제출 요청이 여러 번 들어와도 최종 결과는 한 번 제출된 것과 같아야 한다.

필요한 장치:

- DB unique constraint 또는 lock
- 트랜잭션 내부 재확인
- 같은 `PollParticipant`에 대한 participation 완료 처리 중복 방지
- 같은 제출 요청이 후보별 득표를 두 번 증가시키지 않도록 하는 DB 제약
- 화면 요청이 본 현재 참여자와 lock 이후 DB의 현재 참여자가 같은지 확인하는 stale 요청 방어

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
- 제출, 기권, 미참여, 다음 학생 진행, 종료는 lock 이후 현재 참여자를 다시 확인
- 후속 `VoteSession` 도입 시 open/submitted session 중복 방지 제약 검토

PollSession runtime의 동일 Session 대상 주요 동시 작업은 `PollSession`을 먼저 잠그고 필요한
`PollProgress`를 뒤에 잠근다. Session 종료와 ballot 제출은 `Session -> Progress`, 전교투표 중단은
`parent Poll -> current PollSessions(id 순) -> Progress` 순서를 따른다. 전교투표의 current Session
scope는 LEFT OUTER JOIN을 포함하므로 직접 `FOR UPDATE`하지 않고, 먼저 id를 선정한 뒤 base
`PollSession` relation을 id 순으로 잠근다. 이 순서는 PostgreSQL outer join 잠금 제한을 피하고,
재투표의 `Poll -> source Session` 순서와도 parent Poll 경계를 기준으로 일관된다.
전교투표 시작도 `Poll -> current PollSessions(id 순) -> Classrooms(id 순)`으로 잠근 뒤,
학급·담당 교사·Session 운영자의 활성 상태와 담당 교사/운영자 일치를 최종 확인한다.
초안에서는 구조 변경을 허용하되 이 관계가 어긋난 전교투표는 시작하지 않는다.

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
`Polls::Close`의 종료 직전 gate도 count-only 숫자 일관성만 확인한다.
`ResumeCurrentVoter`는 현재 참여자 포인터만 복원한다.
학생별 후보 선택은 저장, 표시, 로그 어느 쪽으로도 남기지 않는다.
`PollEvent.details`에도 선택지 id, 이름, 번호를 남기지 않는다.

---

## 복구 가능 범위와 비복구 범위

현재 구현에서 복구 가능한 것:

- 브라우저 새로고침
- 교사 재로그인
- 서버 재시작 후 DB 상태 기준 재진입
- `current_poll_participant`가 nil이고, 다른 무결성 문제가 없으며, 미처리 학생이 남아 있는 경우 첫 미처리 학생으로 재개
- 전교임원선거 교사 진행 화면의 broadcast 누락 후 polling 복구
- ballot 창 종료 통지 뒤 같은 학급 ballot 창 재열기
- `ElectionProgress` 기준 refresh/relogin/reboot 복구

위 복구 가능 범위는 `in_progress` 선거에만 적용한다.
`stopped` Poll과 `stopped` ElectionSession은 진행 중단 상태이며 재시작하지 않는다.
일반 학급 Poll의 삭제 정책과 달리 전교임원선거 stopped 세션은 감사 이력으로
삭제하지 않는다. Teacher 목록 숨김도 timestamp만 기록하며 세션 데이터는 보존한다.

현재 자동 복구하지 않는 것:

- `poll_option_tallies` 수 불일치
- `completed` 수와 `votes_count` 합계 불일치
- `current_poll_participant`가 다른 election의 voter를 가리키는 경우
- `closed` 상태인데 미처리 학생이 남은 경우
- `poll_progress` 자체가 없는 경우
- `poll_progress` 상태 불일치
- 후보별 득표 재계산
- `stopped` 선거 재시작

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
- `stopped` 재시작은 현재 도입하지 않음
- 보관 해제와 종료 후 30일 자동 보관

---

## 비목표

이 문서는 암호학적 검증이나 외부 감사 수준의 선거 무결성을 다루지 않는다.

초기 목표는 다음이다.

- 교실에서 안정적으로 투표가 진행될 것
- 투표 도중 장애 후 복구될 것
- 중복 제출되지 않을 것
- DB 상태가 꼬이지 않을 것

공식 전교 선거 수준의 감사 가능성, 외부 신뢰, 개표 승인 절차는 별도 문서에서 다룬다.
