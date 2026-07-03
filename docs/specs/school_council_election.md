# 전교임원선거 운영 기준

## 목적

이 문서는 현재 배포 대상인 전교임원선거의 canonical spec이다.
학급 단위 일반 투표인 `Poll`과 구분하여, 여러 학급의 투표를 하나의
`Election`으로 운영하는 기준을 정리한다.

세부 모델 구조와 비밀투표 원칙은 다음 문서를 함께 참고한다.

- `docs/architecture/election_engine.md`
- `docs/architecture/privacy_and_tally.md`
- `docs/architecture/recovery_and_integrity.md`
- `docs/architecture/roles_and_permissions.md`

## 적용 범위

전교임원선거는 다음 두 유형을 사용한다.

- 정규 전교임원선거(`school_council`): 회장, 6학년 부회장, 5학년 부회장
  항목을 자동 생성한다.
- 단일 항목 전교임원선거(`school_council_single_contest`): 비상 재투표 등을 위해
  admin이 입력한 항목 하나만 생성한다. 항목명은 필수이며 후보자 수 정책과
  후보 등록, 투표, 집계 흐름은 정규 전교임원선거와 같다.

두 유형 모두 다음 구조를 사용한다.

- parent `Election`: 전교임원선거 전체 운영 단위
- `ElectionContest`: 회장, 부회장 등 선출 항목
- `ElectionCandidate`: 항목별 후보와 선택적 후보 사진
- `ElectionSession`: 한 학급의 실제 투표 운영 단위
- `ElectionVoter`: 시작 시점에 고정한 학급 투표자 snapshot
- `ElectionParticipation`: 투표 완료, 기권, 미참여, 대기 상태
- tally: 후보별 득표와 항목별 기권의 count-only 집계
- `ElectionEvent`: 선택 내용이 아닌 운영 이벤트 기록

기존 Poll-backed `school_election` 기능은 이 문서의 기준 대상이 아니다.
실제 선거가 끝난 뒤 별도 리팩터링에서 정리할 legacy 후보로만 다룬다.

## 역할별 화면 흐름

### Admin

Admin은 다음 순서로 전교임원선거를 준비하고 확정한다.

1. `/admin/election_rosters`에서 학교별 공식 투표자 명단을 준비한다.
2. `/admin/elections`에서 전교임원선거를 만든다.
3. 선출 항목, 후보, 후보 사진을 등록한다.
4. 학급별 담당 교사와 공식 명단을 `ElectionSession`으로 배정한다.
5. 준비 상태를 확인하고 parent `Election`을 시작한다.
6. `/admin/elections/:id`에서 학급별 진행 상태를 확인한다.
7. 사고가 발생하면 전체 선거 중단 또는 특정 학급 재투표를 선택한다.
8. 모든 현재 학급 세션이 종료되면 admin이 명시적으로 `선거 종료`를 누른다.
9. parent `Election`이 `closed`가 된 뒤 결과 집계 화면을 확인한다.

### Teacher

Teacher는 본인에게 배정된 학급 세션만 운영한다.

1. `/polls`에서 배정된 전교임원선거 카드를 확인한다.
2. 학급 세션 상세에서 `선거 시작`을 눌러 학급 투표를 시작한다.
3. 현재 학생의 투표 화면을 열고 투표를 감독한다.
4. 투표 완료 또는 미참여 처리 뒤 다음 학생으로 이동한다.
5. 모든 학생 처리가 끝나면 학급 세션을 종료한다.
6. stopped 세션은 상세에서 당시 진행 수치, 명단, 이벤트를 확인한다.
7. stopped 세션이 더 이상 교사 목록에 필요하지 않으면 상세에서 `투표 삭제`를 눌러
   본인의 `/polls` 목록에서만 숨긴다.

## 상태 전이

### Parent Election

```text
draft -> in_progress -> closed
                     -> stopped
```

- `draft`: 항목, 후보, 공식 명단, 학급 세션을 준비한다.
- `in_progress`: 각 학급 교사가 세션을 시작하고 진행한다.
- `closed`: admin이 모든 현재 학급 세션 종료를 확인한 뒤 명시적으로 확정한다.
- `stopped`: 운영 사고로 전체 선거를 중단한 상태다.

학급 세션이 모두 종료되어도 parent `Election`은 자동으로 종료되지 않는다.
정상 종료는 admin의 명시적인 `선거 종료`로만 수행한다.

## 준비 상태 구성 변경

- 선거 이름은 parent `Election`이 `draft`일 때만 수정할 수 있다.
- 대상 학교는 parent `Election`이 `draft`이고 등록된 `ElectionSession`이 없을 때만
  변경할 수 있다.
- 학급 세션의 등록, 개별 등록 해제, 학년 단위 등록 해제는 parent `Election`이
  `draft`일 때만 가능하다.
- 학급 세션 등록 화면은 학급을 기본 선택하지 않으며 admin이 필요한 학급만 선택한다.
- 구성 변경 제한은 화면 표시뿐 아니라 policy와 controller에서도 검증한다.

### Admin 모의 후보자 생성

- admin은 선거 정보 수정 화면에서 `draft` 선거에만 모의 후보자를 생성할 수 있다.
- 후보자가 없는 각 contest에는 사진 없이 한국식 가짜 이름의 후보자 15명을 번호
  1번부터 순서대로 생성한다.
- 후보자가 한 명이라도 등록된 contest는 전체를 건너뛰며 기존 후보 등록 흐름과
  데이터를 변경하지 않는다.
- 정규 전교임원선거는 세 contest에 총 45명, 단일 항목 전교임원선거는 한 contest에
  15명을 생성한다.
- `in_progress`, `closed`, `stopped` 선거는 화면과 서버 양쪽에서 생성을 차단한다.

### ElectionSession

```text
draft -> in_progress -> closed
                     -> stopped
```

- `draft`: 담당 교사가 아직 학급 투표를 시작하지 않은 상태다.
- `in_progress`: snapshot을 기준으로 학급 투표를 진행한다.
- `closed`: 모든 학생 처리를 마치고 학급 투표를 종료한 상태다.
- `stopped`: 전체 중단 또는 재투표로 중단된 과거 세션이다.

`stopped` 세션은 재개하지 않는다. 특정 학급 재투표가 필요하면 기존 세션을
`stopped`로 보존하고 같은 선거, 학급, 교사의 새 `draft` 세션을 만든다.

## 학급 투표 운영

- 학급 세션 시작 시 공식 명단을 `ElectionVoter` snapshot으로 고정한다.
- 투표 화면은 현재 학생에게만 열리며 서버의 ballot 상태 검사를 통과해야 한다.
- 반복 클릭은 기존 ballot 창을 우선 사용한다.
- ballot 창을 닫은 뒤에는 서버 상태를 잠그고 다시 열 수 있어야 한다.
- 후보 선택 또는 기권 제출은 transaction으로 participation과 tally를 함께 반영한다.
- 제출 완료 뒤 ballot은 잠기며 교사 화면에는 다음 학생 진행 동작이 표시된다.
- 참여하지 않은 학생은 교사가 미참여로 처리한다.
- 마지막 학생까지 완료, 기권 또는 미참여로 확정되어야 학급 세션을 종료할 수 있다.
- 실시간 broadcast를 놓친 경우에도 교사 진행 영역은 polling으로 DB 상태를 다시 읽는다.

## 중단과 재투표

전체 선거 중단과 학급 재투표는 서로 다른 동작이다.

- 전체 중단은 parent `Election`을 `stopped`로 만들고 미종료 학급 세션을 중단한다.
- 재투표는 admin만 실행할 수 있으며 parent `Election`이 `in_progress`여야 한다.
- 재투표 대상은 `in_progress` 또는 `closed` 학급 세션이다.
- 기존 세션, voter, participation, tally, event는 삭제하지 않는다.
- 기존 세션은 `stopped`, replacement 세션은 `draft`가 된다.
- 담당 교사는 replacement 세션에서 다시 학급 투표를 시작한다.
- 재투표는 parent `Election` 상태를 변경하지 않는다.

Admin 선거 상세에서는 현재 세션과 stopped 이력을 구분해 표시한다.
같은 학급에 stopped 이력이 여러 개 있어도 감사와 확인을 위해 모두 보존한다.

## Admin 비상 초기화

stopped 세션과 voter, participation, tally, event를 보존하는 것이 일반 원칙이다.
다만 선거 구성 또는 운영 데이터 전체를 폐기하고 준비부터 다시 해야 하는 비상 상황에는
admin 전용 비상 초기화를 명시적 예외로 허용한다.

- parent `Election` 상태와 관계없이 admin만 실행할 수 있으며 teacher에게 위임하지 않는다.
- 선거 상세의 선거 단위 위험 작업에서 선거 이름을 확인 입력한 뒤 실행한다.
- transaction 안에서 해당 선거의 모든 `ElectionSession`을 `destroy!`하고 parent
  `Election`을 `draft`로 되돌린다.
- voter, participation, progress, event, tally는 `ElectionSession` association의
  dependent destroy 정책에 따라 함께 삭제한다.
- `Election`, `School`, `ElectionContest`, `ElectionCandidate`, `User`,
  `ParticipantGroup`, `ParticipantSlot`은 삭제하지 않는다.
- 실행 actor, 선거, 삭제한 세션 수를 운영 로그에 남긴다.

## Teacher 목록 숨김

Teacher의 stopped 세션 숨김은 실제 삭제가 아니다.

- 본인에게 배정된 stopped 세션 상세에서만 실행할 수 있다.
- `hidden_from_teacher_at`만 기록한다.
- 이후 해당 teacher의 `/polls` 목록에서만 제외한다.
- admin 선거 상세의 stopped 이력에는 계속 표시한다.
- 세션 상세 직접 접근, voter, participation, tally, event는 그대로 유지한다.
- draft, in_progress, closed 세션과 다른 교사의 세션에는 적용할 수 없다.

## 종료와 결과 집계

결과 화면은 parent `Election`이 `closed`인 경우에만 접근할 수 있다.

- 후보별 합산 대상은 `closed` `ElectionSession`뿐이다.
- 학급별 집계 목록도 `closed` 세션만 표시한다.
- 완료 학급의 denominator 역시 results에 포함된 closed 세션 기준이다.
- draft, in_progress, stopped 세션은 결과 합산과 results 화면에서 모두 제외한다.
- stopped 세션 때문에 잠정 집계 또는 제외 카드가 표시되지 않는다.
- stopped 이력은 results가 아니라 admin 선거 상세에서 확인한다.

## 직접 URL 접근

- 로그인하지 않은 사용자는 선거 운영 화면에 접근할 수 없다.
- Teacher는 본인에게 배정된 세션 상세만 볼 수 있다.
- stopped 세션을 교사 목록에서 숨긴 뒤에도 담당 teacher의 직접 상세 접근은 유지한다.
- stopped 상세는 읽기 전용이며 투표 시작, ballot 열기, 다음 학생, 미참여, 종료 동작을 제공하지 않는다.
- Admin은 학급 세션 상세와 stopped 이력을 확인할 수 있다.
- parent `Election`이 closed가 아니면 results 직접 접근을 선거 상세로 돌려보낸다.

## 배포 기준

운영 배포 전 점검은
`docs/ops/school_council_election_deploy_checklist.md`를 따른다.
