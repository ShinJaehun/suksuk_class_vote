# Classroom·Student 전환과 ParticipantGroup 제거 계획

## 목차

1. [문서의 목적과 지위](#1-문서의-목적과-지위)
2. [현재 구조와 의존성](#2-현재-구조와-의존성)
3. [최종 원본 구조](#3-최종-원본-구조)
4. [ParticipantGroup의 과도기 위치](#4-participantgroup의-과도기-위치)
5. [Poll 전환 정책](#5-poll-전환-정책)
6. [Election 전환 정책](#6-election-전환-정책)
7. [기존 데이터 전환 원칙](#7-기존-데이터-전환-원칙)
8. [2026년 실제 운영 데이터](#8-2026년-실제-운영-데이터)
9. [단계적 전환 순서](#9-단계적-전환-순서)
10. [금지 사항](#10-금지-사항)
11. [후속 결정 사항](#11-후속-결정-사항)

## 1. 문서의 목적과 지위

이 문서는 새 학교 조직 구조인 `Classroom`·`Student`와 기존 명단 구조인
`ParticipantGroup`·`ParticipantSlot`의 전환 정책을 확정하는 canonical architecture
문서다. 최종 원본, snapshot 보존, 데이터 매핑과 legacy 명단 제거 순서를 정의한다.

현재 runtime 설명과 이 문서가 충돌하면 전환 목표에는 이 문서를 우선 적용한다.
Election runtime 전환 관련 본문은 제거 전 설계 기록이며 현재는 DB 복원·변환 참고 자료로만 사용한다.
전환 중에는 현재 Poll의 동작을 보존하며, 각 단계가 완료되기 전에 기존
association이나 table을 제거하지 않는다.

## 2. 현재 구조와 의존성

현재 신규 runtime과 legacy runtime은 다음 경계로 함께 존재한다.

```text
새 조직 구조                     현재 명단·투표 구조

School                           ParticipantGroup
└── Classroom                    └── ParticipantSlot
```

`Classroom`은 학교, 학년도, 학년, 반과 선택적 담임을 표현하고 `Student`는 해당
학년도의 학생 명단을 가진다. 신규 PollSession은 Classroom의 active Student를 시작 시
snapshot으로 사용한다. ElectionSession은 Classroom 또는 기존 ParticipantGroup 중 정확히 하나를
명단 source로 사용한다. Classroom 기반 session은 active Student를, legacy ParticipantGroup 기반
session은 ParticipantSlot을 읽어 ElectionVoter snapshot을 만든다.

`ParticipantGroup`은 `User`가 소유하며 일반 교사 명단과 학교 선거 명단을 구분한다.
`ParticipantSlot`은 그룹 안에서 유일한 번호와 이름을 가진다. 현재 의존성은 다음과
같다.

- legacy Poll 생성·실행 경로는 교사가 소유한 `ParticipantGroup`을 사용한다.
- legacy `Polls::Start`는 그룹의 `ParticipantSlot`을 번호순으로 읽어 `PollParticipant`를
  생성한다. `PollParticipant`는 번호와 이름 snapshot 및 선택적 원본 slot 참조를
  가진다.
- Classroom 기반 ElectionSession은 active Student를, legacy ElectionSession은 ParticipantSlot을
  사용해 ElectionVoter snapshot을 만든다.
- Poll과 Election의 controller, service, view, policy, factory와 spec 전반이 기존
  명단 구조에 의존한다. seed나 별도 import·운영 script의 직접 의존은 확인되지 않았다.

따라서 신규 runtime 전환이 끝났더라도 legacy Poll 보존 범위 조사와 필요한 PollSession backfill,
Election ID 6 변환과 legacy runtime 분리가 끝나기 전에는 ParticipantGroup·ParticipantSlot을 제거할 수 없다.

## 3. 최종 원본 구조

최종 학교 조직과 명단 원본은 다음 구조로 통일한다.

```text
School
├── SchoolMembership
└── Classroom
    └── Student
```

### 3.1 Classroom

`Classroom`은 특정 학교·학년도·학년·반을 나타내는 조직 레코드다.

- 학년도 종료 뒤 삭제하지 않고 `active: false`로 보존한다.
- 새 학년도에는 기존 Classroom을 수정하지 않고 새 Classroom을 생성한다.
- 담임은 선택적으로 한 명을 배정하며 동일 교사는 동시에 최대 한 Classroom만 맡는다.
- 학교·학년도·학년·반 조합과 생성 뒤 학교 불변 조건을 유지한다.

### 3.2 Student

`Student`는 Classroom에 속한 학년도별 학생 명단 레코드로 구현되었다.

- 반드시 하나의 Classroom에 속한다.
- 해당 학년도 학생 명단의 원본이다.
- 교사용 로그인 계정인 `User`와 분리한다.
- 학생에게 `SchoolMembership`을 만들지 않는다.
- 새 학년도에는 새 Classroom과 Student 명단을 만든다.
- 이전 학년도 Student를 복사·이동·연결하지 않는다.

상세 운영 정책은 `docs/architecture/student_lifecycle_policy.md`를 따른다.

## 4. ParticipantGroup의 과도기 위치

`ParticipantGroup`은 최종 학교 조직 모델이 아니며 `ParticipantSlot`도 최종 학생
원본이 아니다. 두 모델은 기존 Poll 명단과 현재 Election runtime을 유지하기 위한
과도기 호환 구조다.

- 새 기능에서 ParticipantGroup을 장기 원본으로 확장하지 않는다.
- 전환 전에는 현재 Poll과 Election 동작을 깨지 않도록 유지한다.
- Student, Election 명단과 Poll 명단 전환이 끝나면 두 모델을 제거한다.

최종 제거 방향은 확정됐으며 존치 여부를 다시 선택 사항으로 두지 않는다.

## 5. Poll 전환 정책

### 5.1 과도기

- 기존 Poll은 ParticipantGroup 기반으로 계속 동작한다.
- Classroom 또는 Student 추가만을 이유로 기존 Poll association을 다시 연결하지 않는다.
- 시작된 Poll의 `PollParticipant`는 원본 slot 변경과 분리된 snapshot으로 보존한다.
- 기존 Poll 데이터와 tally, participation, progress, event를 다시 작성하지 않는다.

### 5.2 최종 목표

- 새 Poll은 Classroom의 현재 Student 명단에서 `PollParticipant` snapshot을 생성한다.
- 시작 뒤 Classroom이나 Student가 변경돼도 snapshot의 번호와 이름은 바뀌지 않는다.
- 완료된 Poll 기록은 원본 Student의 이동·비활성화·삭제와 무관하게 보존한다.
- Poll이 ParticipantGroup을 원본 명단으로 요구하지 않게 한 뒤 기존 생성 경로를
  중단한다.
- 최종 cutover 뒤 ParticipantGroup·ParticipantSlot association과 source 참조를
  제거한다.

현재 `PollParticipant`가 snapshot 역할을 수행하므로 같은 책임의 새 모델을 추가하지
않는다. Student 출처를 추적할 필요가 있으면 snapshot의 독립성을 해치지 않는 선택적
source 연결을 Poll 전환 단계에서 설계한다.

## 6. Election 전환 정책

`ElectionVoter`는 선거 세션 시작 시점의 voter snapshot이다.

- 기존 ElectionVoter를 Student로 소급 변환하지 않는다.
- 완료·중단된 ElectionSession의 voter, participation, tally, progress와 event를
  변경하거나 삭제하지 않는다.
- 새 ElectionSession은 Classroom을 대상으로 생성하고, 명단 확정 시 Classroom의
  Student에서 ElectionVoter snapshot을 만든다.
- 시작 뒤 Student 이름, 출석번호나 학급이 바뀌어도 ElectionVoter의 번호, 이름과
  순서는 유지한다.

현재 ElectionSession은 Classroom 또는 ParticipantGroup 중 정확히 하나를 직접 source로 사용하는
dual-source 상태다. 신규 세션 전환은 완료됐으며 제거 전에는 다음 경계를 마무리한다.

1. 새 세션의 대상과 교사 검증을 Classroom 기준으로 전환한다.
2. 새 voter 생성 원본을 Student로 전환한다.
3. 기존 세션은 현재 voter snapshot과 표시용 학급 정보를 보존한다.
4. 과거 세션을 새 Classroom·Student에 억지로 연결하지 않은 채 ParticipantGroup과
   ParticipantSlot 없이 읽을 수 있게 한다.
5. 새 Election 명단 생성에서 기존 구조를 사용하지 않는 것을 확인한 뒤 source 연결을
   제거한다.

## 7. 기존 데이터 전환 원칙

### 7.1 자동 추측 금지

학교, 학년도, 학년, 반, 동일 학생 여부 또는 교사 membership 일치가 명확하지 않으면
migration이 임의로 매핑하거나 보정하지 않는다. 모호한 레코드는 별도 검토 목록으로
보고한다.

### 7.2 Classroom 매핑

기존 명단의 Classroom 후보는 다음 식별자로 매핑한다.

```text
school_id
school_year
grade
class_label
```

현재 ParticipantGroup에는 학교·학년·반 관련 필드가 일부 있지만 학년도가 없고 일반
교사 명단은 구조화된 학교·학년·반을 보장하지 않는다. 이름 문자열을 무조건 파싱하지
않으며, 필요한 경우 명시적인 mapping 입력이나 관리자 확인 import 단계를 둔다.

### 7.3 Student 생성

- 각 ParticipantSlot에서 Student 생성 후보를 만든다.
- 이름만으로 동일 학생을 병합하지 않는다.
- 출석번호와 이름이 같아도 다른 학년도나 Classroom이면 병합하지 않는다.
- 학년도 간 동일 학생 연결이나 진급 처리는 하지 않는다.

## 8. 2026년 실제 운영 데이터

- 실제 전교임원선거 결과와 ElectionVoter snapshot은 수정하지 않는다.
- 과거 Election을 새 Classroom이나 Student에 강제로 소급 연결하지 않는다.
- 필요한 경우 기존 저장값 또는 별도의 표시용 학급 snapshot을 보존한다.
- 완료·중단 세션과 관련 participation, tally, progress, event를 그대로 유지한다.
- 운영 DB와 Active Storage 백업은 별도의 역사 자료로 유지한다.
- 데이터 전환 migration이 백업 파일을 직접 읽거나 변형하지 않는다.

## 9. 단계적 전환 순서

### 1단계 — 완료

- School
- SchoolMembership
- Classroom과 학년도별 구조
- 담임 배정 불변조건

### 2단계 — Student 기반 — 완료

- Student 모델·table과 Classroom association 추가
- Student factory와 model spec 추가
- 기존 Poll/Election runtime 유지

### 3단계 — Election 변환 도구 구현, 운영 적용·legacy Poll backfill 미완료

- ParticipantGroup에서 Classroom으로의 명시적 mapping
- ParticipantSlot에서 Student 생성
- 모호한 데이터 보고
- 기존 Poll과 Election 기록 유지

### 4단계 — 신규 Election 명단 생성 경로 전환 — 완료

- 새 ElectionSession이 Classroom을 참조
- Classroom의 Student에서 ElectionVoter snapshot 생성
- 기존 ElectionSession과 snapshot 기록 보존
- ParticipantGroup 기반 새 Election 명단 생성 중단

ElectionSession과 voter snapshot의 구체적인 호환 구조 및 전환 순서는
`docs/architecture/election_classroom_cutover_plan.md`를 따른다.

### 5단계 — 신규 Poll 명단 생성 경로 전환 — 완료

- 새 Poll이 Classroom의 Student에서 PollParticipant snapshot 생성
- 기존 Poll 데이터 보존
- ParticipantGroup 기반 새 Poll 생성 중단

### 현재 남은 전환 순서

1. 운영 백업 복원본에서 Election ID 6 Classroom 변환 dry-run
2. `APPLY=1` 리허설과 invariant·화면 결과 검산
3. historical/read_only 기반
4. Election ID 6 historical Poll 변환과 후보 사진 이관
5. 운영 DB의 기존 Poll 보존 범위 조사
6. 필요한 legacy Poll의 PollSession backfill
7. 신규 PollSession runtime과 legacy ParticipantGroup Poll runtime 분리
8. Election runtime과 table 제거
9. ParticipantGroup·ParticipantSlot 제거
10. 전체 데이터 검산과 운영 전환

## 10. 금지 사항

- 기존 ElectionVoter snapshot 재작성
- 완료된 투표 결과 재집계
- 이름만으로 학생 자동 병합
- ParticipantGroup 이름 문자열의 무조건적인 학년·반 파싱
- 새 Classroom을 기존 Poll에 일괄 연결
- Student 구현과 동시에 ParticipantGroup 즉시 삭제
- production 데이터를 model callback으로 자동 변환
- migration에서 외부 백업 파일 직접 읽기

## 11. 후속 결정 사항

다음은 해당 구현 단계에서 별도로 확정한다.

- guardian 또는 보호자 정보
- 학생 로그인 방법
- ParticipantGroup 제거 migration timestamp
- UI와 권한
- import 화면과 production 전환 일정
