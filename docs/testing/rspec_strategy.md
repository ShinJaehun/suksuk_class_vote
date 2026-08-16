# RSpec Strategy for suksuk_class_vote

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`에서 RSpec 테스트를 어떤 철학과 우선순위로 유지할지 정리한다.

테스트의 목적은 coverage 수치가 아니라 핵심 기능 변경 시 confidence를 주는 안전망이다.
특히 권한, 상태 전이, 멱등성, 중복 제출 방지, 장애 복구와 주요 request 흐름을 고정한다.

---

## 기본 철학

이 프로젝트의 테스트 목적은 다음과 같다.

* 투표 중단 후 DB 상태 기준 복구 가능성 보장
* 중복 제출 방지
* 투표 상태 전이 규칙 고정
* 권한/소유권/학교 경계 고정
* 출석번호 진행 상태와 후보 선택 결과 분리 원칙 검증
* 수동 브라우저 테스트 의존도 감소
* 신규 PollSession runtime과 남아 있는 legacy runtime의 회귀 방지

Coverage 수치 자체를 목표로 삼지 않는다.

---

## 스타일 원칙

* readable > clever.
* DRY보다 DAMP를 우선한다. 테스트는 조금 반복되더라도 의도가 드러나야 한다.
* 테스트 이름은 사용자의 행동이나 도메인 규칙을 문장으로 설명한다.
* context는 guest, admin, teacher 등 역할별로 명확히 나눈다.
* 학생은 로그인 사용자가 아니므로 student context를 인증 사용자처럼 다루지 않는다.
* 테스트 데이터는 가능한 사용 위치 가까이에 둔다.
* 과도한 `shared_context`, helper, abstraction 남용을 피한다.
* brittle한 HTML 구조, Tailwind class, 세부 DOM 배치 고정 테스트를 지양한다.
* request spec은 핵심 텍스트, redirect, status, 데이터 변화, 권한 차단을 중심으로 검증한다.
* system spec은 핵심 happy path와 중요한 브라우저 통합 흐름에만 제한적으로 사용한다.

---

## 현재 기본 회귀 흐름

신규 학급투표와 전교투표의 기본 회귀 대상은 다음 구조다.

```text
School / Classroom / active Student
→ Poll draft
→ PollSession
→ PollParticipant snapshot
→ PollProgress / participation / tally
→ closed 또는 stopped
→ 필요 시 replacement
```

ParticipantGroup / ParticipantSlot과 Election / ElectionSession runtime 및 전용 spec은 제거됐다.
DB 복원·변환 검증은 후속 작업에서 다룬다.

---

## 테스트 우선순위 1

### 인증과 권한

* guest는 주요 리소스에 접근할 수 없다.
* teacher는 자기 학교·담당 Classroom·운영 PollSession 범위만 접근한다.
* manager는 자기 학교 school-managed Poll 범위만 관리한다.
* 다른 교사와 다른 학교의 Classroom, Student, Poll, PollSession 접근은 차단된다.
* admin과 teacher/manager의 신규 Poll 권한 경계를 고정한다.

### Classroom / Student와 snapshot

* Classroom과 Student의 학교·담임·번호·active 불변식을 검증한다.
* Student 단일·bulk 등록은 오류가 있으면 원자적으로 저장하지 않는다.
* PollSession 시작은 active Student만 번호 순서로 PollParticipant snapshot에 복사한다.
* 시작 뒤 Student 수정·inactive가 기존 snapshot과 결과를 바꾸지 않는다.
* snapshot과 participation/tally가 학생별 선택을 직접 연결하지 않는다.

### Poll / PollSession lifecycle

* draft workspace의 정의·명단·시작 준비 조건을 고정한다.
* 시작, ballot open/lock, 제출·기권, 미참여, advance, 종료 상태 전이를 검증한다.
* 부분 완료 학생과 stale current participant 요청이 잘못된 진행·종료를 만들지 않는다.
* 중단은 stopped 상태와 기존 진행 기록을 보존하고 추가 제출을 차단한다.
* replacement 재투표는 source stopped Session을 보존하고 새 Poll/PollSession 관계를 고정한다.
* 동일 학생 제출은 participation과 tally에 한 번만 반영된다.

### school-managed Poll

* parent Poll 준비·시작·중단·명시적 종료와 학급별 PollSession 경계를 검증한다.
* 전체 결과에는 current closed Session만 포함한다.
* 학급 Session 재투표는 stopped/closed source를 보존하고 replacement draft Session을 만든다.
* Test Poll 생성·실행·원본 종료에 따른 terminal lifecycle을 검증한다.
* current Session 중 하나라도 non-closed이면 종료 readiness가 깊은 검사를 수행하지 않고 실패한다.
* 모두 closed일 때만 최종 Session 무결성 검사를 수행한다.
* reset, Session 배정, 전체 중단 같은 batch 작업은 aggregate broadcast를 합치고 최종 상태를 갱신한다.

### runtime recovery와 terminal consistency

* Turbo Stream / ActionCable을 primary 갱신 수단으로 유지한다.
* recovery endpoint는 정상 상태에 `204 No Content`를 반환한다.
* stale 또는 terminal 상태일 때만 필요한 작은 Turbo Stream 영역을 반환한다.
* ballot form이 열린 상태에서 Cable 갱신을 놓쳐도 fingerprint recovery가 locked 상태와 다음 참여자로 수렴한다.
* 전교투표 stream recipient는 현재 active admin과 같은 학교 manager로 제한하고 draft/in-progress 화면의 권한 상실 recovery를 검증한다.
* inactive School/Classroom의 direct Student mutation과 진행 중 Session의 구조 변경 우회를 request/service spec으로 차단한다.
* 진행 중 전교투표의 current closed Session은 재투표 가능 관계가 끝날 때까지 Classroom/operator 변경을 차단한다.
* active ballot form과 학생이 선택 중인 값은 polling으로 교체하지 않는다.
* stale teacher action과 student submit은 DB terminal 상태로 안전하게 수렴한다.
* hidden tab의 polling timer 중단과 visible 복귀 직후 확인은 필요한 JS/browser 수준에서 검증한다.

ActionCable 단절을 DevTools로 매번 인위적으로 재현하는 것을 필수 회귀 테스트로 두지 않는다.
fallback endpoint의 서버 계약은 request/service spec을 우선한다.

### transaction과 동시성

* tally, participation, completion과 event가 같은 transaction에서 함께 성공하거나 rollback된다.
* 중복 실행 방어와 DB unique/state constraint를 검증한다.
* 주요 Session 경로는 `PollSession -> PollProgress` 순서로 lock한다.
* schoolwide stop은 `Poll -> PollSessions(id 순서) -> PollProgress` 순서를 유지한다.
* outer join scope에서 선택한 current Session id를 base PollSession query로 다시 잠그는 계약을 고정한다.
* race 상황에서도 최종 상태·집계·source 보존 invariant가 유지되는지 검증한다.

deadlock 자체를 반복 재현하는 flaky test를 필수 전략으로 삼지 않는다. lock 순서, transaction 경계,
중복 방어와 최종 invariant를 안정적으로 검증한다.

---

## 테스트 우선순위 2

* 결과 화면과 count-only 집계 표시
* locale이 개입되는 핵심 사용자 메시지
* Turbo/HTML 응답 분기
* 인쇄용 결과 화면 또는 export
* 운영 이벤트와 감사 기록
* 접근성에 영향을 주는 핵심 ballot 상호작용

세세한 view 구조, Tailwind class, 자주 바뀌는 문구와 관리자 화면의 장식적 UI는 후순위다.

---

## 테스트 레벨

### model / DB spec

도메인 불변식과 상태·관계 제약을 고정한다.

주요 대상:

* School, SchoolMembership, Classroom, Student
* Poll, PollSession, PollParticipant, PollProgress, PollParticipation
* PollContestCompletion과 option/contest tally
* source/replacement Session 관계

검증 초점:

* 학교·소유권·snapshot 관계
* unique와 상태 제약
* replacement 연결과 source 이력 보존
* count-only tally와 개인 선택 비연결

### service spec

상태 전이, transaction과 lock 경계가 중요한 작업을 고정한다.

주요 흐름:

* PollSession 시작과 snapshot 생성
* submit/participation/advance
* close/stop과 integrity check
* 일반·schoolwide replacement 재투표
* schoolwide start/stop/close/reset와 batch broadcast

Election ID 6의 DB 복원·변환 검증은 runtime service spec과 분리한다.

### policy spec

global role, SchoolMembership role, 학교 scope와 실제 operator 경계를 고정한다.

* admin, manager, 일반 teacher의 범위를 구분한다.
* 다른 학교·다른 Classroom·다른 operator 접근을 차단한다.
* school-managed Poll 전체 lifecycle과 학급 Session 운영 권한을 분리한다.

### request spec

controller 권한, 응답 형식과 상태 변화를 고정한다.

* 주요 HTML/Turbo lifecycle action과 권한 차단
* stale action의 안전한 실패 또는 terminal 복귀
* recovery endpoint의 정상 `204`, stale/terminal Turbo 응답과 active ballot 보존
* schoolwide parent lifecycle, 학급 Session 재투표와 Test Poll endpoint
* 잘못된 요청 뒤 DB 상태·event·tally 불변

### system / browser spec

실제 브라우저 통합이 필요한 최소 흐름만 둔다.

* Classroom/Student에서 Poll draft와 PollSession을 시작하는 happy path
* 교사 승인형 ballot, 학생 제출, 다음 학생, 명시적 종료
* replacement 후 새 Session 운영과 source 이력 접근
* terminal 화면 수렴과 중요한 Turbo UI 흐름
* active ballot 선택 유지와 hidden-tab polling pause처럼 JS 동작이 핵심인 계약

중단 복구, 멱등성과 대부분의 polling 서버 계약은 system spec보다 model/service/request spec으로 먼저 고정한다.

---

## 테스트 작성과 보강 순서

새 기능이나 회귀 수정에서는 다음 순서를 기본으로 한다.

1. model/DB 불변식과 권한 경계
2. service transaction·상태 전이·lock 계약
3. request 권한·응답·stale/terminal 처리
4. 실제 브라우저 통합이 필요한 최소 happy path

이미 구현·검증된 PollSession 중단, replacement 재투표, recovery polling과 lock order를 미래 기능
목록으로 두지 않는다. 변경이 생기면 해당 계약의 기존 회귀 테스트를 우선 보강한다.

---

## legacy 전환기의 테스트 역할

* 신규 Classroom/PollSession runtime은 현재 기본 회귀 대상이다.
* Election/ElectionSession runtime 전용 회귀 spec은 제거됐다.

다음 전환에서는 migration 자체보다 변환 전후 invariant와 조회 결과 보존을 우선 검증한다.

* Election ID 6 Classroom 변환 dry-run과 `APPLY=1` 결과
* historical/read_only 기반
* Election ID 6 historical Poll과 후보 사진 이관
* 운영 Poll 조사와 필요한 PollSession backfill
* 신규/legacy runtime 분리와 legacy table 제거 전 회귀

legacy spec을 일괄 삭제하지 않는다. 대응 runtime과 보존 데이터가 제거되거나 변환된 뒤 관련 회귀 범위를
확인하고 정리한다.

---

## 수동 Smoke Checklist

자동 테스트와 별도로 실제 교실 운영 흐름을 짧게 확인한다.

* 담당 Classroom의 Student 명단과 draft Poll을 준비한다.
* PollSession을 시작하고 첫 학생 ballot을 연다.
* 제출·기권·미참여와 다음 학생 진행을 확인한다.
* 새로고침·재로그인 뒤 DB의 현재 위치로 복구되는지 확인한다.
* 중복 또는 stale 제출이 집계를 바꾸지 않는지 확인한다.
* 모든 학생 처리 뒤 Session을 종료하고 결과를 확인한다.
* 중단과 replacement 재투표가 source 이력을 보존하는지 확인한다.
* school-managed Poll의 학급 Session과 parent 종료 흐름을 확인한다.

Cable 단절이나 deadlock을 매번 수동으로 재현하는 절차는 필수 smoke 항목으로 두지 않는다.

---

## 피해야 할 테스트

* 구현 세부사항에 과하게 결합된 테스트
* 낮은 가치의 단순 마크업 고정 테스트
* request/system 테스트의 과도한 중복
* helper/shared context 남용으로 읽기 어려워진 테스트
* 확정되지 않은 정책을 성급히 고정하는 테스트
* 수동으로 자주 바꾸는 UI 문구나 Tailwind class만 검증하는 테스트
* 모든 기능을 system spec으로만 검증하려는 테스트
* DevTools Cable 단절이나 실제 deadlock 재현에 의존하는 flaky 테스트

---

## 문서와 테스트의 관계

* 테스트는 `docs/specs/*.md`, `docs/architecture/current_system.md`, 관련 architecture 문서의 합의된 요구사항을 기준으로 작성한다.
* spec이 부족한 기능은 현재 구현과 정책을 읽고 필요한 경우 spec 문서를 보강한 뒤 테스트를 설계한다.
* 문서가 구현과 충돌하면 실제 코드와 합의된 정책을 확인한 뒤 문서를 갱신한다.
* archive/legacy 문서는 현재 문서만으로 맥락을 알 수 없을 때만 참고한다.
* 테스트는 과거 구현을 복제하는 장치가 아니라 현재 도메인 규칙과 사용자 흐름을 안전하게 고정하는 장치다.

---

## 한 줄 기준

테스트는 coverage를 채우기 위한 작업이 아니라,
투표 진행, 중단 복구, 중복 제출 방지, 권한 경계와 비밀투표 원칙을 안전하게 바꿀 수 있게 만드는 안전망이다.
