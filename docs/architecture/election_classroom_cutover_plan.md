# Election 명단을 Classroom·Student로 전환하는 최소 계획

## 목차

1. [문서 목적](#1-문서-목적)
2. [현재 Election 의존성](#2-현재-election-의존성)
3. [최종 목표](#3-최종-목표)
4. [호환 방식](#4-호환-방식)
5. [기존 기록 보존](#5-기존-기록-보존)
6. [최소 전환 단계](#6-최소-전환-단계)
7. [예상 변경 파일](#7-예상-변경-파일)
8. [주요 위험](#8-주요-위험)
9. [명시적으로 제외하는 작업](#9-명시적으로-제외하는-작업)

## 1. 문서 목적

이 문서는 새로 생성하는 `ElectionSession`의 명단 원본을
`ParticipantGroup`·`ParticipantSlot`에서 `Classroom`·`Student`로 전환하는 최소
구현 순서를 확정한다. 기존 세션과 실제 선거 기록은 현재 구조 그대로 보존한다.

이 전환은 학생의 진급, 반 이동, 전입·전출 또는 학년도 간 동일인 연결을 다루지
않는다. 새 학년도에는 새 Classroom과 Student 명단을 만든다는 단순 운영 정책을
유지한다.

## 2. 현재 Election 의존성

### 2.1 ElectionSession

현재 `ElectionSession`은 다음 association을 가진다.

- `Election` 필수
- 운영 교사인 `User` 필수
- `ParticipantGroup` 필수
- `ElectionProgress` 하나
- `ElectionVoter`, tally, event 다수

DB의 `election_sessions.participant_group_id`는 `null: false`다. 모델도
`participant_group` 존재를 검증하며 생성 시 `purpose: school_election`인 group만
허용한다. 같은 Election에서 동일 group의 `draft` 또는 `in_progress` 세션은 하나만
허용하는 partial unique index와 model validation이 있다.

관리자 세션 생성은 `Admin::ElectionSessionsController`가 Election과 같은 학교의
미배정 school-election group을 선택하고 `participant_group.user`를 세션 교사로
배정한다. 단일 생성과 일괄 생성 모두 `participant_group_id` parameter를 사용한다.

### 2.2 ParticipantGroup과 권한

school-election group은 학교, 학년, 반 표시값과 소유 교사를 가진다.
`ElectionSession#teacher_can_operate_session`은 일반 교사의 경우 group 소유자와
세션 교사가 같은지 검증한다. `ElectionSessionPolicy#operate?`는 global admin을
허용하고, 일반 교사는 Election이 draft가 아니며 `session.teacher_id`가 본인일 때만
허용한다.

현재 `ElectionPolicy#manage_sessions?`는 global admin에게만 열려 있다.
`SchoolMembership.role = manager`는 Election 세션 배정이나 운영 권한에 아직
적용되지 않았다. 이번 전환에서 manager 권한이 이미 구현된 것으로 가정하지 않는다.

### 2.3 세션 시작과 snapshot

`Elections::StartSession`은 group의 `participant_slots.order(:number)`를 읽는다.
각 slot에서 다음 값을 기존 `ElectionVoter`로 복사한다.

```text
ParticipantSlot.number → ElectionVoter.number
ParticipantSlot.name   → ElectionVoter.name
ParticipantSlot.number → ElectionVoter.position
ParticipantSlot        → ElectionVoter.source_participant_slot (optional)
```

`ParticipantSlot`에는 active 또는 제외 상태가 없다. 모든 slot이 번호순으로 포함된다.
각 voter를 만든 직후 `ElectionParticipation(status: pending)`을 하나씩 생성하고, 첫
voter를 가리키는 `ElectionProgress`, 후보·항목별 tally와 시작 event도 같은
transaction 안에서 생성한다.

시작 가능한 상태는 `draft`와 `supervised`이며, 빈 명단·불완전한 contest·이미 생성된
진행 데이터·유효하지 않은 session을 거부한다. transaction, session row lock,
재검증과 unique constraint가 중복 시작을 방어한다.

### 2.4 화면과 조회

관리자 Election 상세의 세션 배정 화면은 group을 학년별로 나열하고
`participant_group_ids[]`를 제출한다. 세션 목록, 결과와 운영 화면의 다음 부분도
group 이름, 학년·반 또는 slot 수를 직접 사용한다.

- `app/views/admin/elections/_sessions.html.erb`
- `app/views/admin/elections/_session_results.html.erb`
- `app/views/elections/sessions/_admin_summary.html.erb`
- `app/views/elections/sessions/_teacher_progress.html.erb`
- `app/views/elections/sessions/_voter_roster.html.erb`
- `app/views/elections/sessions/_closed_results.html.erb`

draft 세션의 인원수는 group의 slot 수로 계산하지만 시작 뒤 운영 명단은
`ElectionVoter`를 사용한다. 완료 결과의 표 수와 참여 상태도 snapshot과 tally에
있지만 일부 제목·학급 표시가 여전히 group association을 요구한다.

재투표 서비스도 기존 session의 election, participant group, teacher와 operation
mode를 복사해 replacement draft session을 만든다. 관리자 Turbo 갱신 서비스 역시
group 목록과 배정 상태를 다시 조회한다.

### 2.5 핵심 spec 의존성

다음 spec이 ParticipantGroup 기반 계약을 직접 검증한다.

- `spec/models/election_session_spec.rb`
- `spec/models/election_voter_spec.rb`
- `spec/services/elections/start_session_spec.rb`
- `spec/services/elections/revote_session_spec.rb`
- `spec/requests/admin/election_sessions_spec.rb`
- `spec/requests/admin/elections_spec.rb`
- `spec/requests/elections/sessions_spec.rb`
- `spec/factories/election_sessions.rb`

다른 Election 운영 service spec도 공통 준비 과정에서 ParticipantGroup과 slot을 만든다.
전환 시 기존 source 경로의 회귀 검증을 유지하면서 Classroom source example을 추가해야
한다. 기존 snapshot이 원본 명단 변경과 분리된다는 StartSession 및 voter spec도
삭제하지 않는다.

## 3. 최종 목표

새로 생성하는 ElectionSession의 명단 원본은 다음 구조다.

```text
Classroom(active: true)
└── Student(active: true)
```

세션 시작 시 active Classroom의 active Student만 `number` 오름차순으로 읽는다.
새 snapshot 모델을 만들지 않고 기존 `ElectionVoter`를 그대로 사용한다.

```text
Student.number → ElectionVoter.number
Student.name   → ElectionVoter.name
Student.number → ElectionVoter.position
```

각 voter의 `ElectionParticipation(status: pending)` 생성과 progress, tally, event 생성
순서 및 transaction 경계는 현재 `Elections::StartSession`의 동작을 유지한다.

새 supervised session은 Election과 같은 학교의 active Classroom을 대상으로 한다.
일반 교사가 운영하는 세션은 자신의 active Classroom만 허용한다. 현재 구조에서
Classroom 담임은 optional이지만 `ElectionSession.teacher`는 필수이므로, 담임이 없는
Classroom은 운영 교사를 명시적으로 배정하기 전까지 새 supervised session 대상으로
사용하지 않는다.

## 4. 호환 방식

### 4.1 권장안: 선택지 A

전환 기간에는 ElectionSession이 다음 source 중 정확히 하나를 참조한다.

```text
legacy session → participant_group
new session    → classroom
```

`classroom_id`를 nullable로 추가하고 기존 `participant_group_id`도 새 세션을 위해
nullable로 전환한다. 모델과 DB constraint가 두 source 중 하나만 존재하도록 보호한다.
활성 세션 중복 제약도 legacy group용과 새 classroom용으로 각각 유지한다.

이 방식은 기존 세션을 수정하지 않으면서 새 생성 경로만 Classroom으로 바꿀 수 있고,
Student와 ParticipantSlot 사이의 동기화가 필요 없다. 단, 조회와 재투표는 session의
source 종류를 명시적으로 처리해야 한다.

### 4.2 권장하지 않는 선택지 B

Classroom마다 ParticipantGroup을 자동 생성하는 방식은 같은 명단을 Student와 slot에
중복 저장한다. 학생 이름·번호·active 변경 동기화와 실패 복구가 새로 필요하며 legacy
구조의 수명을 늘린다. 현재 코드의 일시적 재사용 외에 이를 정당화할 이점이 없으므로
채택하지 않는다.

범용 roster abstraction이나 polymorphic source 모델도 추가하지 않는다. 두 source의
전환 기간만 모델의 명시적 association과 작은 분기로 처리한다.

## 5. 기존 기록 보존

- 기존 ElectionSession의 `participant_group_id`를 유지한다.
- 기존 ElectionSession을 새 Classroom에 소급 연결하지 않는다.
- 기존 ElectionVoter를 Student로 변환하거나 다시 만들지 않는다.
- 완료·중단 세션의 voter, participation, tally, progress와 event를 수정하지 않는다.
- nullable인 `ElectionVoter.source_participant_slot_id`는 기존 값 그대로 보존한다.
- 실제 운영 결과는 저장된 ElectionVoter snapshot과 tally를 기준으로 계속 조회한다.
- 기존 세션의 학급 표시는 ParticipantGroup을 사용하되, source가 없어도 결과 핵심값을
  snapshot과 tally로 읽도록 조회 의존을 단계적으로 줄인다.

ParticipantGroup table 제거는 기존 세션의 표시 정보까지 독립적으로 보존하는 방법이
확정되고 Poll 전환도 끝난 뒤 별도 작업으로 수행한다.

## 6. 최소 전환 단계

### 1단계 — Classroom 연결 기반

- `election_sessions.classroom_id` nullable foreign key를 추가한다.
- 기존 `participant_group_id`를 nullable로 바꾸되 기존 값은 유지한다.
- 두 source 중 정확히 하나를 요구하는 model validation과 DB check constraint를 둔다.
- `(election_id, classroom_id)`에 active status용 partial unique index를 추가한다.
- 기존 group용 partial unique index는 legacy 세션과 재투표를 위해 유지한다.
- 아직 세션 생성과 시작 runtime은 ParticipantGroup 경로를 사용한다.

### 2단계 — 새 세션 생성 경로 전환

- 관리자 배정 화면의 새 source를 Election 학교의 active Classroom으로 바꾼다.
- Classroom에는 Student가 하나 이상 있고 supervised 운영 교사가 배정돼 있어야 한다.
- 새 session에는 Classroom과 `classroom.teacher`를 배정하고 ParticipantGroup을 만들지
  않는다.
- 일반 교사의 접근은 `session.teacher_id`와 자기 active Classroom을 기준으로 유지한다.
- school manager의 Election 관리 권한은 현재 미구현 상태이므로 이 단계에 섞지 않고
  별도 policy 작업으로 다룬다.

### 3단계 — voter snapshot 원본 전환

- Classroom 기반 draft session은 `students.where(active: true).order(:number)`를 읽는다.
- ParticipantGroup 기반 기존 draft/replacement session은 기존 slot 경로를 유지한다.
- 양쪽 모두 기존 ElectionVoter, ElectionParticipation, progress, tally와 event 생성
  흐름을 재사용한다.
- 현재 `Elections::StartSession` 안에 source별 학생 조회와 voter attribute 생성의 작은
  private 분기를 두는 방식을 우선한다. 별도 범용 roster 계층은 만들지 않는다.
- 시작 뒤에는 source가 아니라 ElectionVoter snapshot만으로 투표를 진행한다.

### 4단계 — 조회·표시와 재투표 전환

- Classroom 세션은 `school_year`, `grade`, `class_number`, `name`을 표시한다.
- legacy 세션은 기존 ParticipantGroup 표시를 유지한다.
- draft 인원수만 source별 원본 명단에서 계산하고, 시작된 세션은 ElectionVoter 수를
  사용한다.
- 결과·운영 화면의 group 직접 호출을 source별 표시 method 또는 최소 helper로 모은다.
- 재투표 replacement는 원본 세션과 같은 source, teacher와 operation mode를 복사한다.
- 완료 결과의 투표자·참여·집계는 source association이 아니라 기존 snapshot과 tally로
  조회되는지 spec으로 고정한다.

### 5단계 — 기존 명단 의존 제거

다음 조건을 모두 만족한 뒤 별도 작업으로 진행한다.

- 새 ElectionSession 생성이 Classroom 기반이다.
- StartSession이 새 세션에서 Student snapshot을 만든다.
- 권한, 재투표와 화면이 두 source를 안전하게 처리한다.
- 기존 세션 결과를 ParticipantGroup 없이도 보존할 표시 정책이 확정됐다.
- Poll의 ParticipantGroup·ParticipantSlot 전환도 완료됐다.
- 저장소에 다른 ParticipantGroup runtime 의존이 없다.

이 문서에서는 ParticipantGroup table 제거를 바로 수행하지 않는다.

## 7. 예상 변경 파일

### 1단계

- `db/migrate/<timestamp>_add_classroom_to_election_sessions.rb`
- `app/models/election_session.rb`
- `spec/models/election_session_spec.rb`
- `spec/factories/election_sessions.rb`

### 2단계

- `app/controllers/admin/election_sessions_controller.rb`
- `app/controllers/admin/elections_controller.rb`
- `app/views/admin/elections/_sessions.html.erb`
- `app/services/elections/broadcast_admin_overview.rb`
- `spec/requests/admin/election_sessions_spec.rb`
- `spec/requests/admin/elections_spec.rb`

### 3단계

- `app/services/elections/start_session.rb`
- `app/models/election_voter.rb`
- `spec/services/elections/start_session_spec.rb`
- `spec/models/election_voter_spec.rb`

`ElectionVoter`의 새 Student source association이 실제 이관 추적에 필요하다고 확정될
때만 nullable `source_student_id` migration을 추가한다. snapshot 생성 자체에는 이
association이 필수가 아니다.

### 4단계

- `app/controllers/elections/sessions_controller.rb`
- `app/services/elections/revote_session.rb`
- `app/services/elections/broadcast_admin_overview.rb`
- `app/views/admin/elections/_session_results.html.erb`
- `app/views/elections/sessions/_admin_summary.html.erb`
- `app/views/elections/sessions/_teacher_progress.html.erb`
- `app/views/elections/sessions/_voter_roster.html.erb`
- `app/views/elections/sessions/_closed_results.html.erb`
- `spec/services/elections/revote_session_spec.rb`
- `spec/requests/elections/sessions_spec.rb`

공통 표시 method가 필요하면 기존 helper를 먼저 확인하고 가장 작은 위치에 추가한다.

## 8. 주요 위험

- `participant_group_id`의 DB `null: false`와 model 필수 validation을 함께 바꿔야 한다.
- active session unique 제약이 현재 participant group만 기준으로 한다.
- 세션 교사 적합성 검증이 group 소유권에 직접 의존한다.
- StartSession이 participant slots를 직접 읽는다.
- 재투표가 participant group을 그대로 복사하고 같은 group으로 활성 세션을 검사한다.
- 관리자 Turbo 갱신과 여러 view가 group 이름과 slot 수를 무조건 사용한다.
- 완료 결과 화면도 학급 표시를 위해 ParticipantGroup을 요구한다.
- 실제 선거 데이터가 있으므로 legacy association을 조기에 제거할 수 없다.

## 9. 명시적으로 제외하는 작업

- Poll 명단 전환
- ParticipantSlot에서 Student로 실제 import
- production 데이터 migration
- 기존 ElectionSession의 Classroom 소급 연결
- 새 voter 또는 범용 roster 모델 작성
- polymorphic participant source
- 진급, 반 이동과 전입·전출 기능
- 학년도 간 동일 학생 추적과 이전 학년도 Student 복사
- UI 전면 재설계
- ParticipantGroup·ParticipantSlot table 즉시 제거
