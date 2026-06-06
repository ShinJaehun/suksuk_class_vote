# RSpec Strategy for suksuk_class_vote

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`에서 RSpec 테스트를 어떤 철학과 우선순위로 추가할지 정리한다.

테스트의 목적은 coverage 수치가 아니라 핵심 기능 변경 시 confidence를 주는 안전망이다.
이 프로젝트에서는 특히 권한, 상태 전이, 멱등성, 중복 제출 방지, 투표 중단 복구, 주요 request 흐름을 고정하는 데 집중한다.

---

## 기본 철학

이 프로젝트의 테스트 목적은 다음과 같다.

* 투표 중단 후 복구 가능성 보장
* 중복 제출 방지
* 투표 상태 전이 규칙 고정
* 권한/소유권 경계 고정
* 출석번호 진행 상태와 후보 선택 결과 분리 원칙 검증
* 수동 브라우저 테스트 의존도 감소
* 향후 학급 선거 MVP를 전교 선거 구조로 확장할 때 회귀 방지

Coverage 수치 자체를 목표로 삼지 않는다.

---

## 스타일 원칙

* readable > clever.
* DRY보다 DAMP를 우선한다. 테스트는 조금 반복되더라도 의도가 드러나야 한다.
* 테스트 이름은 사용자의 행동이나 도메인 규칙을 문장으로 설명한다.
* context는 역할별로 명확히 나눈다.

  * guest
  * admin
  * teacher
* 학생은 초기 MVP에서 로그인 사용자가 아니므로, student context를 인증 사용자처럼 다루지 않는다.
* 테스트 데이터는 가능한 사용 위치 가까이에 둔다.
* 과도한 `shared_context`, helper, abstraction 남용을 피한다.
* brittle한 HTML 구조, Tailwind class, 세부 DOM 배치 고정 테스트를 지양한다.
* request spec은 핵심 텍스트, redirect, status, 데이터 변화, 권한 차단을 중심으로 검증한다.
* system spec은 정말 필요한 happy path와 브라우저 통합 흐름에만 제한적으로 사용한다.

---

## 테스트 우선순위 1

초기 MVP에서 가장 먼저 고정해야 할 핵심 테스트 영역이다.

### 인증/권한

* guest는 주요 리소스에 접근할 수 없다.
* teacher는 본인 투표자 그룹만 볼 수 있다.
* teacher는 다른 teacher의 투표자 그룹을 볼 수 없다.
* teacher는 본인 선거만 만들고 관리할 수 있다.
* teacher는 다른 teacher의 선거를 수정할 수 없다.
* teacher는 본인 투표소만 진행할 수 있다.
* teacher는 다른 teacher의 결과를 볼 수 없다.
* admin은 전체 투표자 그룹, 선거, 결과에 접근할 수 있다.

### 투표자 그룹

* teacher가 투표자 그룹을 생성할 수 있다.
* teacher가 본인 투표자 그룹을 수정할 수 있다.
* 다른 teacher의 투표자 그룹 수정은 차단된다.
* 투표자 그룹 안에서 출석번호가 중복될 수 없다.
* 이미 선거에 사용 중인 투표자 그룹의 수정/삭제 정책을 spec에 맞게 고정한다.

### 학생 명단 bulk import

* 탭 구분 입력을 파싱한다.
* 공백 구분 입력을 파싱한다.
* 제목 행을 건너뛴다.
* 빈 줄을 무시한다.
* 출석번호 중복을 오류로 표시한다.
* 이름 없음 row를 오류로 표시한다.
* 번호 없음 row를 오류로 표시한다.
* 오류가 있으면 저장하지 않는다.
* 정상 입력은 voter slots로 저장된다.

### 선거/후보

* teacher가 본인 투표자 그룹을 대상으로 선거를 생성할 수 있다.
* teacher가 본인 선거에 후보를 등록할 수 있다.
* 선거 시작 전에는 후보를 수정할 수 있다.
* 선거 시작 후에는 후보 수정/삭제가 제한된다.
* 다른 teacher의 선거 후보 등록/수정은 차단된다.

### 투표 진행 상태

* `Election`은 draft / in_progress / closed 상태를 가진다.
* `PollingStation`은 active / closed 상태를 가지며, ready 상태를 두지 않는다.
* `PollingStation`은 `Election`이 in_progress가 된 뒤 생성되므로 active부터 시작한다.
* `ElectionVoterParticipation` 또는 `ElectionVoterReceipt`는 completed / absent / abstained 같은 확정 상태를 가진다.
* 한 투표소에서 open vote session은 하나만 허용한다.
* 완료된 `ElectionVoter`는 다시 투표할 수 없다.
* 종료된 polling station에는 추가 투표를 할 수 없다.
* participation/receipt에는 `candidate_id`를 저장하지 않는다.
* `CandidateTally`는 `ElectionVoter`와 직접 연결하지 않는다.

### 투표 제출 / 멱등성

* open vote session이 있을 때만 투표 제출이 가능하다.
* 같은 vote session을 두 번 제출해도 득표수는 한 번만 증가한다.
* 제출 성공 시 participation/receipt 완료와 tally 증가가 함께 반영된다.
* 제출 실패 시 participation/receipt 완료와 tally 증가가 모두 반영되지 않는다.
* 종료된 투표소에 들어온 제출 요청은 거부된다.
* 학생 completed_at과 후보별 득표 증가 정보를 화면에서 직접 연결해 보여주지 않는다.

### 중단 복구

* 교사 진행 화면을 새로고침해도 현재 `ElectionVoter` 위치로 복구된다.
* 학생 투표 화면을 새로고침해도 open vote session으로 복구된다.
* 교사 재로그인 후 진행 중인 `ElectionVoter` 위치로 복구된다.
* 제출 요청이 성공했지만 브라우저가 완료 화면을 받지 못한 경우, 재접속 시 completed 상태로 보인다.
* 제출 요청이 실패한 경우, 재접속 시 기존 voting 상태로 다시 투표할 수 있다.

---

## 테스트 우선순위 2

초기 MVP의 핵심 흐름이 안정된 뒤 보강할 영역이다.

* 결과 화면의 후보별 득표 표시
* 투표 종료 조건 검증
* 미참여/무투표 처리 되돌림 정책
* 선거 시작 후 투표자 그룹 수정 제한
* locale이 개입되는 핵심 사용자 메시지
* Turbo/HTML 응답 분기
* admin 관리 화면
* 감사 로그 도입 시 주요 이벤트 기록
* 인쇄용 결과 화면 또는 export 기능

---

## 후순위

아래 항목은 테스트로 강하게 고정하기 전에 정책 안정성을 먼저 확인한다.

* 세세한 view 구조
* Tailwind class
* 자주 바뀌는 문구
* 너무 세밀한 DOM 순서
* 후보 카드 디자인
* 관리자 대시보드 세부 UI
* 전교어린이회 선거 확장 기능
* 선거관리위원 개표 승인
* PDF 출력

---

## 테스트 레벨

### model spec

도메인 불변식과 상태 규칙을 고정할 때 우선 사용한다.

대상 예시:

* VoterGroup
* VoterSlot
* Election
* Candidate
* PollingStation
* VoteSession
* Tally

검증 예시:

* 출석번호 중복 금지
* 상태 enum 전이 규칙
* 종료된 선거 수정 제한
* 완료된 voter slot 재투표 방지
* 후보별 tally uniqueness

---

### service spec

상태 전이와 트랜잭션이 중요한 작업을 고정할 때 우선 사용한다.

대상 후보:

* `VoteSessions::Open`
* `Votes::Submit`
* `VoterSlots::MarkAbsent`
* `PollingStations::Close`
* `BulkStudentImport::Parser`
* `BulkStudentImport::Preview`
* `BulkStudentImport::Commit`

검증 예시:

* 투표 시작 시 voter slot과 vote session 상태가 함께 바뀐다.
* 투표 제출 시 tally 증가, voter slot 완료, vote session 제출이 하나의 transaction으로 처리된다.
* 중복 제출이 득표수 중복 증가로 이어지지 않는다.
* import preview가 오류를 올바르게 표시한다.
* import commit은 오류가 있을 때 저장하지 않는다.

---

### policy spec

역할과 scope의 경계를 고정할 때 사용한다.

검증 예시:

* admin은 전체 리소스에 접근할 수 있다.
* teacher는 본인 리소스에만 접근할 수 있다.
* teacher는 다른 teacher의 voter group/election/result에 접근할 수 없다.
* guest는 주요 리소스에 접근할 수 없다.
* 학생은 인증 사용자로 취급하지 않는다.

---

### request spec

사용자 흐름과 controller 권한을 고정할 때 우선 사용한다.

검증 예시:

* 로그인하지 않은 사용자는 redirect된다.
* teacher가 voter group을 생성한다.
* teacher가 bulk import preview를 요청한다.
* teacher가 선거를 생성한다.
* teacher가 후보를 등록한다.
* teacher가 투표를 시작한다.
* teacher가 투표를 종료한다.
* 권한 없는 요청은 차단된다.
* HTML/Turbo 응답이 기본적으로 깨지지 않는다.

---

### system spec

정말 필요한 핵심 happy path만 후보로 둔다.

후보:

* 교사 로그인 후 투표자 그룹 생성
* 학생 명단 붙여넣기 import
* 선거 생성
* 후보 등록
* 출석번호 순서로 투표 진행
* 투표 종료 후 결과 확인

system spec은 초기에는 최소화한다.
중단 복구와 멱등성은 system spec보다 model/service/request spec으로 먼저 고정한다.

---

## 테스트 작성 순서 제안

### Step 1: import와 기본 도메인

* bulk import parser/preview spec
* VoterGroup / VoterSlot validation spec
* teacher 소유권 기본 policy spec

### Step 2: 선거 생성

* Election / Candidate model spec
* teacher election request spec
* 후보 등록 request spec
* 선거 시작 후 후보 수정 제한 spec

### Step 3: 투표 진행 상태

* PollingStation 상태 전이 spec
* VoterSlot 상태 전이 spec
* VoteSession open service spec
* open vote session 중복 방지 spec

### Step 4: 투표 제출

* Votes::Submit service spec
* tally 증가 spec
* 중복 제출 방지 spec
* transaction rollback spec
* completed voter slot 재투표 차단 spec

### Step 5: 복구 흐름

* 진행 중인 voter slot 복구 request spec
* 교사 재로그인 후 진행 중인 투표소 접근 spec
* 제출 성공/실패 후 재접속 시 상태 spec

### Step 6: 결과 확인

* 투표 종료 request spec
* 결과 조회 권한 spec
* 후보별 득표 표시 request spec

---

## 수동 Smoke Checklist

자동 테스트와 별도로 브라우저에서 짧게 확인할 항목이다.

* 교사가 로그인한다.
* 투표자 그룹을 생성한다.
* Excel/HWP에서 복사한 학생 명단을 붙여넣는다.
* 미리보기에서 정상/오류가 구분된다.
* 정상 명단을 저장한다.
* 선거를 생성한다.
* 후보자를 등록한다.
* 투표를 시작한다.
* 첫 번째 학생이 투표한다.
* 투표 완료 후 입력이 차단된다.
* 다음 학생으로 이동한다.
* 특정 학생을 미참여/무투표 처리한다.
* 학생 투표 화면에서 새로고침해도 현재 학생으로 복구된다.
* 교사 진행 화면에서 새로고침해도 현재 상태가 유지된다.
* 브라우저를 닫고 다시 로그인해도 진행 중인 위치로 복구된다.
* 투표 완료 버튼을 빠르게 두 번 눌러도 득표수가 한 번만 오른다.
* 모든 학생을 처리한 뒤 투표를 종료한다.
* 결과 화면에서 후보별 득표수가 표시된다.

---

## 피해야 할 테스트

* 구현 세부사항에 과하게 결합된 테스트
* 낮은 가치의 단순 마크업 고정 테스트
* request/system 테스트의 과도한 중복
* helper/shared_context 남용으로 읽기 어려워진 테스트
* 아직 확정되지 않은 spec을 성급히 고정하는 테스트
* 수동으로 자주 바꾸는 UI 문구나 Tailwind class만 검증하는 테스트
* 브라우저에서만 확인 가능한 문제를 억지로 request spec에 끼워 넣는 테스트
* 모든 기능을 system spec으로만 검증하려는 테스트

---

## 문서와 테스트의 관계

* 테스트는 `docs/specs/*.md`, `docs/architecture/current_system.md`, 관련 architecture 문서에 합의된 요구사항을 기준으로 작성한다.
* spec이 부족한 기능은 먼저 현재 구현과 정책을 읽고, 필요한 경우 spec 문서를 보강한 뒤 테스트를 설계한다.
* 문서가 구현과 충돌하면 문서를 먼저 의심하고, 실제 코드와 합의된 정책을 확인한 뒤 갱신한다.
* archive/legacy 문서는 사용자가 요청하거나 현재 문서만으로 맥락을 알 수 없을 때만 참고한다.
* 테스트는 과거 구현을 복제하기 위한 장치가 아니라, 현재 `쑥쑥교실투표`의 도메인 규칙과 사용자 흐름을 안전하게 고정하는 장치다.

---

## 한 줄 기준

테스트는 coverage를 채우기 위한 작업이 아니라,
`쑥쑥교실투표`의 투표 진행, 중단 복구, 중복 제출 방지, 권한 경계, 비밀투표 원칙을 안전하게 바꿀 수 있게 만드는 안전망이다.
