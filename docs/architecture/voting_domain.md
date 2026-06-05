# Voting Domain

## 목적

이 문서는 `쑥쑥교실투표`의 투표 도메인 모델 관계를 구현 전에 정리하기 위한 architecture 문서다.

현재 구현된 모델은 `VoterGroup`, `VoterSlot`, `Election`, `Candidate`, `ElectionVoter`이다.
`PollingStation`, `VoteSession`, `Tally`는 아직 구현하지 않았다.
`ElectionVoter`는 선거 시작 시점에 생성되는 선거용 명단 snapshot 모델이다.

---

## 현재 구현된 명단 모델

### VoterGroup

`VoterGroup`은 교사가 관리하는 원본 학생 명단이다.

현재 의미:

- 교사가 선거에 사용할 학생 명단 묶음
- `teacher` 역할의 `User`가 소유하는 데이터
- 선거 생성 전 명단 정리 단계에서 이름 수정과 삭제 가능
- 아직 선거 진행 상태와 직접 연결되지 않음

`admin`은 전체 투표자 그룹에 접근할 수 있고, `teacher`는 본인이 소유한 투표자 그룹에만 접근한다.

### VoterSlot

`VoterSlot`은 `VoterGroup` 안의 출석번호/이름 row다.

현재 의미:

- 학생 계정이 아님
- 학생 로그인, PIN, 개인 단말과 연결되지 않음
- 원본 명단의 출석번호와 이름을 표현
- 같은 `VoterGroup` 안에서 출석번호가 중복될 수 없음

현재 단계의 `VoterSlot`은 선거의 투표 진행 상태가 아니다.
투표 진행 상태는 후속 `Election`/`PollingStation` 설계에서 별도 모델이나 snapshot 기반 row로 다룬다.

---

## 선거 생성 시 VoterGroup 선택

학급 선거를 만들 때 교사는 본인이 소유한 `VoterGroup` 중 하나를 선택한다.

초기 학급 선거 MVP의 우선 흐름:

- teacher는 본인 `VoterGroup`만 선택 가능
- admin은 전체 `VoterGroup`을 볼 수 있지만, 초기 학급 선거 생성 UI는 teacher 본인 그룹 선택 흐름을 우선
- 선거 생성 화면에는 `VoterGroup` 이름과 학생 수를 함께 보여주는 방향
- 학생이 1명도 없는 `VoterGroup`은 선거 생성에 사용할 수 없도록 하는 방향을 검토

빈 명단으로 선거를 만들면 후보 등록, 투표 진행, 종료 조건이 모두 애매해지므로 선거 생성 단계에서 막는 쪽이 안전하다.

현재 구현은 학생이 1명 이상 등록된 `VoterGroup`만 선거 생성에 사용할 수 있다.

---

## 현재 구현된 선거 모델

### Election

`Election`은 교사가 만든 선거 단위다.

현재 구현 상태:

- `title`을 가진다.
- 생성한 `User`를 가진다.
- 원본 `VoterGroup`을 연결한다.
- 상태는 `draft`, `in_progress`, `closed`를 가진다.
- index/new/create/show만 구현되어 있다.
- 후보자 등록/수정/삭제는 nested `Candidate` 흐름으로 구현되어 있다.
- 선거 시작은 후보자 2명 이상 일반 경쟁 투표에 한해 구현되어 있다.
- 투표 진행, 결과 집계는 아직 구현하지 않았다.

`Election` 생성 시점에는 선거용 명단 snapshot을 만들지 않는다.
선거 시작 시점에 snapshot을 만든다.

### Election 상태 전이 설계

현재 구현된 `Election` 상태는 `draft`, `in_progress`, `closed`이다.

현재 의미:

- `draft`는 선거 준비 중 상태다.
- `draft` 상태에서는 선거 제목, `VoterGroup` 선택, 후보자 등록/수정/삭제가 가능하다.
- `in_progress`는 선거가 시작되어 선거용 명단 snapshot이 생성된 상태다.
- 아직 교사용 투표 진행, 학생 투표 제출, 집계는 구현하지 않았다.

`Election` enum은 다음과 같다.

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
- `closed`는 투표 종료/집계 단계에서 후속 구현한다.

현재는 `draft -> in_progress` 시작 전이만 구현되어 있다.
`closed` 전이는 투표 종료/집계 단계에서 후속 구현한다.

### Election 시작 조건 초안

선거 시작 기능은 `Elections::Start` service로 구현되어 있다.

`Election` 시작 시점에는 최소 다음 조건을 검증한다.

- `Election`이 `draft` 상태일 것
- 연결된 `VoterGroup`에 `VoterSlot`이 1명 이상 있을 것
- 후보자가 2명 이상 있을 것
- 후보자 이름이 모두 유효할 것
- 선거용 명단 snapshot이 아직 생성되지 않았을 것

후보자 수 정책 검토 항목:

- 후보자 0명은 선거를 시작할 수 없다.
- 후보자 1명은 일반적으로 무투표 당선 처리할 수 있다.
- 다만 학교나 선거 규정에 따라 후보자 1명이어도 찬성/반대 투표를 진행할 수 있다.
- 후보자 2명 이상은 여러 후보 중 선택하는 일반 경쟁 투표로 본다.

현재 구현은 후보자 2명 이상인 일반 경쟁 투표만 start를 허용한다.
후속 `Election` 설계에서는 단순히 후보자 수만 보지 않고, 선거 방식 또는 투표 방식 개념을 검토한다.

컬럼명 후보:

- `election_mode`
- `ballot_mode`

모드 후보:

- `competitive`: 여러 후보 중 선택
- `uncontested`: 1명 후보 무투표 당선
- `approval`: 1명 후보 찬성/반대 투표

컬럼명과 모드명은 아직 확정하지 않는다.
초기 구현에서 어느 모드를 지원할지도 후속 설계에서 결정한다.

후보자 1명 정책은 `ballot_mode` 없이 단순 시작 처리하지 않는다.
현재 구현은 후보자 1명인 선거를 시작하지 않고, 무투표 당선/찬반 투표 정책 결정 후 지원 예정이라는 안내를 제공한다.

### Candidate

`Candidate`는 특정 `Election`에 속한 후보자다.

현재 구현 상태:

- `Election`에 속한다.
- 후보자 이름과 선거 안의 후보 번호를 가진다.
- 후보자 이름은 필수다.
- 후보 번호는 같은 선거 안에서 중복될 수 없다.
- 후보 번호는 서버에서 자동 부여하며, 삭제 후 재정렬하지 않는다.
- draft 상태 선거에서만 후보자 추가/수정/삭제가 가능하도록 controller guard를 둔다.

후보자 사진, 출석번호 연계, 선거 시작 후 수정 예외 처리는 아직 구현하지 않는다.

---

## 원본 참조와 snapshot 정책

`Election`이 원본 `VoterGroup`을 계속 직접 참조하면, 선거 생성 뒤 원본 명단 변경이 이미 만든 선거에 영향을 줄 수 있다.

예상 문제:

- 선거 생성 후 학생이 추가되거나 삭제되면 투표 대상이 바뀜
- 출석번호 변경이나 삭제가 진행 순서와 복구 상태에 영향을 줌
- 투표 시작 후 이름이 바뀌면 결과 보존과 감사 가능성이 약해짐

따라서 선거의 안정성과 복구 가능성을 위해 선거용 명단 snapshot을 만드는 방향을 우선 검토한다.

권장 방향 초안:

- `VoterGroup`은 원본 명단으로 유지
- `Election` 생성 시 `VoterGroup`을 선택
- `Election` 생성 시점에는 원본 `VoterGroup`만 연결
- `Election` 시작 시점에 원본 `VoterGroup`의 `VoterSlot`들을 복사해 선거용 투표자 snapshot 생성
- 시작 버튼을 누른 순간의 명단을 선거용 명단으로 고정
- 이후 원본 `VoterGroup`이 바뀌어도 이미 시작된 `Election`에는 영향을 주지 않음
- `PollingStation`과 투표 진행 상태는 원본 `VoterSlot`이 아니라 선거용 snapshot row를 기준으로 삼는 방향을 우선 검토

### ElectionVoter snapshot 모델

선거용 명단 snapshot 모델은 `ElectionVoter`로 구현되어 있다.

의미:

- `ElectionVoter`는 원본 `VoterSlot`의 복사본이다.
- `ElectionVoter`는 선거 안에서 실제 투표 대상이 되는 학생 row다.
- 학생 계정이 아니다.
- 원본 `VoterSlot`이 수정되거나 삭제되어도 이미 시작된 `ElectionVoter`에는 영향을 주지 않는다.

이유:

- 선거 안에서 실제 투표 대상이 되는 사람을 의미하기 쉽다.
- 원본 `VoterSlot`과 구분된다.
- 이름이 너무 길지 않다.

컬럼 초안:

- `election:references, null: false, foreign_key: true`
- `source_voter_slot:references, null: false, foreign_key to voter_slots`
- `number:integer, null: false`
- `name:string, null: false`

DB index:

- `[election_id, number]` unique
- `[election_id, source_voter_slot_id]` unique

컬럼과 index 이유:

- `number`는 선거 안의 투표 진행 순서를 고정한다.
- `name`은 시작 시점의 이름을 보존한다.
- `source_voter_slot_id`는 원본 명단 추적용이다.
- 같은 원본 `VoterSlot`이 같은 `Election`에 중복 snapshot되면 안 된다.

초기 `ElectionVoter`에는 `status`를 두지 않는다.

이유:

- 출석번호 진행 상태와 실제 투표 결과는 분리해야 한다.
- 투표 진행 상태는 `PollingStation` 또는 `VoteSession` 설계에서 다룰 가능성이 크다.
- `ElectionVoter`는 우선 고정된 선거용 투표자 명단 역할에 집중한다.

후속 투표 진행 설계에서 `waiting`, `voting`, `voted`, `abstained` 같은 상태가 필요하면 다시 검토한다.

### Elections::Start service 설계

선거 시작 로직은 controller에 길게 두지 않고 `Elections::Start` service object로 분리되어 있다.

service 이름 후보:

- `ElectionStarter`
- `StartElection`
- `Elections::Start`

구현 이름은 `Elections::Start`이다.

이유:

- namespace를 통해 `Election` 관련 service임이 명확하다.
- 나중에 `Elections::Close`, `Elections::Tally` 같은 흐름으로 확장하기 쉽다.

`Elections::Start` 책임:

- `Election`이 `draft` 상태인지 확인
- 후보자가 있는지 확인
- 후보자 수와 ballot mode 정책 확인
- `voter_group`에 `voter_slots`가 있는지 확인
- `election_voters` snapshot이 아직 없는지 확인
- transaction 안에서 `ElectionVoter` snapshot 생성
- transaction 안에서 `Election` 상태를 `in_progress`로 변경
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

snapshot 생성은 `Elections::Start`에서 구현되어 있다.

구현 원칙:

- `Election` 시작 시 transaction 안에서 snapshot 생성과 상태 변경을 함께 처리한다.
- 하나라도 실패하면 선거 시작 전체가 실패해야 한다.
- 이미 snapshot이 있으면 중복 생성하지 않아야 한다.
- 시작 이후 후보자 추가/수정/삭제는 금지하는 방향이다.
- 시작 이후 선거에 연결된 snapshot 명단 수정도 금지한다.

복구/무결성 관점:

- snapshot은 투표 중 새로고침, 재부팅, 재로그인 이후에도 동일한 투표 순서를 복구하는 기준이 된다.
- 원본 `VoterGroup`이 아니라 선거용 snapshot을 기준으로 투표 진행 상태를 계산한다.
- 출석번호 진행 상태와 실제 투표 결과는 분리되어야 한다.

snapshot 모델명, 컬럼, `Election`과의 association은 구현되어 있다.

---

## 투표 진행 상태 모델링

이번 단계에서 구현하지는 않지만, 다음 구현의 기준이 되는 투표 진행 상태 원칙은 아래와 같이 둔다.

### ElectionVoter의 책임

`ElectionVoter`는 선거용 고정 명단이다.

책임:

- 선거 시작 시점의 투표 대상 학생 row를 나타낸다.
- 시작 시점의 출석번호와 이름을 보존한다.
- 원본 `VoterSlot`이 바뀌어도 이미 시작된 선거의 투표 대상이 바뀌지 않게 한다.
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

출석번호 진행 상태가 `candidate_id` 같은 실제 선택 결과와 직접 연결되면 누가 누구에게 투표했는지 추적할 수 있다.
따라서 진행 상태 모델은 `ElectionVoter`를 참조하더라도, 실제 후보 선택 결과와 직접 결합하지 않도록 설계한다.

### 진행 상태 모델 후보

#### 후보 A: PollingStation

의미:

- 선거 진행소 또는 투표소 전체 상태를 나타낸다.
- 초기 학급 MVP에서는 `Election` 1개에 `PollingStation` 1개가 자연스럽다.
- 현재 어느 `ElectionVoter`가 투표 중인지, 현재 진행 위치가 어디인지 관리하기 좋다.
- 교사용 진행 화면과 잘 맞는다.

주의:

- `Election`도 `status`를 가지므로, `PollingStation` 상태가 중복되지 않도록 범위를 좁혀야 한다.
- 전교 선거 확장 시에는 한 `Election`에 여러 `PollingStation`이 필요할 수 있다.

#### 후보 B: VoteSession

의미:

- 개별 학생의 투표 시도 또는 제출 세션에 가깝다.
- 학생 투표 화면에 들어간 순간부터 제출까지의 transient 상태를 다루기 좋다.

주의:

- 초기 MVP처럼 교사 장치 하나에서 학생을 순서대로 진행하는 흐름에서는 처음부터 복잡할 수 있다.
- 제출 token, open session, 재제출 방지까지 함께 설계해야 하므로 도입 시점을 신중히 잡는다.

#### 후보 C: ElectionProgress

의미:

- 이름만 보면 선거 진행 상태를 직관적으로 표현한다.

주의:

- 도메인 용어로는 다소 일반적이다.
- 교사용 투표소, 학생 투표 화면, 전교 선거 확장까지 포괄하기에는 의미가 흐려질 수 있다.

### 권장 방향

초기 MVP에서는 `PollingStation`을 우선 검토한다.

권장 이유:

- 교사가 장치 하나로 선거를 진행하는 흐름과 잘 맞는다.
- `ElectionVoter` snapshot 명단 위에서 현재 진행 위치를 복구하기 쉽다.
- 후속 전교 선거 확장에서도 “학급별 투표소” 개념으로 확장할 수 있다.

`VoteSession`은 학생 투표 화면과 제출 흐름이 복잡해질 때 후속으로 검토한다.
예를 들어 signed token, open session, 제출 중복 방지, 화면 새로고침 복구가 필요해지는 시점에 별도 모델로 도입할 수 있다.

### PollingStation 책임 초안

`PollingStation`은 아직 구현하지 않는다.

후속 구현에서 검토할 책임:

- `Election`에 속한다.
- 초기 학급 MVP에서는 `Election`당 하나만 존재한다.
- 현재 투표 순서 또는 current index를 관리한다.
- 현재 투표 중인 `ElectionVoter`를 가리킨다.
- 새로고침, 재로그인, PC 재부팅 후에도 현재 투표 순서를 복구할 수 있게 한다.
- teacher가 다음 학생으로 진행할 수 있게 한다.
- 이미 투표 완료된 학생을 중복 투표시키지 않게 한다.

컬럼 후보:

- `election:references, null: false`
- `current_election_voter:references, nullable, foreign_key to election_voters`
- `status:integer, default: 0`
- `started_at:datetime`
- `closed_at:datetime`

상태 후보:

- `ready`
- `active`
- `closed`

다만 `Election` 자체도 `draft`, `in_progress`, `closed` 상태를 가진다.
초기 구현에서는 `Election.status`를 선거 전체 상태의 기준으로 삼고, `PollingStation`은 `current_election_voter_id` 중심으로 단순화하는 방향도 가능하다.
이 중복 여부는 실제 모델 추가 직전에 결정한다.

### ElectionVoter별 진행 상태 위치

선택지 A: `ElectionVoter`에 `progress_status` 추가

- 장점: 단순하다.
- 단점: `ElectionVoter`가 고정 명단 역할을 넘어 진행 상태까지 갖게 된다.

선택지 B: 별도 `ElectionVoterProgress` 또는 `PollingSlot` 모델 추가

- 장점: 고정 명단과 진행 상태를 분리할 수 있다.
- 단점: 모델 수와 join이 늘어난다.

선택지 C: `PollingStation`이 current pointer만 가지고, 완료 여부는 별도 vote receipt 또는 record에서 판단

- 장점: 초기 구현을 작게 유지할 수 있다.
- 단점: 중단 복구와 상태 표시가 복잡해질 수 있다.

권장:

- 다음 구현 전 한 번 더 판단한다.
- 다만 고정 명단과 진행 상태를 분리한다는 원칙은 유지한다.
- 현재 `ElectionVoter`에는 진행 상태 컬럼을 추가하지 않는다.

### 실제 투표 결과 모델 후보

실제 표는 아직 구현하지 않는다.

후속 후보:

- `VoteRecord`
- `Vote`
- `Ballot`
- `Tally`

정책:

- 개별 vote row가 `election_voter_id`와 `candidate_id`를 동시에 저장하면 누가 누구에게 투표했는지 연결될 수 있다.
- 비밀투표를 우선하면 출석번호 진행 상태와 실제 선택 결과를 분리해야 한다.
- 초기 MVP에서는 transaction 안에서 “해당 `ElectionVoter`는 완료 처리”와 “후보자 득표 count 증가”를 함께 처리하는 방향을 검토한다.
- 감사 가능성을 위해 어떤 수준의 익명 기록을 남길지는 후속 설계가 필요하다.

### 투표 제출 트랜잭션 원칙

후속 구현에서 투표 제출은 반드시 transaction으로 처리한다.

최소 원칙:

- 현재 투표 대상 `ElectionVoter`가 맞는지 확인한다.
- 아직 완료되지 않은 학생인지 확인한다.
- 선택한 후보자가 해당 `Election`의 후보자인지 확인한다.
- 완료 상태 변경과 득표 반영을 같은 transaction에서 처리한다.
- 실패 시 전체 rollback한다.
- 새로고침이나 중복 클릭으로 같은 학생이 두 번 제출되지 않도록 unique constraint 또는 lock을 검토한다.

### 중단 복구 원칙

후속 구현에서 교사가 브라우저를 새로고침하거나 PC가 재부팅되어도 다음을 복구해야 한다.

- 현재 `Election`
- `Election` 상태
- `ElectionVoter` snapshot 명단
- 현재 투표 순서
- 완료된 학생 목록
- 다음 투표할 학생

복구 기준은 원본 `VoterGroup`이 아니라 `ElectionVoter` snapshot과 투표 진행 상태 모델이어야 한다.

---

## 수정 제한 정책

### 선거와 연결되기 전 VoterGroup

선거와 연결되기 전의 `VoterGroup`은 원본 명단 정리 단계로 본다.

허용 방향:

- 투표자 그룹 이름 수정
- 투표자 그룹 삭제
- 학생 1명 추가
- 학생 여러 명 추가
- 학생 이름 수정
- 학생 삭제

번호 재정렬은 투표 진행 순서와 연결되므로 별도 정책 없이는 구현하지 않는다.

### 선거 생성 후

원본 `VoterGroup` 수정은 가능하더라도 이미 생성된 선거에는 영향을 주지 않는 방향이 안전하다.

이를 위해 선거용 snapshot 정책을 우선 검토한다.
snapshot을 사용하지 않고 원본을 직접 참조한다면, 선거 생성 후 원본 명단 수정/삭제 제한 guard가 필요하다.

### 선거 시작 후

해당 선거의 투표자 명단은 수정하지 않는다.

금지 방향:

- 학생 추가
- 학생 삭제
- 출석번호 변경
- 투표 진행 상태와 연결된 이름 변경

### 투표 종료 후

투표 종료 후에는 결과 보존과 감사 가능성을 우선한다.

따라서 선거용 명단은 수정하지 않는다.
예외가 필요하다면 관리자 권한, 확인 절차, 감사 로그가 함께 필요하다.

---

## 후속 설계 범위

다음 모델은 아직 구현하지 않는다.

- `PollingStation`
- `VoteSession`
- `Tally`

다음 구현 전에 결정할 항목:

- 후보자 1명 선거의 처리 방식
- `ballot_mode`를 선거 시작 구현 전에 추가할지 여부
- 선거 시작 후 후보 수정 제한의 예외 정책
- `PollingStation` 상태 컬럼을 둘지, `Election.status`와 current pointer만 사용할지 여부
- `ElectionVoter`별 진행 상태를 별도 모델로 둘지 여부
- 실제 투표 결과를 집계 count 중심으로 둘지, 익명 기록을 함께 둘지 여부

다음 구현 순서:

1. `PollingStation` 또는 진행 상태 모델 최종 결정
2. 진행 상태 모델 추가
3. `Election` start 후 `PollingStation` 생성 또는 초기화
4. 교사용 진행 화면 추가
5. 학생 투표 화면 추가
6. 투표 제출 transaction 구현
7. 중단 복구/중복 제출 방지 spec 추가
8. 결과 집계 화면 추가
