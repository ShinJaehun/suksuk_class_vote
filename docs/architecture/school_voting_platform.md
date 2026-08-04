# 학교 조직 및 투표 플랫폼 재설계

## 목차

1. [문서의 목적과 지위](#1-문서의-목적과-지위)
2. [현재 구조와 재구축 방향](#2-현재-구조와-재구축-방향)
3. [목표 조직 구조](#3-목표-조직-구조)
4. [핵심 불변조건](#4-핵심-불변조건)
5. [권한 구조](#5-권한-구조)
6. [투표 도메인의 독립 축](#6-투표-도메인의-독립-축)
7. [대상 학급과 Voter snapshot](#7-대상-학급과-voter-snapshot)
8. [비밀투표](#8-비밀투표)
9. [기존 Election 전환](#9-기존-election-전환)
10. [Poll 목표 구조](#10-poll-목표-구조)
11. [상태 무결성과 운영 이벤트](#11-상태-무결성과-운영-이벤트)
12. [역사 자료 export/import](#12-역사-자료-exportimport)
13. [단계적 전환 순서](#13-단계적-전환-순서)
14. [확정된 설계와 후속 검토 사항](#14-확정된-설계와-후속-검토-사항)

## 1. 문서의 목적과 지위

이 문서는 쑥쑥교실투표를 학교 조직 기반의 선거·의견 활동 플랫폼으로 재구축하기
위한 canonical architecture 문서다. 기존 구현을 설명하는 문서가 아니라 앞으로
구축할 관계, 권한 경계, 상태 무결성, 비밀투표 및 데이터 이관 원칙을 정의한다.

기존 architecture/spec 문서와 충돌하면 재구축 목표에는 이 문서를 우선 적용한다.
기존 문서는 현재 구현과 전환 과정의 참고 자료로 사용하고 별도 작업에서 갱신하거나
archive한다.

이번 재설계는 기존 DB를 계속 변형하는 소규모 리팩터링이 아니다. 새 구조로
재구축하고 새 DB를 만든 뒤, 보존 대상으로 선택한 2026년 선거 기록만 읽기 전용
export/import 절차로 옮긴다.

## 2. 현재 구조와 재구축 방향

현재 시스템에는 교사가 소유한 `ParticipantGroup`/`ParticipantSlot` 기반 학급
`Poll`, admin이 parent `Election` 아래 학급별 `ElectionSession`을 배정하는
전교임원선거가 있다. 이전 Poll 기반 legacy `SchoolElection` 구조는 제거되었다.

현재 `Poll`은 활동 정의, 명단, 진행 상태, 집계와 진행 포인터를 한 흐름에서 맡고
`Poll.kind = election`으로 선거도 표현한다. 교사 접근 경계는 학교·학급보다 사용자
소유권 중심이다.

목표 구조는 `School`을 조직과 권한의 최상위 경계로 삼고 실제 학급과 학생을
`Classroom`, `Student`로 표현한다. 모든 신규 학급투표와 전교투표는 `Poll` 정의와
학급별 `PollSession`을 사용한다. 후보자 선거는 `Poll.kind = election`, 설문조사는
`survey`, 토의는 `discussion`, 토론은 `debate`로 표현한다. 기존 `Election`은 신규
기능을 개발하지 않는 전환 대상이며 Election ID 6을 historical Poll로 변환하고 검증한
뒤 runtime과 table을 제거할 예정이다.

## 3. 목표 조직 구조

```text
School
├── SchoolMembership
│   └── User
│       ├── member
│       └── manager
│
└── Classroom
    ├── teacher: User 0..1명
    └── Students
```

### 3.1 School, User, SchoolMembership

`School`은 조직, 데이터 접근 및 운영 권한의 최상위 경계다. 학급, 학생, 학교 단위
Election·Poll은 하나의 학교에 속한다.

```text
User
- role: teacher / admin
- name
- email
- encrypted_password
- active
```

`User.role`은 서비스 전체 역할인 `teacher`, `admin`만 사용한다.

```text
SchoolMembership
- school_id
- user_id
- role: member / manager
- active 또는 현재 소속 여부
```

학교 안 역할은 `SchoolMembership.role`의 `member`, `manager`로 관리한다. 교사는
최대 한 학교에만 현재 소속된다. `SchoolMembership`은 `User.role = teacher`인
사용자만 가질 수 있고, 교사 한 명은 현재 유효한 membership을 최대 하나만 가진다.
`manager`는 활성 상태인 teacher에게만 지정한다. 대표 선생님은 해당 학교의
manager이며 담임교사와 독립된 개념이다. manager가 담임일 수도 있고 아닐 수도
있으며, 담임 배정만으로 manager가 되지 않는다.

### 3.2 Classroom과 Student

```text
Classroom
- school_id
- teacher_id nullable
- school_year
- grade
- class_label: string
- name
- active
```

학급에는 활성 상태인 teacher를 담임으로 0명 또는 1명 배정하며, `User.role = admin`인
global admin은 담임으로 배정하지 않는다. 교사는 활성 학급을 최대 한 개만 담당하며
과거 inactive 학급에는 담임 기록을 보존할 수 있다. 이를 DB에서도 보장하도록 활성
학급의 `classrooms.teacher_id`에 partial unique index를 둔다. 담임교사의 현재 학교
membership과 학급의 학교는 같아야 한다.

`class_label`은 숫자와 문자 학급명을 모두 허용한다. 따라서 `1`, `13`뿐 아니라
`생활교육실` 같은 특수 학급도 Classroom으로 표현한다. 숫자 label은 화면에서 `반`
접미사를 붙이고 문자 label은 그대로 표시한다.

학교·학년도·학년·반 이름 조합은 중복될 수 없다. 생성된 학급의 학교는 변경할 수 없다.
가능한 항목은 validation뿐 아니라 DB unique index 또는 constraint로도 보장한다.

학교를 잘못 지정했다면 운영 기록 보존 정책에 따라 비활성화하고 올바른 학교에 새
학급을 만든다.

```text
Student
- classroom_id
- number
- name
- active
```

`Student`는 독립 모델이며 `User`가 아니다. 학생 번호는 학급 안에서 유일해야 한다.
향후 PIN 로그인도 User나 Devise에 연결하지 않고 `Student` 자체 인증으로 추가한다.
Classroom과 Student는 학년도별로 새로 생성하고 학년도 종료 시 Classroom만
비활성화한다. 상세 운영 정책은 `docs/architecture/student_lifecycle_policy.md`를 따른다.

ParticipantGroup·ParticipantSlot에서 Classroom·Student로의 데이터 전환과 단계별
제거 정책은 `docs/architecture/classroom_participant_group_transition.md`를 따른다.

## 4. 핵심 불변조건

- 모든 조직 데이터의 최상위 경계는 `School`이다.
- SchoolMembership은 teacher만 가질 수 있으며 교사별 현재 유효한 membership은
  최대 하나다.
- manager와 학급 담임은 활성 teacher만 가능하고 global admin은 담임이 될 수 없다.
- 학급의 담임은 최대 한 명이고 교사의 활성 담당 학급도 최대 하나다. inactive 학급의
  담임 기록은 보존하되 활성 학급에는 중복 배정할 수 없다.
- 담임의 현재 학교 membership과 학급의 학교는 같아야 한다.
- 학교·학년도·학년·반 조합은 유일하며 생성된 학급의 학교는 바꿀 수 없다.
- 학생 번호는 학급 안에서만 유일하다.
- `Student`는 인증용 `User`가 아니다.
- 학교 범위 활동도 실제 대상 학급을 명시하며 모든 학급을 암묵적으로 포함하지 않는다.
- 시작 뒤 결과에 영향을 주는 정의, 대상과 snapshot은 변경하지 않는다.
- 학생별 참여 상태와 실제 선택의 연결을 저장하지 않는다.
- 전체 결과에는 최종 `closed` 세션만 포함한다.
- `stopped`와 replacement 세션은 삭제하거나 덮어쓰지 않는다.

이 불변조건은 화면 검증이나 validation만으로 끝내지 않는다. 가능한 항목은 DB unique
index 또는 constraint로도 보장하고 transaction과 권한 정책을 함께 사용한다.

## 5. 권한 구조

권한 판단은 controller와 policy를 중심으로 두며 view는 판정 결과만 사용한다.
활성 사용자와 현재 유효한 membership만 학교 권한의 주체가 된다.
membership 생성·manager 지정·담임 배정 시에도 사용자 role과 active 상태, 학교 일치,
기존 담임 배정을 서버에서 검증한다.

### 5.1 Global admin

`User.role = admin`인 global admin은 다음 권한을 가진다.

- 모든 학교·교사·학급·학생 관리
- 모든 Election·Poll 접근
- manager 지정과 해제
- 긴급 운영, 복구 및 데이터 이관

global admin도 시작 후 불변조건과 역사 자료의 읽기 전용 제한을 임의로 우회하지
않는다. 예외 복구는 확인 절차와 이벤트를 남기는 별도 동작으로 수행한다.

### 5.2 School manager

`SchoolMembership.role = manager`인 교사는 자기 학교 범위에서 다음을 수행한다.

- 교사와 membership 관리
- manager 역할 관리
- 학급 관리와 담임 배정
- 학생 관리
- 학교 단위 Election·Poll 생성
- 세션 진행 확인
- 중단·재투표 관리
- 학교 전체 결과 확인

다른 학교의 데이터에는 접근할 수 없다.

### 5.3 일반 teacher

`SchoolMembership.role = member`인 일반 교사의 범위는 다음과 같다.

- 자신의 담당 학급 열람
- 자신의 학급 학생 관리
- 자신의 학급 Election·Poll 생성 및 운영
- 자신의 학급 결과 확인

같은 학교의 다른 학급에는 접근할 수 없다. 담당 학급이 없으면 학급 단위 활동을
생성하거나 운영할 수 없다.

## 6. 투표 도메인의 독립 축

다음 네 축은 서로 독립적이며 한 축의 값으로 다른 축을 추론하지 않는다.

### 6.1 콘텐츠 종류

신규 콘텐츠는 모두 `Poll`로 정의한다. `Poll.kind`는 `election`, `survey`,
`discussion`, `debate`이며 공통 `PollContest`, `PollOption`, `PollSession` runtime을
사용한다. Election과 Poll을 별도 신규 엔진으로 발전시키지 않는다.

### 6.2 운영 범위

```text
classroom
school
```

`classroom`은 대상 학급 하나를 가진다. `school`은 같은 학교에서 대상 학급을 하나
이상 명시적으로 선택한다. 학교의 모든 학급을 자동 포함하지 않으므로 나중에 추가된
학급도 대상에 자동 편입되지 않는다.

### 6.3 진행 방식

```text
teacher_gated
continuous_confirmed
```

- `teacher_gated`: 각 학생의 시작과 다음 학생 전환을 교사가 승인한다.
- `continuous_confirmed`: 제출 뒤 빈 확인 화면을 표시하고 별도의 다음 학생 시작
  단계를 둔다. 다음 학생은 이전 학생의 선택을 볼 수 없어야 한다.

진행 방식은 세션 시작 시 잠근다.

### 6.4 접속 방식

현재 범위는 `supervised_shared_device`, 향후 확장은 `individual_pin`이다.
현재는 교사 감독 아래 공유 장치에서 순서대로 투표한다. 개별 PIN은 목표 구조가
수용할 후속 확장이지만 현재 구현 범위가 아니다.

## 7. 대상 학급과 Voter snapshot

### 7.1 VotingTarget

```text
VotingTarget
- votable_type: Election / Poll
- votable_id
- classroom_id
- position
```

원칙:

- 학급 범위에는 대상 학급이 정확히 하나다.
- 학교 범위에는 같은 학교의 대상 학급이 하나 이상이다.
- 같은 활동에 같은 학급을 중복 등록할 수 없다.
- 시작 전에 대상을 잠그고 시작 후 추가·제거·순서 변경을 금지한다.
- 대상 학급별 Session을 생성한다.

### 7.2 공통 Voter snapshot

```text
Voter
- voting_session_type
- voting_session_id
- student_id nullable
- student_name_snapshot
- student_number_snapshot
- position
- status
- submitted_at
```

상태 예:

```text
pending
completed
absent
```

`Student`는 현재 명단의 원본이고 `Voter`는 특정 세션 시작 시 복사되는 snapshot이다.
`student_id`는 선택적 추적 참조일 뿐 기록의 정체성이 아니다. 원본 학생이 삭제되거나
이름·번호가 바뀌어도 진행 중이거나 종료된 기록의 이름, 번호, 순서와 참여 상태는
바뀌지 않는다.

각 세션은 자기 학급의 활성 학생을 시작 transaction 안에서 Voter로 복사한다.
snapshot 생성과 세션 시작은 함께 성공하거나 함께 실패한다.

후보 또는 선택지를 고른 투표와 기권 투표 모두 제출 절차를 마치면 Voter 상태는
`completed`다. 기권 여부는 Voter에 저장하지 않고 전체 기권표의 count-only 집계에만
반영한다. `absent`는 투표 선택이 아니라 운영자가 처리하는 출석·참여 상태이므로
Voter에 저장할 수 있다.

## 8. 비밀투표

개별 학생과 실제 선택의 연결 관계를 저장, 표시하거나 이벤트에 기록하지 않는다.

저장하는 정보:

- 특정 Voter가 투표 절차를 완료했는지와 제출 시각
- 후보자 또는 선택지별 count-only 집계와 전체 기권표 수
- 선택 내용을 포함하지 않는 운영 이벤트

저장하지 않는 정보:

```text
특정 학생 → 특정 후보 또는 선택지
특정 학생 → 기권
```

따라서 어떤 학생이 기권했는지, 어떤 학생이 어떤 후보 또는 선택지를 골랐는지는
저장하지 않는다. `absent`는 선택 결과가 아닌 운영자의 출석·참여 처리이므로 이
비밀투표 제한과 구분한다.

제출 transaction은 다음을 함께 처리한다.

1. 현재 Voter의 소속, 순번과 제출 자격 검증
2. 중복 제출 검증
3. 해당 후보자·선택지 또는 기권의 count-only 집계 증가
4. 기권을 포함한 정상 제출의 Voter를 `completed`로 처리
5. 다음 진행 상태 전환
6. 선택 내용을 포함하지 않는 이벤트 기록

필요한 row를 lock한 뒤 자격과 현재 위치를 다시 확인한다. 어느 단계든 실패하면
집계, Voter, 진행 상태와 이벤트를 모두 rollback한다. 늦은 요청이나 반복 클릭도
같은 표를 두 번 집계할 수 없다. 기권은 학생의 의사이므로 개인별로 외부에 드러내지
않고 이벤트에도 남기지 않는다. `absent`는 권한 있는 운영자만 처리한다.

## 9. 기존 Election 전환

`Election`, `ElectionContest`, `ElectionCandidate`, `ElectionSession`은 현재 운영 데이터
호환을 위해 남아 있지만 신규 기능의 목표 구조가 아니다. Election ID 6을 Poll,
PollContest, PollOption, PollSession과 count-only historical 기록으로 변환하는 리허설과
운영 검증을 먼저 수행한다. 이후 Election runtime과 table을 제거한다.

변환 전까지 legacy 화면과 service는 수정하지 않는다. 후보 사진, 재투표 관계와
historical/read_only 표시는 Poll 쪽 후속 작업에서 명시적으로 설계하며 Election 코드를
새 Poll runtime에서 호출하거나 복사하지 않는다.

## 10. Poll 목표 구조

현재 Poll runtime을 Classroom·Student로 단계적으로 전환하는 구체적 기준은
[`poll_classroom_cutover_plan.md`](poll_classroom_cutover_plan.md)를 따른다.

```text
Poll
- school_id
- created_by_id
- title
- kind: election / survey / discussion / debate
- school_managed
- status
- started_at
- closed_at
```

`school_managed: false`는 학급투표, `school_managed: true`는 전교투표다. 초기 응답 방식은
Contest별 단일 선택이며 복수 선택과 yes/no 전용 방식은 후속 범위다.

```text
PollOption
- poll_id
- text
- position
```

```text
PollSession
- poll_id
- classroom_id
- operator_id
- operator_name_snapshot
- ballot_flow
- status
```

Poll은 정의와 선택지를 소유하지만 학생 명단, 학급별 진행 상태·집계와 진행 포인터를
직접 소유하지 않는다. 이 책임은 대상 학급별 PollSession에 둔다. 각 Session은 공통
Voter snapshot, count-only 집계, 진행 상태와 운영 이벤트를 가진다.
PollSession의 운영자 필드와 운영자 변경 이벤트에도 ElectionSession과 같은 snapshot
원칙을 적용한다.

`Classroom.teacher`는 평상시 담임이고 `PollSession.operator`는 해당 실행의 실제 운영자다.
담임을 기본 운영자로 선택할 수 있지만 동일성을 강제하지 않으며 manager나 global admin도
정책에 따라 운영할 수 있다. `operator_name_snapshot`은 당시 이름을 보존하고, 실제 운영 권한과
학교 접근 범위는 PollSession 생성 service와 policy에서 검증한다.

현재는 legacy Poll을 위해 `Poll.school_id`를 nullable로 두고 PollSession foundation과 실행 기록의
nullable `poll_session_id` 연결을 추가했다. 기존 Poll runtime은 `poll_session_id = NULL`인 기록을
계속 만들며 `poll_id`도 유지한다. participant number, progress, option/contest tally의 legacy와
PollSession unique index는 분리되어 같은 Poll의 여러 학급 실행을 수용한다. PollParticipation은
PollParticipant를 통해 간접 연결한다. 신규 PollSession 실행 기록은 `poll_id`와 `poll_session_id`를
함께 가지며, PollSession ID는 Poll 내부 번호가 아니라 table 전체의 전역 ID다. legacy runtime
분리와 data backfill은 후속 단계다.

일반 학급투표는 `Polls::CreateDefinitionWithSession`이 Poll 정의와 최초 Classroom draft
PollSession을 같은 transaction에서 만든다. 전교투표는 `/school_polls`에서 정의를 먼저 만들고
같은 School의 여러 Classroom을 draft PollSession으로 배정한다. 각 Session operator는 해당
Classroom의 담임이며 담당 교사의 `/polls` 목록에 나타난다. 사용자 화면에서는 이 두 범위를
각각 학급투표와 전교투표라고 부른다.

전교투표 관리자는 준비 점검을 통과한 draft Poll을 명시적으로 시작한다. 시작은 Poll만
`in_progress`로 전환하고 `started_at`과 Poll-level event를 기록하며 Session snapshot은 만들지
않는다. 이후 담당 교사가 각 draft PollSession을 개별 시작한다. 모든 Session이 무결한 closed
상태일 때 관리자가 전교투표를 명시적으로 종료하고 `closed_at`과 Poll-level event를 기록한다.
재투표가 구현되기 전에는 draft, in_progress, stopped Session이 하나라도 있으면 전체 종료할 수 없다.

`Polls::StartSession`은 draft PollSession을 잠근 뒤 active Student를 number 순
PollParticipant snapshot으로 만들고 PollProgress, option/contest tally, `poll_started` event를
같은 session에 연결한다. PollParticipation은 시작 시 만들지 않으며 Poll 정의 status도 변경하지
않는다. 시작 시 첫 snapshot 학생을 current로 지정하고 ballot은 잠근다. 고정된 학생 투표 창을 연
뒤 operator 또는 global admin이 현재 학생의 ballot을 명시적으로 열고 잠글 수 있다. 열린 ballot은
각 contest의 PollOption을 하나씩 검증한 뒤 PollSession별 count-only tally를 transaction과 row lock
안에서 증가시키고 completed participation을 만든다. 성공하면 ballot을 잠그고 current를 유지한다.
교사는 현재 학생을 미참여로 확정하거나, 처리된 current를 유지한 상태에서 다음 미처리 학생을
number/id 순서로 명시적으로 지정한다. 자동 다음 학생 전환과 자동 종료는 의도적으로 사용하지 않으며,
마지막 학생까지 확정된 뒤 교사가 session을 명시적으로 종료한다. 종료 화면은 현재
`poll_session_id`에 속한 tally와 시작 당시 PollParticipant snapshot만으로 결과와 투표자 명단을
표시하고 개인별 선택 row는 저장하거나 표시하지 않는다. 교사 operation 화면과 고정 이름의 학생
창은 Turbo Stream으로 갱신하며 polling fallback도 제공한다. `Polls::SessionStatusCheck`가 draft,
in_progress, closed 단계의 정의·snapshot·진행·집계 무결성을 확인하고 실제 시작·ballot open·제출·
미참여·다음 학생·종료 service가 해당 조건으로 잘못된 action을 차단한다. 기존 ParticipantGroup 기반
`Polls::Start`와 legacy 직접 실행 route는 그대로 유지한다. 신규 PollSession의 중단·stopped 이력·
replacement session·재투표는 아직 구현되지 않았다.

Classroom·Student 관리 UI는 role 기반 Classroom scope와 일반 페이지 CRUD를 제공한다. admin은 모든
학교, manager는 소속 학교, 일반 teacher는 자신이 담임인 Classroom과 학생 명단만 관리한다. Student는
단일 또는 textarea bulk 방식으로 등록하고 hard delete 대신 비활성화·복구한다. 이 자료는 신규 Poll의
Classroom 선택과 시작 snapshot에 사용하며 ParticipantGroup·ParticipantSlot 변환은 수행하지 않는다.
다음 전환 작업은 legacy runtime 분리와 데이터 이관, PollSession 중단·replacement·재투표,
후보 사진과 historical/read_only 정책을 순서대로 다루는 것이다.

학교 교사 관리 UI는 기존 teacher 계정만 SchoolMembership의 `member`로 소속시키며 global admin만
`manager` 지정·해제를 수행한다. 같은 학교 manager는 미소속 teacher 추가와 일반 member의 안전한
소속 해제만 할 수 있다. 담당 Classroom이 있으면 membership 삭제를 차단하고 Classroom 설정으로
연결하며 User 생성·초대, 학교 간 자동 전근, 담임 일괄 배정은 제공하지 않는다.

관리 UI의 기본 자원 순서는 **School → Classroom → Teacher → Student**다. School 상세는 기본 정보,
대표 선생님과 소속 Classroom·Teacher의 진입점이고, Classroom 설정은 담임 배정의 유일한 위치이자
Student 관리의 parent다. Teacher 화면은 User 계정, SchoolMembership과 담당 Classroom을 함께
요약하며 Student는 Classroom 아래에서만 관리한다. 상단 메뉴는 역할에 따라 학교·교실·선생님으로
정리했고 대표 역할은 School 상세에만 둔다. Teacher 생성 시 School을 선택하면 member membership을
같은 transaction에서 만들며 Student bulk 입력은 30개의 번호·이름 행 form을 사용한다.

## 11. 상태 무결성과 운영 이벤트

### 11.1 시작 시 잠금

최초 세션이 시작될 때 다음을 잠근다.

- 대상 학급
- Contest
- Candidate
- Option
- 학생 명단 snapshot
- ballot flow
- 기권 정책
- 단일 후보 정책

시작 뒤 결과에 영향을 주는 설정의 추가·수정·삭제를 금지한다. 변경이 필요하면 진행
세션을 덮어쓰지 않고 중단·replacement 절차를 따른다.

### 11.2 세션 상태와 전체 결과

- `draft`: 준비 중이며 결과에서 제외한다.
- `in_progress`: 진행 중이며 결과에서 제외한다.
- `stopped`: 중단 이력이며 재개하거나 결과에 포함하지 않는다.
- `closed`: 종료 조건과 무결성 검사를 통과한 확정 세션이다.

학교 전체 결과에는 `closed` 세션만 포함한다. `draft`, `in_progress`, `stopped`는
모두 제외한다.

재투표 시 기존 stopped 세션과 새 replacement 세션을 모두 보존한다. 기존 Voter,
진행 상태, tally와 event를 삭제하거나 초기화하지 않는다. 같은 학급에 여러 이력이
있어도 최종 closed 세션만 전체 결과에 포함한다.

종료 직전에는 확정 Voter 수, 후보·선택지 집계 합계, 기권 수와 tally 연결의 숫자
일관성을 검사한다. 개인별 선택을 복원하거나 대조하지 않는다.

### 11.3 운영 이벤트

다음 중요 변경은 actor, 시각, 대상 세션과 선택을 노출하지 않는 문맥으로 보존한다.

- 세션 시작
- 일시정지
- 재개
- absent 처리
- 세션 중단
- 재투표 세션 생성
- 세션 종료
- 운영자 변경
- 복구 수행

일시정지/재개는 같은 in_progress 세션의 운영 제어다. stopped는 재개하지 않는 중단
이력이다. 새로고침, 재로그인이나 장치 재시작 뒤 복구는 DB의 세션, Voter와 진행
상태를 source of truth로 수행한다.

## 12. 역사 자료 export/import

기존 production DB 전체를 새 구조로 직접 migration하지 않는다.

```text
기존 production
→ 읽기 전용 export
→ 새 DB 생성
→ 새 구조 import
```

선택한 2026년 전교임원선거 기록만 이관한다. 기존 구조가 남아 있을 때 export 도구를
main에 먼저 반영하고, 새 DB에 조직·선거 구조를 만든 후 검증 가능한 import 절차로
적재한다.

역사 Election은 다음 상태로 import한다.

```text
status: closed
historical: true
read_only: true
```

역사 자료에서는 설정 수정, 후보 수정, 재개, 재투표, 삭제와 세션 초기화를 금지한다.
기존 stopped와 replacement 세션은 모두 보존하되 합계에는 최종 closed 세션만
포함한다. import 전후에 대상 학급, 세션 상태, Voter 상태 수, 후보별 집계와 최종
합계를 비교할 수 있어야 한다.

## 13. 단계적 전환 순서

1. 설계 문서를 확정한다.
2. 기존 구조용 2026년 선거 export 도구를 구현하고 main에 반영한다.
3. 장기 통합 브랜치 `rebuild/school-voting-platform`을 생성한다.
4. legacy `SchoolElection`을 제거한다.
5. 학교 조직 기반을 구현한다.
6. ElectionSession을 전환 기간의 Classroom dual-source 구조로 정리한다.
7. Poll 정의와 PollSession을 분리하고 전교투표 생명주기를 구현한다.
8. Election ID 6을 historical Poll로 import하고 검증한다.
9. Election runtime과 table을 제거한다.
10. Poll 전환 완료 후 `ParticipantGroup`을 제거한다.

현재 1~7단계의 신규 구조와 PollSession runtime까지 완료되었다. legacy `SchoolElection`
관리자 runtime, `SchoolElections::*` service, Poll 연결, legacy 모델과 DB table을 제거했고,
School·SchoolMembership·Classroom·Student 조직 기반과 ElectionSession의 Classroom·
ParticipantGroup dual-source 전환을 구현했다. PollSession foundation, 신규 Poll 정의와 최초 draft
Session 생성, 여러 Classroom 배정, Student snapshot, 감독형 제출·count-only 집계·참여 기록·
미참여·명시적 다음 학생·명시적 종료·Session별 결과, 담당 Session 목록, 전교투표 전체 결과,
Turbo Stream/polling 갱신과 단계별 상태 점검도 구현됐다. Poll은 전체 시작·종료 시각과 Poll-level
event를 기록하며 전교투표가 in_progress일 때만 담당 학급 Session을 시작할 수 있다.

아직 신규/legacy Poll runtime의 서버 측 분리, PollSession 중단·stopped 이력·replacement·재투표,
Election id=6 변환 리허설과 실제 적용 여부 결정, 운영 Poll 보존 범위 조사와 필요한 backfill이
남아 있다. 실제 Election id=6 운영 데이터에는 변환 task를 적용하지 않았다. 이관 뒤에야
ParticipantGroup·ParticipantSlot과 legacy Poll runtime을 제거할 수 있다. 신규 Election 기능은
추가하지 않으며 검증된 historical Poll 변환 뒤 Election runtime과 table을 제거한다. 재투표,
후보 사진, historical/read_only 표시는 후속 작업이다.

`ParticipantGroup`은 현재 Poll 원본 명단과 진행 흐름에 연결되어 있고 export 시 학생
명단의 출처가 될 수 있다. 이를 일찍 삭제하면 Poll 운영과 export 검증이 깨지고 새
Student/Voter 구조로 옮기지 못한 기록의 의미를 잃는다. 두 콘텐츠의 전환과 이관
검증이 끝날 때까지 호환 경계로 유지한다.

## 14. 확정된 설계와 후속 검토 사항

### 14.1 확정된 설계

- School을 조직과 권한의 최상위 경계로 사용한다.
- 전역 역할과 학교 역할을 User.role과 SchoolMembership.role로 분리한다.
- 학급-담임은 양쪽 모두 최대 하나이며 학급의 학교는 변경하지 않는다.
- Student는 독립 모델이고 User/Devise 계정이 아니다.
- Election/Poll, 범위, 진행 방식과 접속 방식을 독립 축으로 둔다.
- 대상 학급과 세션 투표자 snapshot을 공통 개념으로 다루되, `VotingTarget`·`Voter` 같은 공통
  추상화의 실제 도입은 후속 검토 대상으로 둔다.
- 학생별 선택을 저장하지 않고 참여 상태와 count-only 집계를 함께 갱신한다.
- 시작 뒤 설정을 잠그고 전체 결과에는 closed 세션만 포함한다.
- 중단·replacement 이력과 운영 이벤트를 보존한다.
- 새 DB에 선택한 2026년 기록만 읽기 전용 역사 자료로 import한다.

### 14.2 후속 검토 사항

- membership 이력의 정확한 상태와 유효 기간 표현
- 학년도 변경 시 Classroom/Student 승급·복사·비활성화 절차
- Candidate·tally 모델과 당선 결과 보존 방식
- `approval_rule`의 초기 규칙과 동률 처리
- 일시정지를 status 또는 별도 시각/flag 중 무엇으로 표현할지
- replacement 세션 연결 필드와 최종 세션 판정 제약
- tally 모델의 실제 이름과 DB 제약
- 이벤트 모델의 구체적인 테이블·필드 이름
- individual PIN 발급·폐기·보안 정책
- 2026년 export 형식, 식별자 매핑, 검산 보고서와 import 실패 처리

복잡한 결선, 복수 당선, 고급 득표율 규칙, Poll 복수 선택과 개별 PIN 투표는 후속
제품 범위이며 초기 재구축 완료 조건에 포함하지 않는다.
