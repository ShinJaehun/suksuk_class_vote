# Poll Classroom·Student 전환 계획

## 1. 목적과 범위

이 문서는 `Poll`의 명단 원본을 `ParticipantGroup`·`ParticipantSlot`에서
`Classroom`·`Student`로 전환하는 기준이다. 시작 전에는 Classroom의 active Student를
사용하고, 시작 후에는 `PollParticipant` snapshot으로 진행·인원·결과를 고정한다.

목표는 기존 Poll ID와 진행·집계 기록을 손상하지 않고 신규 경로를 전환한 뒤,
Election과 Poll 양쪽의 의존을 모두 제거하여 `ParticipantGroup`·`ParticipantSlot` table을
삭제할 수 있게 하는 것이다. 현재 PollSession foundation, 실행 기록의 nullable 연결, Poll 정의와
최초 draft PollSession 생성 화면과 `Polls::StartSession` backend, 전용 nested POST start route와
목록 시작 UI까지 연결됐다. 기존 ParticipantGroup Poll start/runtime은 변경하지 않는다.

## 2. 현재 구조

PollSession foundation은 존재하지만 기존 runtime에서 `Poll` 하나가 투표 정의와 한 번의 학급
실행을 모두 담당한다. 실행 기록에는 nullable `poll_session_id`가 추가됐지만 legacy runtime은
이를 비운 채 `poll_id`로 기록한다. 또한 개인별 선택지를 저장하는 `PollVote` 모델은 없다. 비밀투표를 위해
참여 상태와 선택지별 count-only tally를 분리해 저장한다.

| 모델 | 현재 책임과 association | 상태·제약·삭제 |
| --- | --- | --- |
| `Poll` | `user`, optional `participant_group`; contests, options, participants, tallies, events, progress 소유 | `draft/in_progress/closed/stopped`; draft·stopped·미보관 closed만 삭제 가능; 삭제 시 하위 실행 기록 cascade |
| `PollSession` | `poll`, `classroom`, 실제 `operator`, 학급·운영자 이름 snapshot | foundation만 존재; `draft/in_progress/closed/stopped`; 같은 Poll/Classroom의 active 실행 unique; runtime 미사용 |
| `ParticipantGroup` | `user`, optional `school`, many slots/polls | Poll은 `teacher_personal` group만 생성 UI에서 선택; draft Poll이 사용 중이면 group 삭제 차단 |
| `ParticipantSlot` | group의 번호·이름 명단 row | group 내 number unique; PollParticipant의 optional source, slot 삭제 시 FK `ON DELETE SET NULL` |
| `PollParticipant` | Poll 시작 시 number·name snapshot, optional `source_participant_slot`, optional `poll_session` | legacy poll 또는 PollSession 안에서 number unique; participation/event/progress의 실행 기준 |
| `PollParticipation` | participant의 확정 상태 | `completed/absent/abstained`; participant당 1개, `recorded_at` 존재 |
| `PollProgress` | current participant, 시작·종료 시각, ballot lock, optional `poll_session` | `active/closed`, `ballot_locked/ballot_open`; legacy poll 또는 PollSession당 1개 |
| `PollOption` / `PollContest` | 선택지와 항목 정의 | contest 내 option number unique, poll 내 contest position unique |
| `PollOptionTally` | option별 표 수 | poll·option unique, 0 이상 |
| `PollContestTally` | contest별 기권 수 | poll·contest unique, 0 이상 |
| `PollEvent` | Poll/participant 운영 event | 선택지 정보를 details에 저장하지 않음 |

DB의 주요 제약은 다음과 같다.

- `polls.participant_group_id`는 nullable이고 FK 삭제 시 null로 바뀐다. source check constraint는 없다.
- `poll_participants`의 `(poll_id, number)`와
  `(poll_id, source_participant_slot_id)`에 unique index가 있다. nullable source는 여러 row에서 null일 수 있다.
- `poll_participations.poll_participant_id`, `poll_progresses.poll_id`,
  `poll_option_tallies(poll_id, poll_option_id)`, `poll_contest_tallies(poll_id, poll_contest_id)`는 unique다.
- 같은 ParticipantGroup으로 여러 Poll을 만드는 것을 금지하는 index는 없다.

## 3. 현재 Poll 실행 흐름

1. **생성**: `PollsController#new/#create`가 `ParticipantGroupPolicy::Scope`를 적용한
   `teacher_personal` group 중 slot이 하나 이상인 group을 선택한다. strong parameter는
   `participant_group_id`를 받는다. `app/views/polls/new.html.erb`도 group과 slot 수를 표시한다.
2. **준비**: `Poll#readiness_voter_count`, `#startable_by_configuration?`와
   `app/views/polls/_readiness.html.erb`, `_poll_participants.html.erb`가 group의 현재 slot을 읽는다.
   draft에서는 group 명단 수정 링크도 노출한다.
3. **시작/snapshot**: `Polls::Start#participant_slots/#create_snapshot`이 slot을 number 오름차순으로
   `PollParticipant(number, name, source_participant_slot_id)`로 복사한다. 같은 transaction에서
   option/contest tally, `PollProgress`, `poll_started` event를 만들고 Poll을 in_progress로 바꾼다.
   `participant_group_name_snapshot` 또한 이 때 저장한다. 현재 service는 transaction은 사용하지만
   Poll row에 명시적 `with_lock`/`lock!`을 수행하지 않는다.
4. **진행**: `Polls::OpenCurrentParticipantBallot`, `SubmitVote`,
   `RecordParticipationOutcome`, `RecordNextParticipantAbsent`, `AdvanceCurrentParticipant`가
   `PollProgress`, `PollParticipant`, `PollParticipation`을 사용한다. 시작 후 slot을 다시 읽지 않는다.
   `Polls::SubmitBallot` service와 spec도 존재하지만 현재 controller/route에서 호출하는 경로는
   확인되지 않았다.
5. **복구와 중단**: `Polls::ResumeCurrentParticipant`는 in_progress Poll의 current pointer가 없을 때
   첫 미처리 snapshot participant를 재지정하는 복구다. stopped Poll을 재시작하거나 replacement를
   만드는 기능은 없다. `Polls::Stop`은 in_progress를 stopped로 바꾸고 event를 남기며,
   stopped Poll은 UI에서 재시작 불가로 표시된다.
6. **종료·결과**: `Polls::Close`가 모든 participant의 처리와 tally 무결성을 검증하고
   Poll/Progress를 closed로 변경한다. `Polls::ResultSummary`와 `IntegrityReport`는
   PollParticipant/Participation과 option/contest tally만 사용하며 group/slot을 읽지 않는다.
7. **목록·보관**: `PollsController#voter_counts_for`는 draft는 slot 수, 시작된 Poll은 snapshot 수를
   표시한다. `index`/`archived` view는 `participant_group_name_snapshot` 또는 현재 group 이름을 쓴다.
   closed Poll은 archive할 수 있고, archived closed Poll은 삭제할 수 없다.

## 4. snapshot 보존 계약

명단 원본과 실행 기록을 다음처럼 분리한다.

```text
현재 명단 원본       실행 snapshot             비밀 결과
ParticipantGroup     PollParticipant           PollOptionTally
└─ ParticipantSlot     ├─ number/name             PollContestTally
                       └─ PollParticipation      PollEvent
```

`PollParticipant` 자체가 번호와 이름을 저장하므로, 시작 후 진행·결과는 원본 slot이
변경되거나 삭제되어도 달라지지 않는다. `spec/requests/polls_spec.rb`은 source slot 이름을
변경해도 snapshot이 유지되고, group이 삭제된 closed Poll도 저장된 group name과
participant snapshot으로 표시됨을 검증한다.

`PollParticipation`에는 pending 상태가 없다. 미처리 participant는 participation row가 없는
상태로 표현하고, 확정된 뒤에만 completed/absent/abstained row를 만든다. 개인별
선택지는 저장하지 않고 `PollOptionTally`/`PollContestTally`만 갱신한다.

현재 `Poll#readiness_voter_count`, `_readiness`, `_poll_participants`, `PollsController#voter_counts_for`는
draft에서 slot을 읽는다. 이는 snapshot 생성 전이므로 정상적인 source 의존이다. 반면 시작
후 운영 service·결과 service·투표 화면은 이미 snapshot을 기준으로 한다. Student와
과거 PollParticipant를 연결하는 신규 FK는 기본 목표로 두지 않는다.

## 5. 목표 구조

`Poll` 정의와 학급별 실행을 분리한다.

```text
School
└─ Poll                    # 재사용 가능한 내용과 선택지 정의
   └─ PollSession          # 특정 Classroom의 1회 실행
      ├─ Classroom         # draft 명단 원본
      ├─ operator          # 해당 실행의 실제 운영자
      ├─ PollParticipant[] # 시작 시 number/name snapshot
      ├─ PollProgress
      ├─ PollParticipation[]
      └─ count-only tallies/events
```

- `Poll`은 학교에 속하며 실행 명단과 진행 상태를 직접 소유하지 않는다.
- 신규 실행 단위인 `PollSession`은 Classroom과 당시 담당 교사를 참조한다.
- draft PollSession은 `classroom.students.where(active: true).order(:number)`를 명단으로 쓴다.
- 시작 transaction에서 active Student의 number/name을 PollParticipant snapshot으로 복사한다.
- Classroom 기반 participant의 `source_participant_slot_id`는 null로 둔다. `source_student_id`를
  새로 만들지 않는다.
- 시작 후 인원·순번·완료·미참여·기권·결과는 PollParticipant/Participation/Progress/tally로만
  계산한다. Student 변경은 과거 PollSession에 영향을 주지 않는다.
- 학급 표시는 `school_year`, `grade`, `formatted_class_label`을 사용하여 `1반`과
  `생활교육실`을 모두 안전하게 표시한다.
- `Classroom.teacher`는 평상시 담임이고 `PollSession.operator`는 실제 운영자다. 담임이 기본
  운영자일 수 있지만 동일성을 강제하지 않는다.
- `operator_name_snapshot`은 실행 당시 운영자 이름을 보존하며 User 이름이나 operator 변경으로
  자동 갱신하지 않는다. 운영 가능 여부와 학교 접근은 생성 service/policy에서 검증한다.

## 6. source 전환 방식

### 권고: 새 PollSession은 Classroom 전용, 기존 Poll runtime은 단계적으로 이관

`polls.classroom_id`를 추가하거나 Poll 자체에 ParticipantGroup/Classroom dual source를
도입하지 않는다. 새 `PollSession`은 처음부터 Classroom만 참조한다. 기존 Poll row와
ParticipantGroup runtime은 실행 기록을 PollSession으로 옮길 때까지 그대로 유지한다.

- `polls.school_id`는 legacy row를 위해 처음에는 nullable이다.
- `poll_sessions`는 poll, classroom, operator와 생성 당시 학급·운영자 이름 snapshot을 가진다.
- 같은 Poll/Classroom의 draft 또는 in_progress PollSession은 하나만 허용한다.
- closed/stopped 실행 뒤 같은 Poll을 같은 Classroom에서 다시 실행할 수 있다.
- PollParticipant/Progress/tally/event에는 nullable `poll_session_id`가 있고 기존 `poll_id`도 유지한다.
- legacy row는 `poll_session_id = NULL`, 새 실행 기록은 같은 Poll의 PollSession을 함께 참조한다.
- legacy와 PollSession의 unique index를 분리해 같은 Poll을 여러 PollSession에서 실행할 DB 기반을
  마련했다. PollParticipation은 PollParticipant를 통해 간접 연결한다.

이 구조는 정의 재사용과 실행 기록을 분리하고 새 runtime에 dual-source 조건을 남기지 않는다.
foundation rollback은 PollSession row가 있으면 기록 삭제 대신 명시적으로 거부한다.

## 7. 단계별 구현 계획

### 단계 1: PollSession foundation

- `polls.school_id` nullable FK를 추가하고 Poll에 optional school association을 둔다.
- poll/classroom/operator/status, 학급·운영자 이름 snapshot과 lifecycle 시각을 가진
  `poll_sessions`를 만든다.
- PollSession status는 draft/in_progress/closed/stopped이고 DB 허용값 constraint를 둔다.
- 같은 Poll/Classroom의 draft/in_progress 중복을 model validation과 partial unique index로 막는다.
- Poll, Classroom, operator 삭제는 PollSession이 있으면 제한한다.
- foundation 시점에는 실행 기록 association을 만들지 않았고 기존 runtime은 Poll과
  ParticipantGroup을 계속 사용한다.

### 단계 2: 실행 기록 FK 기반

- PollParticipant, PollProgress, PollOptionTally, PollContestTally, PollEvent에 nullable
  `poll_session_id`를 추가한다. PollParticipation은 PollParticipant를 통한 소유 관계를 유지한다.
- legacy row의 기존 poll FK와 삭제 정책을 유지한 채 새 association을 추가한다.
- participant number, progress, option tally, contest tally의 legacy/PollSession partial unique
  index를 분리하고 PollEvent에는 일반 PollSession index만 둔다.
- 연결된 실행 기록의 Poll과 PollSession.poll 일치를 model에서 검증한다.
- legacy backfill 정책이 확정되기 전에는 새 PollSession runtime을 열지 않는다.

### 단계 3: 새 Poll 정의와 Classroom 배정

- `Polls::CreateDefinitionWithSession`은 Poll 정의·contest·option과 최초 draft PollSession을
  하나의 transaction으로 생성한다.
- service는 school을 Classroom에서, user/operator를 actor에서 정하고 외부 source·소유권·lifecycle
  값을 신뢰하지 않는다.
- active Classroom과 active Student를 확인하고 담임 teacher, 같은 학교 manager, global admin의
  운영 권한을 검증한다. operator와 Classroom teacher의 동일성은 강제하지 않는다.
- 학급·운영자 이름 snapshot을 caller인 service가 명시적으로 저장한다.
- `GET /polls/new`는 권한별 eligible Classroom과 단일 contest/option 입력을 제공하고,
  `POST /polls`는 service만 호출한다. 신규 ParticipantGroup Poll 생성은 차단됐다.
- 새 School 기반 draft는 목록에서 학급·operator snapshot과 “실행 준비 중”만 표시하며 legacy
  시작·진행·결과 action을 제공하지 않는다. 기존 ParticipantGroup Poll 조회/runtime은 유지한다.

### 단계 4: PollSession 시작

- `Polls::StartSession`은 PollSession row를 transaction 안에서 lock하고 draft 상태, 정의,
  Classroom, active Student와 actor 권한을 다시 검증한다.
- Classroom의 active Student를 number 순으로 PollParticipant snapshot에 복사하며
  PollParticipation은 만들지 않는다.
- `source_participant_slot_id`는 null이며 Student source FK를 추가하지 않는다.
- progress, option/contest tally, `poll_started` event를 같은 PollSession에 연결하고 공통 시작 시각을
  기록한 뒤 session만 in_progress로 전환한다. Poll 정의 status는 변경하지 않는다.
- `PollSessionsController#start`는 parent Poll과 PollSession ID를 함께 조회하고 policy 확인 후
  service만 호출한다. 목록은 모든 session 상태를 표시하고 권한 있는 draft에만 POST 시작 버튼을 둔다.
- 시작 뒤 목록에서 in_progress를 표시하지만 진행·투표·중단·종료·결과 runtime은 후속 단계다.
- legacy Poll 시작 경로는 실제 데이터 전환 완료 전까지 별도 분기로 유지한다.

### 단계 5: 운영 화면과 결과

- draft 인원은 active Student, 시작 후 인원·진행은 PollParticipant/Participation/Progress를 쓴다.
- 숫자·문자 학급명은 PollSession의 `classroom_name_snapshot`으로 안전하게 표시한다.
- `ResultSummary`, `IntegrityReport`, `Close`는 PollSession 단위 snapshot/tally를 사용하되
  count-only 비밀투표 계산 의미는 바꾸지 않는다.
- archived·closed·stopped 실행은 Classroom/Student 현재 상태로 재계산하지 않는다.
- 개인별 선택 row가 없는 count-only 비밀투표 계약을 유지하며 결과를 재계산하지 않는다.

### 단계 6: 기존 Poll 데이터 전환

보존할 Poll 범위는 repository만으로 확정할 수 없다. **운영 백업의 Poll 목록·상태·
보관 여부·group 사용 현황을 조사한 후 결정해야 한다.**

- 시작된 closed/stopped/in_progress Poll은 PollParticipant·Participation·Progress·tally·event와
  group name snapshot으로 완결된다. PollSession backfill은 필요하지만 Classroom·Student 생성
  필요 여부는 운영 데이터 조사 후 결정한다.
- 보존할 draft Poll은 snapshot이 없으므로 계속 운영할 것이라면 명시적
  ParticipantGroup→Classroom, ParticipantSlot→Student mapping이 필요하다. 불필요한 draft를
  삭제할지도 운영 정책 결정이다.
- 전환기가 필요하면 Poll ID를 명시적으로 받는 dry-run 기본 service/task로 만들고,
  Poll·PollSession·participant·participation·progress·option/contest/tally/event ID·count·status·시각을
  transaction 전후로 대조한다.
- Student를 생성하는 경우 원본 slot number/name만 사용하고 학년도를 명시적으로
  받는다. group name 문자열을 파싱해 Classroom을 추측하지 않는다.

### 단계 7: legacy 제거

- 신규 Poll 생성·시작·준비·목록·보관 경로의 group/slot 의존을 제거한다.
- 보존 대상 Poll을 전환하거나 snapshot-only 역사 기록으로 완결했음을 검증한다.
- 실행 기록의 PollSession FK를 필수로 전환한 뒤 runtime의 Poll 직접 실행 association을 제거한다.
- `polls.participant_group_id`, `poll_participants.source_participant_slot_id` FK/index/column과 model
  association, legacy spec을 제거한다.
- Election 실제 데이터 Classroom 전환과 runtime legacy 분기 제거가 완료되면 Election
  일회성 변환 도구의 보존/제거 시점을 결정한다.
- 저장소 전체 검색으로 Poll·Election 외 의존이 없음을 확인한 후
  ParticipantGroup·ParticipantSlot 모델·controller·policy·view·table을 삭제한다.

## 8. 권한과 학교 범위

### 현재 확인된 권한

- `PollsController` 모든 action은 login을 요구한다. 학생/익명 접속 경로는 없다.
- `PollPolicy` transaction action은 global admin 또는 `Poll.user` 소유자를 허용한다.
  교사는 자신의 Poll만 조회·시작·진행·중단·종료할 수 있다.
- `PollPolicy::Scope` 은 admin도 포함해 `scope.where(user: user)`만 반환하므로, admin은
  다른 교사 Poll의 URL을 알면 조회할 수 있지만 목록에서는 보지 못한다.
- Poll만을 위한 별도 admin controller/view는 없고 교사와 같은 `PollsController`·view를
  global admin 권한으로 이용한다.
- 새 Poll group 선택은 teacher에게 소유 group만, admin에게 모든 `teacher_personal`
  group을 허용한다. Poll에 `school_id`는 없고 teacher_personal group의 school도 optional이므로
  현재 Poll 생성은 학교 범위를 서버에서 검증하지 않는다.
- `SchoolMembership.manager` 역할은 현재 `PollPolicy`/controller에서 사용하지 않는다.

### 전환 원칙

- 일반 teacher: 자신의 active Classroom, 같은 school membership, active Student가 있는 경우만
  생성·운영한다.
- global admin: 기존 운영 action 권한은 유지하되, 타 교사 Classroom Poll 신규 생성의
  소유자/운영자 정책을 먼저 확정한다.
- school manager: 권한 확대를 이 cutover에서 추측하지 않는다. 현재 정책에 없으므로
  별도 권한 spec으로 도입한다.
- 다른 학교 Classroom ID를 직접 전송해도 eligible relation 밖이면 생성하지 않는다.
- Student는 인증 주체가 아니며, 현재처럼 교사 장치의 감독형 ballot 흐름을 유지한다.

## 9. 데이터 invariant

전환 및 역사 데이터 검증에서 다음 값을 유지한다.

- Poll: `id`, `user_id`, `title`, `kind`, `status`, `archived_at`, `created_at`.
- PollParticipant: ID, poll ID, number, name, row count.
- PollParticipation: ID, participant ID, `status`, `recorded_at`, row count.
- PollProgress: ID, poll ID, current participant ID, `status`, `ballot_status`, `started_at`, `closed_at`.
- PollContest/PollOption: ID, poll/contest association, position/number/name, row count.
- PollOptionTally: ID, poll/option ID, `votes_count`.
- PollContestTally: ID, poll/contest ID, `abstentions_count`.
- PollEvent: ID, poll/participant/actor ID, event type, occurred_at, details, row count.
- 참여 상태별 count, participant별 처리 상태, option별 표 수, contest별 기권 수.

Poll 자체에 `started_at`/`closed_at`은 없고 `PollProgress` 열에 존재한다. stopped 시각
열도 없으며 `poll_stopped` event로만 기록한다. 존재하지 않는 `PollVote` ID를
invariant로 만들지 않는다.

## 10. spec 전략

### 현재 spec이 보장하는 계약

- `spec/models/poll_spec.rb`: group 필수 조건, 빈 group 거부, 상태, 삭제/보관 정책.
- `spec/models/poll_participant_spec.rb`: number/name snapshot validation, poll 내 number/source slot unique,
  nullable source.
- `spec/services/polls/start_spec.rb`: slot number/name snapshot, 중복 시작 방지, tally/progress/event,
  각 실패의 transaction rollback.
- `spec/services/polls/result_summary_spec.rb`, `integrity_report_spec.rb`, `close_spec.rb`: snapshot
  참여 상태와 count-only tally 결과·무결성.
- `spec/requests/polls_spec.rb`: 소유 group 생성, draft slot/시작 snapshot 인원, 운영, 중단,
  보관, 삭제, source 변경/삭제 후 snapshot 보존.
- `spec/policies/poll_policy_spec.rb`: global admin과 owner teacher의 현재 권한.

### 단계별로 추가할 핵심 spec

1. foundation: Poll/Classroom school 일치, operator와 snapshot, status constraint, active 중복,
   FK 삭제/rollback 보호.
2. 실행 기록 FK: participant/progress/tally/event의 nullable PollSession 연결, legacy 보존,
   backfill invariant.
3. 새 배정: 자기 active Classroom, 같은 학교, 담임, active Student 필수;
   inactive/다른 학교/직접 legacy parameter 거부; 권한 spec.
4. 시작: active Student만 number 순 snapshot, inactive 제외, source slot null, 빈 명단 거부,
   PollSession row lock과 중복 시작, 전체 rollback, legacy start 회귀.
5. 운영: 숫자/`생활교육실` 표시, draft active Student 수, 시작 후 snapshot 수,
   Student 변경 무영향, Classroom/legacy 혼합 목록, nil group 안전성.
6. 결과: option·contest tally와 participation invariant, archived/stopped/closed snapshot 표시,
   source slot 변경/삭제 회귀.
7. 데이터 전환: dry-run 무변경, 선택 Poll 격리, ID/count/status/시각/tally/event
   보존, 중간 실패 rollback, already-converted/no-op. 보존 범위 결정 후에만 작성한다.
8. legacy 제거: 전체 의존 검색, column/FK 제거 migration up/down, 신규 Classroom PollSession
   happy path와 보존 Poll 결과 회귀.

## 11. 제거 완료 조건

- [ ] Election 신규 세션 생성·시작·재투표에 legacy source 사용이 없다.
- [ ] 선택한 실제 Election의 Classroom 일회성 변환과 invariant 검증이 완료됐다.
- [ ] Election runtime legacy 표시·조회·StartSession 분기가 제거됐다.
- [ ] Poll 신규 생성·시작·운영·결과·보관 경로에 legacy source 사용이 없다.
- [ ] 운영 Poll 보존 범위가 확정되고 필요한 데이터 전환/검증이 완료됐다.
- [ ] Poll runtime과 표시에서 ParticipantGroup·ParticipantSlot 분기가 제거됐다.
- [ ] Election/Poll 외 `ParticipantGroup` 관리 controller·policy·view를 제거해도 된다.
- [ ] `poll_participants.source_participant_slot_id`, `election_voters.source_participant_slot_id` FK를
  제거해도 snapshot·결과가 유지된다.
- [ ] ParticipantSlot을 참조하는 모든 FK/index가 제거됐다.
- [ ] 원본 snapshot ID/count와 표시·집계 결과를 대조했다.
- [ ] 전체 model/service/request/policy/migration spec이 통과했다.
- [ ] Election 변환 도구와 Poll 전환 도구의 제거/보관 시점을 운영 절차에 남겼다.

## 12. 확인된 위험과 미결정 사항

### 높음

1. **보존 Poll 범위 미확정**: repository에는 실제 운영 Poll의 개수·상태·보관
   필요성이 없다. 운영 백업 조사 전에 전체 보존·선택 보존·제거를 결정하지 않는다.
2. **legacy Poll의 school 경계가 없음**: `polls.school_id`는 foundation에서 nullable이므로 기존
   row는 계속 user/group만으로 존재한다. 새 PollSession 생성 전 school·teacher membership를
   server에서 검증하고 legacy backfill은 별도로 수행해야 한다.
3. **source-null 역사 row**: group FK가 `ON DELETE SET NULL`이고 closed/stopped는 model도 group을
   요구하지 않는다. Election식 unconditional exactly-one constraint는 기존 기록을 깨뜨린다.
4. **시작 동시성**: `Polls::Start` 검증은 transaction 밖에서 시작하고 Poll row lock이 없다.
   Classroom snapshot 전환 때 lock 안에서 재검증해야 한다.

### 중간

5. **운영자 정책**: `Poll.user`가 owner/operator 두 역할을 함께 한다. global admin의
   타 Classroom Poll 생성과 school manager 권한은 별도 결정이 필요하다.
6. **이름 snapshot column**: `participant_group_name_snapshot`은 group 삭제 후 표시를 보존한다.
   Classroom 표시 snapshot을 별도 열로 둘지, 보존 backfill 후 중립적 이름으로 rename할지
   1단계에서 확정해야 한다.
7. **PollSession 이관 순서**: foundation만 추가된 동안 기존 Poll runtime과 새 PollSession이
   함께 존재한다. 실행 기록 FK backfill과 invariant 검증 전에는 새 runtime을 열지 않는다.
8. **재투표 없음**: stopped Poll은 terminal이며 replacement/revote 관계도 없다.
   `ResumeCurrentParticipant`는 in_progress pointer 복구일 뿐이다. Poll 재투표는 이 전환의 숨은 요구로
   추가하지 않는다.

### 낮음

9. **source slot FK**: `PollParticipant.source_participant_slot_id`는 optional이고 삭제 시 null로 바뀐다.
   실행·결과는 이 FK를 필수로 사용하지 않아 신규 Student source FK가 필요하지 않다.
10. **투표 제출 service 두 개**: route/controller는 `SubmitVote`를 사용하지만 `SubmitBallot`도
    따로 존재한다. Classroom cutover에서 둘을 공통화하지 말고, 실제 호출 계약을 먼저
    확정한 뒤 미사용 경로 정리를 별도로 판단한다.
11. **ParticipantGroup purpose**: Poll UI는 `teacher_personal`만 선택하고 Election legacy는
    `school_election`을 사용한다. table 제거 전에 두 purpose의 운영 데이터가 각각 전환됐는지
    분리해 검증해야 한다.
