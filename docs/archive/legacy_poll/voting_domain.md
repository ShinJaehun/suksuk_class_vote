# Voting Domain

> 이 문서는 `ParticipantGroup` / `ParticipantSlot` 기반 legacy Poll runtime의 역사 문서다.
> 현재 신규 학급투표와 전교투표의 구현 기준으로 사용하지 않는다.
> 현재 구조는 `docs/architecture/current_system.md`와 `docs/architecture/school_voting_platform.md`를 우선 참고한다.

## 목적

이 문서는 `쑥쑥교실투표`의 현재 투표 도메인 모델 관계를 정리하기 위한 architecture 문서다.

현재 구현된 핵심 모델은 `ParticipantGroup`, `ParticipantSlot`, `Poll`, `PollOption`,
`PollOptionTally`, `PollParticipant`, `PollParticipation`, `PollProgress`, `PollEvent`이다.
`PollParticipant`는 투표 시작 시점에 생성되는 투표 참여자 명단 snapshot 모델이다.

---

## 현재 구현된 명단 모델

### ParticipantGroup

`ParticipantGroup`은 교사가 관리하는 원본 학생 명단이다.

현재 의미:

- 교사가 투표에 사용할 학생 명단 묶음
- `teacher` 역할의 `User`가 소유하는 데이터
- 투표 생성 전 명단 정리 단계에서 이름 수정과 삭제 가능
- 이미 시작된 투표의 진행 상태와 직접 연결되지 않음

`admin`은 전체 참여자 그룹에 접근할 수 있고, `teacher`는 본인이 소유한 참여자 그룹에만 접근한다.

### ParticipantSlot

`ParticipantSlot`은 `ParticipantGroup` 안의 출석번호/이름 row다.

현재 의미:

- 학생 계정이 아님
- 학생 로그인, PIN, 개인 단말과 연결되지 않음
- 원본 명단의 출석번호와 이름을 표현
- 같은 `ParticipantGroup` 안에서 출석번호가 중복될 수 없음

`ParticipantSlot`은 원본 명단 row이며 투표 진행 상태가 아니다.
투표 진행은 시작 시 생성되는 `PollParticipant` snapshot과 `PollProgress`를 기준으로 다룬다.

---

## 투표 생성 시 ParticipantGroup 선택

투표를 만들 때 교사는 본인이 소유한 `ParticipantGroup` 중 하나를 선택한다.

초기 학급 투표 MVP의 우선 흐름:

- teacher는 본인 `ParticipantGroup`만 선택 가능
- admin은 전체 `ParticipantGroup`을 볼 수 있지만, 초기 학급 투표 생성 UI는 teacher 본인 그룹 선택 흐름을 우선
- 투표 생성 화면에는 `ParticipantGroup` 이름과 학생 수를 함께 보여준다.
- 학생이 1명도 없는 `ParticipantGroup`은 투표 생성에 사용할 수 없다.

빈 명단으로 투표를 만들면 선택지 등록, 투표 진행, 종료 조건이 모두 애매해지므로 투표 생성 단계에서 막는다.

현재 구현은 학생이 1명 이상 등록된 `ParticipantGroup`만 투표 생성에 사용할 수 있다.

---

## 현재 구현된 투표 모델

### Poll

`Poll`은 교사가 만든 투표 단위다.

현재 구현 상태:

- `title`을 가진다.
- 생성한 `User`를 가진다.
- 원본 `ParticipantGroup`을 연결한다.
- 상태는 `draft`, `in_progress`, `closed`를 가진다.
- index/new/create/show와 start/submit/advance/close 흐름이 구현되어 있다.
- 선택지 등록/수정/삭제는 nested `PollOption` 흐름으로 구현되어 있다.
- 투표 시작은 선택지 2개 이상인 흐름에 한해 구현되어 있다.
- 투표 진행, 참여 처리, 결과 집계가 구현되어 있다.

`Poll` 생성 시점에는 투표 참여자 명단 snapshot을 만들지 않는다.
투표 시작 시점에 snapshot을 만든다.

`Poll#kind`는 활동 유형을 구분한다.

```text
election: 0
discussion: 10
debate: 20
```

현재 생성 UI에는 `선거`, `토의`만 노출한다.
내부 kind는 `debate`를 지원하지만, 찬성/반대 자동 선택지 생성 전까지 `토론`은 생성 UI에 노출하지 않는다.

### Poll 상태 전이 설계

현재 구현된 `Poll` 상태는 `draft`, `in_progress`, `closed`이다.

현재 의미:

- `draft`는 투표 준비 중 상태다.
- `draft` 상태에서는 투표 제목, `ParticipantGroup` 선택, 선택지 등록/수정/삭제가 가능하다.
- `draft` 상태에서는 아직 `PollParticipant` snapshot이 없고 원본 `ParticipantGroup`을 직접 참조한다.
- `in_progress`는 투표가 시작되어 투표 참여자 명단 snapshot이 생성된 상태다.
- 교사용 진행, 선택 제출, 참여 처리, 집계가 구현되어 있다.

`Poll` enum은 다음과 같다.

```text
draft: 0
in_progress: 10
closed: 20
```

상태 전이:

```text
draft -> in_progress -> closed
```

설계 기준:

- `ready` 상태는 초기 MVP에서 두지 않는다.
- 초기 MVP에서는 `draft`에서 바로 `in_progress`로 시작한다.
- `in_progress`로 전이하기 전에 후보자와 명단 조건을 반드시 검증한다.
- `closed`는 투표 종료와 결과 확정 상태다.

### Poll 시작 조건 초안

투표 시작 기능은 `Polls::Start` service로 구현되어 있다.

`Poll` 시작 시점에는 최소 다음 조건을 검증한다.

- `Poll`이 `draft` 상태일 것
- 연결된 `ParticipantGroup`에 `ParticipantSlot`이 1명 이상 있을 것
- 선택지가 2개 이상 있을 것
- 선택지 이름이 모두 유효할 것
- 투표 참여자 명단 snapshot이 아직 생성되지 않았을 것

선거 유형의 후보자 수 정책 검토 항목:

- 후보자 0명은 선거를 시작할 수 없다.
- 후보자 1명은 일반적으로 무투표 당선 처리할 수 있다.
- 다만 학교나 선거 규정에 따라 후보자 1명이어도 찬성/반대 투표를 진행할 수 있다.
- 후보자 2명 이상은 여러 후보 중 선택하는 일반 경쟁 투표로 본다.

현재 구현은 후보자 2명 이상인 일반 경쟁 투표만 start를 허용한다.
후보자 1명 정책은 별도 mode 없이 단순 시작 처리하지 않는다.
현재 구현은 후보자 1명인 선거를 시작하지 않고, 무투표 당선/찬반 투표 정책 결정 후 지원 예정이라는 안내를 제공한다.

### PollOption

`PollOption`은 특정 `Poll`에 속한 선택지다.
선거에서는 후보자, 토의에서는 의견, 토론에서는 입장으로 표시한다.

현재 구현 상태:

- `Poll`에 속한다.
- 선택지 이름과 투표 안의 번호를 가진다.
- 선택지 이름은 필수다.
- 선택지 번호는 같은 투표 안에서 중복될 수 없다.
- 선택지 번호는 서버에서 자동 부여하며, 삭제 후 재정렬하지 않는다.
- draft 상태 투표에서만 선택지 추가/수정/삭제가 가능하도록 controller guard를 둔다.

후보자 사진, 출석번호 연계, 선거 시작 후 수정 예외 처리는 아직 구현하지 않는다.

---

## 원본 참조와 snapshot 정책

`Poll`이 원본 `ParticipantGroup`을 계속 직접 참조하면, 선거 생성 뒤 원본 명단 변경이 이미 만든 선거에 영향을 줄 수 있다.

snapshot 없이 원본 명단을 직접 진행 기준으로 삼을 때의 예상 문제:

- 선거 생성 후 학생이 추가되거나 삭제되면 투표 대상이 바뀜
- 출석번호 변경이나 삭제가 진행 순서와 복구 상태에 영향을 줌
- 투표 시작 후 이름이 바뀌면 결과 보존과 감사 가능성이 약해짐

따라서 선거의 안정성과 복구 가능성을 위해 투표 참여자 명단 snapshot을 만드는 방향을 우선 검토한다.

권장 방향 초안:

- `ParticipantGroup`은 원본 명단으로 유지
- `Poll` 생성 시 `ParticipantGroup`을 선택
- `Poll` 생성 시점에는 원본 `ParticipantGroup`만 연결
- `draft` 상태에서도 원본 `ParticipantGroup` 이름 수정과 `ParticipantSlot` 학생 추가/수정/삭제는 가능
- 단, draft `Poll`이 현재 참조 중인 `ParticipantGroup` 자체 삭제는 차단
- `Poll` 시작 시점에 원본 `ParticipantGroup`의 `ParticipantSlot`들을 복사해 투표 참여자 snapshot 생성
- 시작 버튼을 누른 순간의 명단을 투표 참여자 명단으로 고정
- 이후 원본 `ParticipantGroup`이 바뀌어도 이미 시작된 `Poll`에는 영향을 주지 않음
- `PollProgress`과 투표 진행 상태는 원본 `ParticipantSlot`이 아니라 투표 참여자 snapshot row를 기준으로 삼음

### PollParticipant snapshot 모델

투표 참여자 명단 snapshot 모델은 `PollParticipant`로 구현되어 있다.

의미:

- `PollParticipant`는 원본 `ParticipantSlot`의 snapshot 복사본이다.
- `PollParticipant`는 선거 안에서 실제 투표 대상이 되는 학생 row다.
- 학생 계정이 아니다.
- 원본 `ParticipantSlot`이 수정되거나 삭제되어도 이미 시작된 `PollParticipant`에는 영향을 주지 않는다.

이유:

- 선거 안에서 실제 투표 대상이 되는 사람을 의미하기 쉽다.
- 원본 `ParticipantSlot`과 구분된다.
- 이름이 너무 길지 않다.

컬럼 초안:

- `poll:references, null: false, foreign_key: true`
- `source_participant_slot:references, null: true, foreign_key to participant_slots`
- `number:integer, null: false`
- `name:string, null: false`

DB index:

- `[poll_id, number]` unique
- `[poll_id, source_participant_slot_id]` unique

컬럼과 index 이유:

- `number`는 선거 안의 투표 진행 순서를 고정한다.
- `name`은 시작 시점의 이름을 보존한다.
- `source_participant_slot_id`는 원본 명단 추적용 링크다.
- 원본 `ParticipantSlot`이 삭제되면 `source_participant_slot_id`는 `nil`이 될 수 있다.
- 같은 원본 `ParticipantSlot`이 같은 `Poll`에 중복 snapshot되면 안 된다.

초기 `PollParticipant`에는 `status`를 두지 않는다.

이유:

- 출석번호 진행 상태와 실제 투표 결과는 분리해야 한다.
- 투표 진행 상태는 `PollProgress` 또는 `VoteSession` 설계에서 다룰 가능성이 크다.
- `PollParticipant`는 우선 고정된 투표 참여자 명단 역할에 집중한다.

후속 투표 진행 설계에서 `waiting`, `voting`, `voted`, `abstained` 같은 상태가 필요하면 다시 검토한다.

### Polls::Start service 설계

선거 시작 로직은 controller에 길게 두지 않고 `Polls::Start` service object로 분리되어 있다.

service 이름 후보:

- `PollStarter`
- `StartPoll`
- `Polls::Start`

구현 이름은 `Polls::Start`이다.

이유:

- namespace를 통해 `Poll` 관련 service임이 명확하다.
- 나중에 `Polls::Close`, `Polls::Tally` 같은 흐름으로 확장하기 쉽다.

`Polls::Start` 책임:

- `Poll`이 `draft` 상태인지 확인
- 후보자가 있는지 확인
- 후보자 수와 ballot mode 정책 확인
- `participant_group`에 `participant_slots`가 있는지 확인
- `poll_participants` snapshot이 아직 없는지 확인
- transaction 안에서 `PollParticipant` snapshot 생성
- transaction 안에서 `Poll` 상태를 `in_progress`로 변경
- 실패 시 전체 rollback
- 성공/실패 결과를 controller가 처리할 수 있게 반환

start action 위치 초안:

```ruby
resources :elections, only: %i[index show new create] do
  post :start, on: :member
  resources :candidates, only: %i[new create edit update destroy]
end
```

이 route는 구현되어 있다.

### snapshot 생성 무결성 원칙

snapshot 생성은 `Polls::Start`에서 구현되어 있다.

구현 원칙:

- `Poll` 시작 시 transaction 안에서 snapshot 생성과 상태 변경을 함께 처리한다.
- 하나라도 실패하면 선거 시작 전체가 실패해야 한다.
- 이미 snapshot이 있으면 중복 생성하지 않아야 한다.
- 시작 이후 후보자 추가/수정/삭제는 금지하는 방향이다.
- 시작 이후 선거에 연결된 snapshot 명단 수정도 금지한다.

복구/무결성 관점:

- snapshot은 투표 중 새로고침, 재부팅, 재로그인 이후에도 동일한 투표 순서를 복구하는 기준이 된다.
- 원본 `ParticipantGroup`이 아니라 투표 참여자 snapshot을 기준으로 투표 진행 상태를 계산한다.
- 출석번호 진행 상태와 실제 투표 결과는 분리되어야 한다.

snapshot 모델명, 컬럼, `Poll`과의 association은 구현되어 있다.

---

## 투표 진행 상태 모델링

이번 단계에서 구현하지는 않지만, 다음 구현의 기준이 되는 투표 진행 상태 원칙은 아래와 같이 둔다.

### PollParticipant의 책임

`PollParticipant`는 투표 참여자 고정 명단이다.

책임:

- 선거 시작 시점의 투표 대상 학생 row를 나타낸다.
- 시작 시점의 출석번호와 이름을 보존한다.
- 원본 `ParticipantSlot`이 바뀌어도 이미 시작된 선거의 투표 대상이 바뀌지 않게 한다.
- 후속 투표 진행 상태 모델이 참조할 기준 row가 된다.

비책임:

- 실제 투표 결과를 저장하지 않는다.
- 출석번호 진행 상태를 직접 저장하지 않는다.
- 후보자 선택 결과를 저장하지 않는다.
- `waiting`, `voting`, `completed`, `absent`, `abstained` 같은 진행 상태를 현재 모델에 두지 않는다.

이 원칙을 지키는 이유는 고정 명단, 출석번호 진행 상태, 실제 투표 결과를 분리하기 위해서다.

### 출석번호 진행 상태와 실제 투표 결과 분리

교사가 보는 진행 상태와 실제 표는 분리한다.

예:

```text
1번 김민준 대기
2번 이서연 투표 중
3번 박지호 완료
```

이 정보는 “누가 투표 차례인지”, “누가 완료되었는지”를 복구하기 위한 운영 상태다.
반면 실제 투표 결과는 “어떤 후보가 몇 표를 받았는지” 또는 “익명 표 기록이 무엇인지”를 다루는 별도 데이터다.

분리 이유:

- 비밀투표를 보장한다.
- 중단 후 진행 위치를 복구할 수 있다.
- 같은 학생의 중복 제출을 막을 수 있다.
- 운영 상태와 결과 집계를 각각 감사할 수 있다.

출석번호 진행 상태가 `poll_option_id` 같은 실제 선택 결과와 직접 연결되면 누가 누구에게 투표했는지 추적할 수 있다.
따라서 진행 상태 모델은 `PollParticipant`를 참조하더라도, 실제 후보 선택 결과와 직접 결합하지 않도록 설계한다.

### 진행 상태 모델 후보

#### 후보 A: PollProgress

의미:

- 선거 진행소 또는 투표 진행 정보 전체 상태를 나타낸다.
- 초기 학급 MVP에서는 `Poll` 1개에 `PollProgress` 1개가 자연스럽다.
- 현재 어느 `PollParticipant`가 투표 중인지, 현재 진행 위치가 어디인지 관리하기 좋다.
- 교사용 진행 화면과 잘 맞는다.

주의:

- `Poll`도 `status`를 가지므로, `PollProgress` 상태가 중복되지 않도록 범위를 좁혀야 한다.
- 전교 선거 확장 시에는 한 `Poll`에 여러 `PollProgress`이 필요할 수 있다.

#### 후보 B: VoteSession

의미:

- 개별 학생의 투표 시도 또는 제출 세션에 가깝다.
- 학생 투표 화면에 들어간 순간부터 제출까지의 transient 상태를 다루기 좋다.

주의:

- 초기 MVP처럼 교사 장치 하나에서 학생을 순서대로 진행하는 흐름에서는 처음부터 복잡할 수 있다.
- 제출 token, open session, 재제출 방지까지 함께 설계해야 하므로 도입 시점을 신중히 잡는다.

#### 후보 C: PollProgress

의미:

- 이름만 보면 선거 진행 상태를 직관적으로 표현한다.

주의:

- 도메인 용어로는 다소 일반적이다.
- 교사용 투표 진행 정보, 학생 투표 화면, 전교 선거 확장까지 포괄하기에는 의미가 흐려질 수 있다.

### 권장 방향

초기 MVP에서는 `PollProgress`을 투표 진행 상태 모델로 사용한다.

권장 이유:

- 교사가 장치 하나로 선거를 진행하는 흐름과 잘 맞는다.
- `PollParticipant` snapshot 명단 위에서 현재 진행 위치를 복구하기 쉽다.
- 후속 전교 선거 확장에서도 “학급별 투표 진행 정보” 개념으로 확장할 수 있다.

`VoteSession`은 학생 투표 화면과 제출 흐름이 복잡해질 때 후속으로 검토한다.
예를 들어 signed token, open session, 제출 중복 방지, 화면 새로고침 복구가 필요해지는 시점에 별도 모델로 도입할 수 있다.

### PollProgress 최종 구조

초기 MVP의 투표 진행 상태 모델은 `PollProgress`다.

의미:

- 하나의 `Poll`을 실제로 진행하는 투표 진행 정보 또는 진행 상태 컨테이너다.
- 초기 학급 선거 MVP에서는 `Poll` 1개당 `PollProgress` 1개를 둔다.
- 전교 선거 확장 시에는 한 `Poll`에 여러 학급별 `PollProgress`을 둘 수 있다.

책임:

- 특정 `Poll`의 투표 진행 상태를 나타낸다.
- 현재 투표 중인 `PollParticipant`를 가리킨다.
- 새로고침, 재로그인, PC 재부팅 후에도 현재 투표 순서를 복구할 수 있게 한다.
- teacher가 다음 학생으로 진행할 수 있게 한다.
- `PollParticipant` snapshot 명단을 기준으로 진행한다.
- 원본 `ParticipantGroup` 또는 `ParticipantSlot`을 직접 참조하지 않는다.

비책임:

- 실제 후보자 선택 결과를 저장하지 않는다.
- 후보자별 득표수를 저장하지 않는다.
- 개별 학생이 어떤 후보를 선택했는지 저장하지 않는다.
- 최종 집계 계산을 담당하지 않는다.
- 익명 vote record를 저장하지 않는다.

현재 주요 컬럼:

- `poll:references, null: false, foreign_key: true`
- `current_poll_participant:references, null: true, foreign_key to poll_participants`
- `status:integer, null: false, default: 0`
- `started_at:datetime`
- `closed_at:datetime`

DB index:

- `[poll_id]` unique

이유:

- 초기 MVP에서는 `Poll` 1개당 `PollProgress` 1개다.
- `current_poll_participant_id`는 현재 위치 복구 기준이다.
- `started_at`과 `closed_at`은 진행 시간 기록과 후속 감사에 도움이 된다.

status:

```text
active: 0
closed: 10
```

`ready` 상태는 두지 않는다.

이유:

- `Poll`이 이미 `draft`, `in_progress`, `closed` 상태를 가진다.
- `PollProgress`은 `Poll`이 `in_progress`가 된 뒤 생성 또는 초기화된다.
- 따라서 `PollProgress`은 `active`부터 시작하면 충분하다.
- `PollProgress.closed`는 `Poll.closed`와 함께 맞춘다.

### PollProgress 생성 시점

`Poll` start 성공 시 `PollProgress`을 함께 생성한다.

흐름:

1. `Polls::Start` transaction 안에서 `PollParticipant` snapshot 생성
2. `Poll` 상태를 `in_progress`로 변경
3. `PollProgress` 생성
4. `current_poll_participant`를 첫 번째 `PollParticipant`로 설정

`Polls::Start` 안에서 snapshot, 상태 변경, `PollProgress` 생성을 같은 transaction으로 처리한다.

### PollParticipant별 진행 상태 위치

선택지 A: `PollParticipant`에 `progress_status` 추가

- 장점: 단순하다.
- 단점: `PollParticipant`가 고정 명단 역할을 넘어 진행 상태까지 갖게 된다.

선택지 B: 별도 `PollParticipantProgress` 또는 `PollingSlot` 모델 추가

- 장점: 고정 명단과 진행 상태를 분리할 수 있다.
- 단점: 모델 수와 join이 늘어난다.

선택지 C: `PollProgress`이 current pointer만 가지고, 완료 여부는 별도 vote receipt 또는 record에서 판단

- 장점: 초기 구현을 작게 유지할 수 있다.
- 단점: 중단 복구와 상태 표시가 복잡해질 수 있다.

권장:

- `PollParticipant` 자체에는 진행 상태를 넣지 않는다.
- `PollProgress`은 `current_poll_participant_id`만 가진다.
- 완료 상태는 `PollParticipation`에서 관리한다.
- `PollProgress`은 현재 위치 복구를 담당하고, 완료 여부는 `PollParticipation`으로 판단한다.
- 고정 명단과 진행 상태를 분리한다는 원칙은 유지한다.

### 다음 참여자 진행 정책

teacher가 “다음 참여자”를 누르면 다음 흐름을 따른다.

- 현재 `current_poll_participant`를 기준으로 다음 number의 `PollParticipant`를 찾는다.
- 다음 `PollParticipant`가 있으면 `PollProgress.current_poll_participant`로 설정한다.
- 다음 `PollParticipant`가 없으면 모든 학생 투표가 끝난 상태로 보고 종료/집계 단계로 넘어갈 수 있다.

현재 참여자가 완료, 미참여, 기권 중 하나로 확정된 경우에만 다음 참여자로 이동한다.

### 실제 투표 결과 모델

정책:

- 개별 vote row가 `poll_participant_id`와 `poll_option_id`를 동시에 저장하면 누가 누구에게 투표했는지 연결될 수 있다.
- 비밀투표를 우선하면 출석번호 진행 상태와 실제 선택 결과를 분리해야 한다.
- 현재 구현은 별도 개별 vote row를 만들지 않는다.
- transaction 안에서 “해당 `PollParticipant`는 완료 처리”와 “선택지 득표 count 증가”를 함께 처리한다.
- `PollEvent`에는 선택지 id/name/number를 저장하지 않는다.

### 투표 제출 트랜잭션 원칙

투표 제출은 반드시 transaction으로 처리한다.

최소 원칙:

- 현재 투표 대상 `PollParticipant`가 맞는지 확인한다.
- 아직 완료되지 않은 학생인지 확인한다.
- 선택한 선택지가 해당 `Poll`의 선택지인지 확인한다.
- 완료 상태 변경과 득표 반영을 같은 transaction에서 처리한다.
- 실패 시 전체 rollback한다.
- 새로고침이나 중복 클릭으로 같은 학생이 두 번 제출되지 않도록 unique constraint 또는 lock을 검토한다.

### 중단 복구 원칙

후속 구현에서 교사가 브라우저를 새로고침하거나 PC가 재부팅되어도 다음을 복구해야 한다.

- 현재 `Poll`
- `Poll` 상태
- `PollParticipant` snapshot 명단
- 현재 투표 순서
- 완료된 학생 목록
- 다음 투표할 학생

복구 기준은 원본 `ParticipantGroup`이 아니라 `PollParticipant` snapshot과 투표 진행 상태 모델이어야 한다.
초기 MVP에서는 `PollProgress.current_poll_participant_id`가 현재 위치 복구의 1차 기준이다.
`current_poll_participant`가 있으면 해당 학생 위치로 복구한다.
`current_poll_participant`가 없으면 첫 번째 `PollParticipant` 또는 다음 미완료 `PollParticipant`를 계산하는 방향을 검토한다.

---

## 수정 제한 정책

### 선거와 연결되기 전 ParticipantGroup

선거와 연결되기 전의 `ParticipantGroup`은 원본 명단 정리 단계로 본다.

허용 방향:

- 참여자 그룹 이름 수정
- 참여자 그룹 삭제
- 학생 1명 추가
- 학생 여러 명 추가
- 학생 이름 수정
- 학생 삭제

번호 재정렬은 투표 진행 순서와 연결되므로 별도 정책 없이는 구현하지 않는다.

### 선거 생성 후

원본 `ParticipantGroup` 수정은 가능하더라도 이미 생성된 선거에는 영향을 주지 않는 방향이 안전하다.

이를 위해 투표 시작 시점에 투표 참여자 snapshot을 생성한다.
draft 선거는 아직 snapshot이 없으므로 원본 명단 수정은 허용하되, 현재 참조 중인 원본 `ParticipantGroup` 자체 삭제만 차단한다.

### 선거 시작 후

이미 시작된 선거의 투표 진행 기준은 원본 명단이 아니라 `PollParticipant` snapshot이다.
따라서 `in_progress` / `closed` 선거가 있어도 원본 `ParticipantGroup` 이름 수정, 학생 추가, 학생 이름 수정, 학생 삭제, 원본 명단 삭제는 가능하다.
원본 명단 변경은 이미 시작된 선거의 투표 순서와 투표 대상에 영향을 주지 않는다.

금지 방향:

- 선거에 연결된 `PollParticipant` snapshot 명단 수정
- 참여자별 후보 선택 저장/표시
- 진행 중 선택지별 집계 노출

### 투표 종료 후

투표 종료 후에는 결과 보존과 감사 가능성을 우선한다.

종료된 선거도 `PollParticipant` snapshot과 선거 시작 당시 그룹명 snapshot이 보존 기준이다.
원본 `ParticipantGroup` 또는 `ParticipantSlot`이 수정/삭제되어도 종료된 선거의 투표 참여자 명단은 `PollParticipant.number/name` 기준으로 유지한다.
단, draft 선거는 아직 snapshot이 없고 원본 `ParticipantGroup`을 직접 참조하므로 해당 원본 명단 자체 삭제를 차단한다.
이 삭제 차단은 비밀투표나 결과 보존 때문이 아니라, 준비 중인 `Poll`이 필수 명단 설정을 잃지 않게 하는 안전장치다.

---

## 후속 설계 범위

다음 모델은 아직 구현하지 않는다.

- `PollProgress`
- `VoteSession`
- `Tally`

다음 구현 전에 결정할 항목:

- 후보자 1명 선거의 처리 방식
- `ballot_mode`를 선거 시작 구현 전에 추가할지 여부
- 선거 시작 후 후보 수정 제한의 예외 정책
- 완료된 학생 목록 또는 receipt를 어떤 모델로 둘지 여부
- 실제 투표 결과를 집계 count 중심으로 둘지, 익명 기록을 함께 둘지 여부

다음 구현 순서:

1. `PollProgress` 모델 추가
2. `Polls::Start`에서 `PollProgress` 생성
3. `Poll` show에 `PollProgress` 상태 표시
4. 교사용 진행 화면 초안
5. 다음 학생 진행 action
6. 투표 제출 모델/transaction 설계
7. 중복 제출 방지 spec
8. 결과 집계 화면 추가
