# Student 학년도별 명단 운영 정책

## 목차

1. [문서 목적](#1-문서-목적)
2. [Classroom과 Student의 의미](#2-classroom과-student의-의미)
3. [새 학년도 운영](#3-새-학년도-운영)
4. [학년도 종료](#4-학년도-종료)
5. [Student 수정과 비활성화](#5-student-수정과-비활성화)
6. [Poll snapshot](#6-poll-snapshot)
7. [이 서비스에서 구현하지 않는 기능](#7-이-서비스에서-구현하지-않는-기능)

## 1. 문서 목적

이 문서는 `Classroom`과 `Student`를 한 학년도 동안 운영하고 과거 명단을
보존하는 기준을 정한다. 이 서비스는 학생의 장기 학적, 진급, 전학 이력을
관리하는 학교 행정 시스템이 아니다.

신규 PollSession은 active Student 명단을 시작 시 snapshot으로 복사한다. 기존
`ParticipantGroup`·`ParticipantSlot` legacy Poll 경로의 전환은
`docs/architecture/classroom_participant_group_transition.md`를 따른다.

## 2. Classroom과 Student의 의미

### 2.1 Classroom

`Classroom`은 특정 학교·학년도·학년·반의 1년 운영 단위다.

- `school_year`, `grade`, `class_label`로 학년도별 학급을 구분한다.
- `active: true`는 현재 운영 중인 학급을 뜻한다.
- `active: false`는 운영이 끝난 역사 학급을 뜻한다.
- 이전 Classroom을 다음 학년도로 수정하거나 재사용하지 않는다.
- 새 학년도 담임은 새 Classroom에 배정한다.

### 2.2 Student

`Student`는 특정 Classroom에서 사용하는 해당 학년도 학생 명단 한 행이다.

- 하나의 Classroom에 속한다.
- `number`, `name`, `active`를 가진다.
- 교사용 로그인 계정인 `User`와 분리한다.
- 학교 행정상의 장기 학생 신원 모델이 아니다.
- 다른 학년도 Student와 같은 실제 학생인지 추적하지 않는다.

### 2.3 active의 의미

`Classroom.active`와 `Student.active`는 서로 다른 상태다.

```text
Classroom.active
→ 해당 학년도의 학급이 현재 운영 대상인지 여부

Student.active
→ 해당 Classroom 명단에서 현재 사용하는 학생인지 여부
```

`Student.active: false`는 잘못 등록했거나 더 이상 그 Classroom 명단에서
사용하지 않는다는 뜻이다. 학교 전체 재학 상태, 진급, 전학 이력 또는 다음
학년도 등록 여부를 나타내지 않는다.

현재 운영 명단은 `Classroom.active = true`와 `Student.active = true`를
모두 만족하는 학생으로 구성한다.

## 3. 새 학년도 운영

새 학년도에는 다음 순서로 운영한다.

1. 교사가 새 Classroom을 생성한다.
2. 해당 학년도 학생을 새 Student로 등록한다.
3. 이 명단을 1년 동안 Poll·Election에 사용한다.

이전 학년도 Student를 복사하거나 이동하거나 연결하지 않는다. 같은 실제
학생이 다음 학년도에도 있더라도 새 Classroom에 새 Student 행으로 등록하며,
두 행 사이에 동일 학생 관계를 만들지 않는다.

## 4. 학년도 종료

학년도 종료 시 다음 상태 변경만 수행한다.

```text
Classroom.active = false
```

소속 Student를 일괄 inactive로 바꾸지 않는다. inactive Classroom 안에 active
Student가 남는 것은 정상이며, 해당 학급 운영 당시의 최종 명단을 보존한다.
과거 Classroom과 Student는 삭제하거나 다음 학년도 데이터로 이전하지 않는다.

## 5. Student 수정과 비활성화

같은 Classroom 안에서는 기존 Student의 다음 필드를 수정할 수 있다.

- `name`: 오타나 표시 이름 정정
- `number`: 출석번호 정정
- `active`: 명단 사용 여부 변경

`classroom_id`는 생성 후 변경할 수 없다. 이는 진급이나 반 이동 workflow를
지원하기 위한 규칙이 아니라 과거 명단 행이 실수로 다른 Classroom으로
옮겨지는 것을 막는 최소 안전장치다.

같은 Classroom에서는 `[classroom_id, number]`가 유일해야 한다. inactive
Student의 번호도 재사용하지 않으며, 다른 번호를 가진 동명이인은 허용한다.

일반 운영에서는 Student를 hard delete하지 않고 필요하면 inactive 처리한다.
명백한 오등록을 삭제하는 별도 기능은 현재 설계하거나 구현하지 않는다.

## 6. Poll snapshot

Student는 신규 PollSession 명단의 원본이다. 활동 시작 시 active Student의 번호와 이름을
`PollParticipant` snapshot으로 복사한다.

- 시작 후 Student의 이름, 번호 또는 active가 바뀌어도 기존 snapshot은 바꾸지 않는다.
- 완료되거나 중단된 Poll 기록을 Student 현재값으로 다시 작성하지 않는다.
- 기존 `ParticipantSlot` 기반 기록을 Student에 소급 연결하거나 변환하지 않는다.
- snapshot은 Student의 현재 상태와 독립된 당시 투표 명단 기록으로 보존한다.

## 7. 이 서비스에서 구현하지 않는 기능

이 서비스의 범위에는 다음 기능이 포함되지 않는다.

- 학생 진급 처리
- 반 이동 처리
- 전입·전출 이력 관리
- 학년도 간 동일 학생 연결
- 장기 학적 관리
- 이전 학년도 학생 자동 복사
- 학생 신원 통합
- 진급·이동·상태 전이 service
- 진급 대상 자동 추천과 반 편성 UI
- 학교 행정 시스템 수준의 학적 audit

새 학년도에는 새 Classroom과 새 Student 명단을 만드는 단순한 운영 원칙을
유지한다.
