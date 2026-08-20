# 학교 기반 투표 아키텍처

## 목적

이 문서는 현재 구현된 학교·학급·학생 구조와 Poll runtime의 canonical architecture를 정의한다.

## 조직 경계

`School`은 데이터 접근과 학교 운영 권한의 최상위 경계다.

```text
School
├── SchoolMembership ── User
├── Classroom ── Student
└── Poll ── PollSession ── PollParticipant
```

`User.role`은 global `admin`과 `teacher`를 사용한다. teacher의 학교 내부 역할은 SchoolMembership의 `member` 또는 `manager`다. manager는 별도 global role이 아니다.

Classroom은 학교·학년도·학년·반과 선택적 담임을 가진다. Student는 Classroom의 번호·이름·active 상태를 가진 명단 데이터이며 인증 주체가 아니다.

## 핵심 불변조건

- School을 넘는 Classroom·Student·Poll 관계를 만들지 않는다.
- active teacher 한 명은 active Classroom 하나만 담당한다.
- Student 번호는 Classroom 안에서 유일하다.
- 시작 뒤 결과에 영향을 주는 Poll 정의, 대상과 snapshot을 변경하지 않는다.
- 학생별 선택과 기권 여부를 이름에 연결하지 않는다.
- 전체 결과에는 current `closed` PollSession만 포함한다.
- stopped source와 replacement Session을 삭제하거나 덮어쓰지 않는다.
- 권한은 controller와 policy, 상태 무결성은 model과 service가 최종 검증한다.

## 계정과 권한

User는 `login_id`로 로그인한다. global admin은 전체 학교 범위를 관리한다. manager는 자기 학교의 teacher·Classroom·Student와 school-managed Poll을 관리한다. 일반 teacher는 담당 Classroom의 Student와 자신이 소유하거나 실제 운영하는 PollSession을 다룬다.

admin은 담임을 표현하기 위한 가상 Classroom에 연결되지 않는다. PollSession의 실제 운영자는 `operator` 관계로 명시하며 Classroom 담임과 동일할 필요는 없다.

세부 권한은 [역할과 권한](roles_and_permissions.md)을 따른다.

## Poll 정의

```text
Poll
├── PollContest
│   └── PollOption
└── PollSession (Classroom별 실행)
```

Poll은 제목, 유형, 항목·선택지, 기권 허용과 진행 방식 정책을 소유한다. 기권은 기본 허용하고 진행 방식은 기본 `teacher_confirmed`이며, `automatic`에서는 완료한 학생 화면의 확인을 거쳐 다음 대기 학생을 시작한다. 투표 시작 또는 실행 기록 생성 뒤에는 정책을 변경할 수 없다. 학급투표와 전교투표의 모든 PollSession은 이 Poll-level 정책을 함께 사용한다. PollSession은 학급별 학생 snapshot, 진행 포인터, 참여 상태와 tally를 소유한다. 같은 Poll을 여러 Classroom에서 실행해도 각 진행 상태와 집계는 PollSession으로 분리된다.

일반 학급투표는 `school_managed: false`, 전교투표는 `school_managed: true`다.

## PollSession 시작과 진행

draft PollSession 시작은 transaction 안에서 다음을 수행한다.

1. Session과 관련 상태를 정해진 순서로 lock한다.
2. active Student를 번호 순으로 PollParticipant에 복사한다.
3. PollProgress와 option·contest tally를 생성한다.
4. 첫 participant를 current로 지정하고 ballot을 잠근다.
5. Session을 `in_progress`로 전환하고 운영 event를 남긴다.

PollParticipant는 `number`, `name`, `position`의 당시 snapshot이다. 시작 뒤 Student가 수정되거나 inactive가 되어도 진행 중·종료된 Session의 명단은 바뀌지 않는다.

교사는 현재 학생의 ballot을 열고 잠근다. 학생은 한 번에 미완료 PollContest 하나를 제출한다. 선택 제출은 PollOptionTally를, 항목 기권은 PollContestTally를 증가시키며 PollContestCompletion과 같은 transaction에 저장한다. 어떤 선택을 했는지는 participant에 연결하지 않는다.

모든 항목을 처리한 학생은 completed 또는 abstained 참여 상태로 완료되며, 운영자가 처리한 absent는 미참여다. `teacher_confirmed`에서는 교사가 다음 학생 이동을 승인하고, `automatic`에서도 마지막 제출 직후 current participant를 바꾸지 않고 학생 완료 화면의 확인 요청이 기존 advance 절차를 실행한다. Session 종료는 항상 교사의 명시적 action이다.

## 전교투표

school-managed Poll은 대상 Classroom마다 PollSession을 가진다.

1. manager 또는 global admin이 draft Poll 정의와 대상 학급을 준비한다.
2. 준비 점검을 통과하면 parent Poll을 명시적으로 시작한다.
3. 담당 교사·지정 operator가 각 학급 PollSession을 개별 시작하고 운영한다.
4. manager와 admin은 학교 전체 진행을 조회한다.
5. 모든 current Session이 무결한 closed 상태일 때 parent Poll을 명시적으로 종료한다.
6. 결과는 current closed Session의 count-only tally를 합산한다.

manager의 school-managed Poll lifecycle 권한과 학급 PollSession의 실제 `operate?` 권한은 다르다. manager가 Session을 조회할 수 있어도 operator가 아니면 ballot·학생 진행 mutation을 수행할 수 없다.

Test Poll과 replacement 재투표도 원본과 이력을 보존한다. current execution은 replacement Session이 없는 Session으로 판단한다.

## 비밀투표와 표시

PollParticipation 내부 상태는 진행 무결성을 위해 `completed`, `absent`, `abstained`를 사용한다. 학생별 UI는 다음처럼 표시한다.

- `completed` → `투표 완료`
- `abstained` → `투표 완료`
- `absent` → `미참여`
- participation 없음 → `대기`

누가 기권했는지는 교사 명단과 진행 화면에 표시하지 않는다. 익명 결과에서는 Contest별 기권 수를 표시할 수 있다. 자세한 계약은 [비밀투표와 집계](privacy_and_tally.md)를 따른다.

## Snapshot과 역사 표시

PollSession은 `classroom_name_snapshot`, `operator_name_snapshot`을 저장한다. 이 값은 당시 운영 기록의 정체성이다.

- 학급명·운영자명은 snapshot-first로 표시한다.
- 결과의 학년 그룹은 classroom_name_snapshot에서 읽은 역사적 학년을 우선한다.
- snapshot이 없거나 기존 형식을 해석할 수 없을 때만 현재 연관 값을 fallback으로 사용한다.
- 현재 Classroom 학년·반이나 User 이름 변경으로 과거 snapshot을 덮어쓰지 않는다.

## Realtime과 수렴

DB가 authoritative state이며 Turbo Stream/Action Cable은 빠른 화면 갱신 수단이다.

- 실제 operator와 `operate?`가 허용된 사용자는 진행 중 Session의 `operation_screen`을 구독한다.
- 조회 전용 school manager는 operation stream을 구독하지 않고 5초 HTTP polling으로 진행 화면을 갱신한다.
- 학생 ballot은 `ballot_screen`을 구독하고 5초 Frame polling과 10초 recovery 확인을 함께 사용한다.
- schoolwide 관리 화면은 active global admin과 같은 학교의 active manager에게만 user별 recipient stream을 제공한다.
- broadcast 누락, Cable 재연결 또는 오래 열린 화면은 polling/recovery가 DB 상태로 수렴시킨다.

Realtime payload는 권한의 근거가 아니다. mutation은 매 요청마다 policy와 상태 guard를 통과해야 한다.

## 상태 무결성과 결과

PollSession 상태는 draft, in_progress, closed, stopped다. 종료 전에 SessionStatusCheck가 정의, participant snapshot, progress, completion, participation과 tally 수치를 검증한다.

제출은 PollSession과 PollProgress의 lock 순서를 지키며 중복 요청에도 하나의 completion과 한 번의 tally 증가만 허용한다. schoolwide batch 작업은 Poll과 Session을 안정적인 순서로 잠근다.

결과는 개인 선택 row가 아니라 PollOptionTally와 PollContestTally를 사용한다. stopped·draft·in_progress Session은 확정 결과에서 제외하며 replacement 이전 source도 보존한다.

복구 원칙은 [복구와 무결성](recovery_and_integrity.md)을 따른다.
