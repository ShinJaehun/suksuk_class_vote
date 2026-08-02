# Student 생명주기와 학년도별 명단 보존 정책

## 목차

1. [문서의 목적과 지위](#1-문서의-목적과-지위)
2. [상태의 의미](#2-상태의-의미)
3. [학년도 종료와 진급](#3-학년도-종료와-진급)
4. [같은 학년도 반 이동](#4-같은-학년도-반-이동)
5. [전입·전출과 복귀](#5-전입전출과-복귀)
6. [이름과 출석번호 정정](#6-이름과-출석번호-정정)
7. [삭제와 보존](#7-삭제와-보존)
8. [Poll·Election snapshot](#8-pollelection-snapshot)
9. [동일 학생의 장기 식별](#9-동일-학생의-장기-식별)
10. [상태 전이 표](#10-상태-전이-표)
11. [금지 사항](#11-금지-사항)
12. [후속 구현 순서](#12-후속-구현-순서)
13. [후속 설계 사항](#13-후속-설계-사항)

## 1. 문서의 목적과 지위

이 문서는 한 학년도 Classroom의 학생 명단 행인 `Student`의 생성, 수정, 이동,
비활성화와 보존 정책을 정의하는 canonical architecture 문서다. 학년도 간 동일한
실제 사람을 표현하는 모델이 아니라 학년도별 명단 레코드의 생명주기를 다룬다.

```text
School
└── Classroom
    └── Student
```

Student는 교사용 로그인 계정인 User와 분리한다. 현재 Poll·Election runtime은 아직
ParticipantGroup·ParticipantSlot을 사용하며, 전환 순서는
`docs/architecture/classroom_participant_group_transition.md`를 따른다.

## 2. 상태의 의미

### 2.1 Classroom.active

`Classroom.active`는 해당 학년도의 학급이 현재 운영 대상인지 나타낸다.

- `true`: 현재 운영 중인 학급
- `false`: 종료된 학년도의 역사 학급
- 학년도 종료 시 Classroom을 삭제하지 않고 inactive로 전환한다.
- 새 학년도에는 기존 Classroom을 수정하지 않고 새 Classroom을 만든다.

### 2.2 Student.active

`Student.active`는 해당 Student가 그 Classroom 명단에서 유효한 구성원인지 나타낸다.

- `true`: 해당 학급 명단에 남아 있는 학생
- `false`: 전출, 반 이동 또는 중도 이탈로 해당 명단에서 빠진 학생
- 학교 전체의 현재 재학 상태가 아니며 다른 학년도 Student 상태와 자동 연결하지 않는다.

향후 runtime에서 현재 사용 가능한 명단은 두 조건을 모두 만족해야 한다.

```text
Classroom.active = true
Student.active = true
```

이 문서에서는 이를 위한 scope나 query method를 구현하지 않는다.

## 3. 학년도 종료와 진급

### 3.1 학년도 종료

- Classroom만 `active: false`로 변경한다.
- 소속 Student를 일괄 inactive로 바꾸지 않는다.
- Student.active는 해당 학년도 종료 시점에 그 명단에 남아 있었는지를 보존한다.
- Classroom 상태 변경 callback으로 Student 상태를 자동 변경하지 않는다.
- inactive Classroom 안의 active Student는 정상적인 역사 상태다.

```text
2026학년도 4학년 11반 — inactive
├── 1번 김학생 — active
├── 2번 이학생 — active
└── 3번 박학생 — inactive(학기 중 전출)
```

### 3.2 다음 학년도 진급

- 다음 학년도에는 새 Classroom을 만든다.
- 진급 학생마다 새 Student 행을 만든다.
- 이전 Student의 classroom_id나 active를 진급 때문에 변경하지 않는다.
- 이전 학년도와 새 학년도 Student는 서로 다른 명단 레코드다.

```text
2026학년도 4학년 11반 / 3번 / 홍길동
2027학년도 5학년 3반  / 8번 / 홍길동
```

현재 두 행을 동일한 실제 사람으로 직접 연결하지 않는다. 학년도 간 연결은 별도 안정
식별자 설계가 확정된 뒤 도입한다.

## 4. 같은 학년도 반 이동

- 기존 Student의 classroom_id를 대상 반으로 변경하지 않는다.
- 이전 Classroom의 Student를 `active: false`로 바꾼다.
- 대상 Classroom에 새 Student를 만들고 새 반의 출석번호를 부여한다.
- 이전 Student는 이전 반의 역사 명단으로 보존한다.

```text
2026학년도 4학년 1반 / 5번 / 홍길동 — inactive
2026학년도 4학년 2반 / 7번 / 홍길동 — active
```

장기적으로 Student.classroom_id는 생성 뒤 변경할 수 없는 불변조건으로 구현한다.
현재 문서 작업에서는 validation이나 migration을 추가하지 않는다.

## 5. 전입·전출과 복귀

### 5.1 전입

- 대상 Classroom에 active Student를 새로 만든다.
- 같은 이름의 Student가 있어도 자동 병합하지 않는다.
- 해당 Classroom에서 과거에도 사용되지 않은 출석번호를 부여한다.
- 전입 전 학교나 학급 정보는 현재 Student에 자동 저장하지 않는다.

### 5.2 전출과 중도 이탈

- Student를 삭제하지 않고 `active: false`로 바꾼다.
- 이름, 출석번호와 Classroom 관계를 유지한다.
- inactive Student가 가진 번호를 같은 Classroom에서 재사용하지 않는다.
- 이후 전입 학생에게는 다른 번호를 부여한다.

현재 모델과 DB의 `[classroom_id, number]` unique 제약은 active 여부와 관계없이 적용돼
이 정책을 보호한다.

### 5.3 같은 학급으로 복귀

- 같은 학년도, 같은 Classroom으로 복귀하면 기존 Student를 `active: true`로 되돌린다.
- 같은 Student 행과 기존 번호를 재사용하고 기본적으로 새 행을 만들지 않는다.
- 다른 Classroom으로 복귀하거나 재배정되면 새 Student를 만든다.
- 이름만으로 복귀 대상을 자동 탐색하지 않는다. 관리 UI나 service에서 명시적으로
  기존 행을 선택해야 한다.

## 6. 이름과 출석번호 정정

### 6.1 이름

오타, 개명, 띄어쓰기나 표시 이름 정정은 기존 Student.name을 수정한다. 이름 수정만으로
새 Student를 만들지 않는다.

### 6.2 출석번호

- 같은 Classroom 안의 입력 오류나 명단 정정은 기존 Student.number를 수정한다.
- 현재 또는 과거 Student가 이미 가진 번호로 변경할 수 없다.
- `[classroom_id, number]` unique 제약을 유지한다.
- 번호 정정만으로 새 Student를 만들지 않는다.

```text
같은 Classroom에서 번호 정정
→ 기존 Student.number 수정

다른 Classroom으로 이동
→ 기존 Student inactive + 대상 Classroom에 새 Student 생성
```

## 7. 삭제와 보존

일반 운영에서는 Student를 hard delete하지 않는다. 전출, 이동과 중도 이탈은 inactive로
처리하고 역사 명단을 보존한다.

hard delete는 다음 조건을 모두 만족하는 명백한 입력 실수에 한해 후속 관리 기능에서
별도로 검토한다.

- 실제 학생 레코드가 아니라 잘못 생성된 행임이 명확하다.
- 실제 Poll·Election 활동에 사용되지 않았다.
- 다른 기록의 source로 참조되지 않는다.
- 관리자가 명시적으로 삭제한다.

현재 `Classroom has_many :students, dependent: :restrict_with_error` 정책을 유지한다.
Student가 하나라도 있는 Classroom은 삭제하지 않으며 학년도 종료는 Classroom을
inactive로 전환한다. Student가 없는 명백한 오생성 Classroom만 삭제할 수 있다.

## 8. Poll·Election snapshot

Student는 향후 새 활동의 명단 원본이지만 활동 기록 자체는 아니다.

- 활동 시작 시 active Student의 번호와 이름을 `PollParticipant` 또는
  `ElectionVoter` snapshot으로 복사한다.
- 이후 Student의 이름, 번호, active나 학급이 바뀌어도 이미 생성된 snapshot은
  변경하지 않는다.
- 완료·중단된 활동을 Student 현재값으로 재작성하지 않는다.
- source association은 출처 추적 보조 정보이며 snapshot의 번호와 이름을 대체하지
  않는다.
- Student 삭제 여부와 무관하게 snapshot은 독립적으로 보존한다.
- 기존 ParticipantSlot 기반 snapshot도 Student로 소급 변환하지 않는다.

```text
Student.name 또는 number 수정
→ 이후 새 활동 명단에 반영

기존 PollParticipant.name/number
기존 ElectionVoter.name/number
→ 그대로 보존
```

## 9. 동일 학생의 장기 식별

현재 Student에는 안정적인 개인 식별자가 없다.

- 이름만으로 같은 실제 학생이라고 판단하지 않는다.
- 이름과 출석번호만으로 학년도 간 Student를 병합하지 않는다.
- 다른 Classroom의 Student를 자동 연결하지 않는다.
- 같은 Classroom의 동명이인을 허용한다.
- 성장·진급 이력이 필요하면 별도의 안정 식별자를 설계한다.

`person_id`, `student_identity_id`, 이전·다음 Student 연결, 교육행정 식별자나 생년월일
기반 식별은 이번 문서에서 결정하지 않는다. 동일인 식별을 위해 민감정보를 성급하게
추가하지 않는다.

## 10. 상태 전이 표

| 상황 | 기존 Student | 새 Student | Classroom |
| --- | --- | --- | --- |
| 학년도 종료 | 상태 유지 | 생성 안 함 | inactive |
| 다음 학년도 진급 | 유지 | 새 학년도 학급에 생성 | 새 Classroom 생성 |
| 같은 학년도 반 이동 | inactive | 대상 반에 생성 | 양쪽 모두 유지 |
| 전입 | 해당 없음 | 대상 반에 생성 | 유지 |
| 전출 | inactive | 생성 안 함 | 유지 |
| 같은 반 복귀 | active로 복구 | 기본적으로 생성 안 함 | 유지 |
| 이름·번호 정정 | 기존 행 수정 | 생성 안 함 | 유지 |
| 명백한 입력 실수 | 후속 정책에 따라 삭제 검토 | 생성 안 함 | 유지 |

## 11. 금지 사항

- 진급을 위해 기존 Student.classroom_id 변경
- 반 이동을 단순 classroom_id 수정으로 처리
- 학년도 종료 시 Student 일괄 inactive callback
- Student 비활성화 시 Classroom 상태 자동 변경
- 이름만으로 동일 학생 자동 병합
- inactive Student의 출석번호 재사용
- Student 수정 시 기존 PollParticipant 또는 ElectionVoter 일괄 갱신
- 전출 Student hard delete
- 기존 ParticipantSlot을 자동 추측해 Student로 병합
- production 데이터를 model callback으로 자동 전환

## 12. 후속 구현 순서

### 1단계 — Student 불변조건 보완

- 생성 뒤 classroom_id 변경 금지
- 같은 Classroom 복귀를 위한 active 전환 검증
- 현재 number unique 제약 유지
- model spec 보완

### 2단계 — 명단 관리 service 또는 정책

- Student 등록과 이름·번호 정정
- 비활성화와 재활성화
- 같은 학년도 반 이동
- 입력 실수 삭제 가능 여부 판정

### 3단계 — ParticipantSlot import

- 명시적으로 매핑된 Classroom에 Student 생성
- 이름만으로 병합하지 않음
- 번호 충돌과 모호한 레코드 보고
- 기존 Poll·Election snapshot 유지

### 4단계 — Election 전환

- active Classroom의 active Student에서 ElectionVoter snapshot 생성
- 기존 ElectionSession 보존

### 5단계 — Poll 전환

- active Classroom의 active Student에서 PollParticipant snapshot 생성
- 기존 Poll 보존

### 6단계 — 기존 명단 제거

- ParticipantGroup·ParticipantSlot runtime 의존 제거
- legacy table 제거

## 13. 후속 설계 사항

- 학년도 간 동일 학생 식별자
- 진급 대상 자동 추천과 반 편성 UI
- 전입·전출 사유 column
- 상태 변경 시각과 audit log
- 보호자 정보, 학생 로그인과 PIN
- 성별, 생년월일과 학생 사진
- hard delete UI와 관리자·교사 권한
- production 전환 시점
