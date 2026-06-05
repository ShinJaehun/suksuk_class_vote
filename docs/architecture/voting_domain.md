# Voting Domain

## 목적

이 문서는 `쑥쑥교실투표`의 투표 도메인 모델 관계를 구현 전에 정리하기 위한 architecture 문서다.

현재 구현된 모델은 `VoterGroup`, `VoterSlot`, `Election`, `Candidate`이다.
`PollingStation`, `VoteSession`, `Tally`, 선거용 명단 snapshot 모델은 아직 구현하지 않았으며, 실제 모델명과 컬럼은 후속 설계에서 확정한다.

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
- 상태는 `draft`만 사용한다.
- index/new/create/show만 구현되어 있다.
- 후보자 등록/수정/삭제는 nested `Candidate` 흐름으로 구현되어 있다.
- 선거 시작, 투표 진행, 결과 집계는 아직 구현하지 않았다.

`Election` 생성 시점에는 선거용 명단 snapshot을 만들지 않는다.
선거 시작 시점에 snapshot을 만드는 방향을 후속 작업에서 구현한다.

### Election 상태 전이 초안

현재 구현된 `Election` 상태는 `draft`뿐이다.

현재 의미:

- `draft`는 선거 준비 중 상태다.
- `draft` 상태에서는 선거 제목, `VoterGroup` 선택, 후보자 등록/수정/삭제가 가능하다.
- 아직 선거 시작과 투표 시작은 구현하지 않았다.

후속 상태 전이 초안:

```text
draft -> in_progress -> closed
```

검토 항목:

- `ready` 상태를 별도로 둘지는 아직 결정하지 않는다.
- 초기 MVP에서는 `draft`에서 바로 `in_progress`로 시작해도 된다.
- 다만 `in_progress`로 전이하기 전에 후보자와 명단 조건을 반드시 검증한다.

이 상태 전이는 아직 구현 전 초안이다.

### Election 시작 조건 초안

선거 시작 기능은 아직 구현하지 않았다.

후속 구현에서 `Election` 시작 시점에는 최소 다음 조건을 검증한다.

- `Election`이 `draft` 상태일 것
- 연결된 `VoterGroup`에 `VoterSlot`이 1명 이상 있을 것
- 후보자가 1명 이상 있을 것
- 후보자 이름이 모두 유효할 것
- 선거용 명단 snapshot이 아직 생성되지 않았을 것

후보자 수 정책 검토 항목:

- 후보자 0명은 선거를 시작할 수 없다.
- 후보자 1명은 일반적으로 무투표 당선 처리할 수 있다.
- 다만 학교나 선거 규정에 따라 후보자 1명이어도 찬성/반대 투표를 진행할 수 있다.
- 후보자 2명 이상은 여러 후보 중 선택하는 일반 경쟁 투표로 본다.

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

### ElectionVoter snapshot 모델 초안

선거용 명단 snapshot 모델은 아직 구현하지 않았다.

모델명 후보:

- `ElectionVoter`
- `ElectionVoterSlot`
- `ElectionVoterSnapshot`

권장 초안은 `ElectionVoter`이다.

이유:

- 선거 안에서 실제 투표 대상이 되는 사람을 의미하기 쉽다.
- 원본 `VoterSlot`과 구분된다.
- 이름이 너무 길지 않다.

컬럼 초안:

- `election_id`
- `source_voter_slot_id`
- `number`
- `name`
- `status`

`status` 후보:

- `waiting`
- `voting`
- `voted`
- `abstained`

검토 항목:

- `status`는 아직 확정하지 않는다.
- 투표 진행 상태를 `ElectionVoter`에 둘지, 별도 `PollingStation`/`VoteSession` 계층에 둘지는 후속 설계에서 결정한다.
- 특정 `Election` 안에서 `ElectionVoter`의 `number`는 중복될 수 없어야 한다.

### snapshot 생성 무결성 원칙

snapshot 생성은 아직 구현하지 않았다.

후속 구현 원칙:

- `Election` 시작 시 transaction 안에서 snapshot 생성과 상태 변경을 함께 처리한다.
- 하나라도 실패하면 선거 시작 전체가 실패해야 한다.
- 이미 snapshot이 있으면 중복 생성하지 않아야 한다.
- 시작 이후 후보자 추가/수정/삭제는 금지하는 방향이다.
- 시작 이후 선거에 연결된 snapshot 명단 수정도 금지한다.

복구/무결성 관점:

- snapshot은 투표 중 새로고침, 재부팅, 재로그인 이후에도 동일한 투표 순서를 복구하는 기준이 된다.
- 원본 `VoterGroup`이 아니라 선거용 snapshot을 기준으로 투표 진행 상태를 계산한다.
- 출석번호 진행 상태와 실제 투표 결과는 분리되어야 한다.

실제 snapshot 모델명, 컬럼, `Election`과의 association은 다음 구현 작업에서 확정한다.

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
- 선거용 투표자 snapshot 모델

다음 구현 전에 결정할 항목:

- `Election` 시작 상태 전이
- 선거용 명단 snapshot 모델명과 생성 방식
- snapshot row의 이름과 출석번호 보존 방식
- 후보자 최소 수 정책
- snapshot row의 상태 보관 위치
- 선거 시작 후 후보 수정 제한의 예외 정책
