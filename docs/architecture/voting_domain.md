# Voting Domain

## 목적

이 문서는 `쑥쑥교실투표`의 투표 도메인 모델 관계를 구현 전에 정리하기 위한 architecture 문서다.

현재 구현된 모델은 `VoterGroup`과 `VoterSlot`뿐이다.
`Election`, `Candidate`, `PollingStation`, `VoteSession`, `Tally`, 선거용 명단 snapshot 모델은 아직 구현하지 않았으며, 실제 모델명과 컬럼은 후속 설계에서 확정한다.

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
- `Election` 생성 시점 또는 시작 시점에 선거용 투표자 snapshot 생성 검토
- `PollingStation`과 투표 진행 상태는 원본 `VoterSlot`이 아니라 선거용 snapshot row를 기준으로 삼는 방향을 우선 검토

snapshot 생성 시점은 아직 확정하지 않는다.

검토 기준:

- 생성 시점 snapshot: 선거 생성 이후 원본 명단 변경이 선거에 영향을 주지 않음
- 시작 시점 snapshot: 선거 시작 전까지 원본 명단 정리 여지를 더 줄 수 있음

실제 snapshot 모델명, 컬럼, `Election`과의 association은 `Election` 모델 설계 때 확정한다.

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

- `Election`
- `Candidate`
- `PollingStation`
- `VoteSession`
- `Tally`
- 선거용 투표자 snapshot 모델

다음 구현 전에 결정할 항목:

- `Election` 최소 컬럼과 상태
- `Election`이 선택한 원본 `VoterGroup`을 어떻게 기록할지
- 선거용 명단 snapshot 생성 시점
- snapshot row의 이름과 출석번호 보존 방식
- 빈 `VoterGroup`을 선거 생성에서 막는 validation 위치
