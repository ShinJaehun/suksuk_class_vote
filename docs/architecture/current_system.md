# 현재 시스템

## 목적

이 문서는 현재 저장소에 구현된 runtime, 사용자 흐름과 운영 경계를 요약한다. 세부 불변조건은 관련 architecture 문서를 따른다.

## 기술 구성

- Ruby on Rails 8.1
- PostgreSQL
- Devise `database_authenticatable`, `rememberable`
- Pundit
- Turbo, Stimulus, Action Cable
- Active Storage
- RSpec

## 현재 데이터 모델

### 조직과 계정

- `School`: 데이터와 학교 권한의 경계
- `Classroom`: 학교·학년도·학년·반과 선택적 담임 교사
- `Student`: Classroom에 속하는 번호·이름·active 상태의 명단 데이터
- `User`: `login_id`로 로그인하는 `teacher` 또는 global `admin`
- `SchoolMembership`: teacher의 학교 소속, `member` / `manager` 역할과 선택적 학년

학생은 User가 아니며 로그인, PIN, 개인 계정을 사용하지 않는다. 한 teacher는 하나의 SchoolMembership을 가지며, 활성 teacher 한 명은 활성 Classroom 하나를 담당할 수 있다.

### 투표 정의와 실행

- `Poll`: 투표 정의, 유형, 소유자, 학교 범위와 lifecycle
- `PollContest`: 회장·부회장 또는 설문 항목
- `PollOption`: 항목의 후보·선택지
- `PollSession`: 한 Classroom의 실제 실행 단위와 당시 학급·운영자 snapshot
- `PollParticipant`: 시작 시 Student에서 복사한 번호·이름·순서 snapshot
- `PollParticipation`: 학생별 처리 상태(`completed`, `absent`, `abstained`)
- `PollContestCompletion`: 학생이 특정 항목 제출을 마쳤다는 사실
- `PollProgress`: 현재 학생, ballot 상태와 세션 진행 상태
- `PollOptionTally`: 선택지별 count-only 득표
- `PollContestTally`: 항목별 count-only 기권 수
- `PollEvent`: 선택 내용이 아닌 운영 이벤트

PollParticipation과 PollContestCompletion은 진행 무결성을 위한 상태다. 어떤 학생이 어떤 PollOption을 선택했는지는 저장하지 않는다.

## 학급투표

일반 학급투표는 `school_managed: false`인 Poll과 Classroom의 PollSession으로 구성한다. 교사는 정의와 명단을 준비하고 PollSession을 시작한다.

시작 service는 transaction 안에서 다음을 함께 수행한다.

- active Student를 번호 순으로 PollParticipant에 복사
- PollProgress 생성과 첫 current participant 지정
- option·contest tally 초기화
- PollSession을 `in_progress`로 전환
- 시작 event 기록

교사가 학생 투표 창을 열고 잠그며 학생은 현재 항목을 선택하거나 기권한다. 제출은 completion과 count-only tally를 같은 transaction과 row lock 안에서 갱신한다. 다음 학생 이동과 PollSession 종료는 교사가 명시적으로 수행한다.

## 전교투표

전교투표는 `school_managed: true`인 parent Poll과 대상 Classroom별 PollSession을 사용한다.

- manager 또는 global admin이 Poll 정의와 대상 학급을 준비한다.
- parent Poll 시작은 전체 투표를 `in_progress`로 전환한다.
- 각 학급 PollSession은 담당 교사 또는 허용된 운영자가 개별 시작·운영한다.
- manager는 자기 학교의 전체 진행을 조회하고, 정책이 허용하는 중단·재투표·종료를 관리한다.
- 모든 current PollSession이 무결한 `closed` 상태일 때 parent Poll을 명시적으로 종료한다.
- 학교 전체 결과에는 current `closed` PollSession만 포함한다.

중단된 Session과 replacement Session은 덮어쓰거나 삭제하지 않는다. current execution은 replacement가 없는 Session이며, 재투표도 source 이력을 보존한다.

## 인증과 권한

로그인 식별자는 `login_id`다. User에 현재 email 계정 필드는 없다. 상단의 계정 링크는 비밀번호 변경 화면으로 이동하며, 현재 비밀번호를 확인한 뒤 새 비밀번호를 저장한다. teacher profile의 개별 edit route는 없고 admin과 manager는 `/teachers` 관리표에서 권한 범위의 계정을 관리한다.

권한의 최종 판단은 controller와 Pundit policy가 담당한다.

- global admin: 전체 School·Classroom·Student·teacher와 Poll 관리
- manager: 자기 학교의 선생님·교실과 school-managed Poll 관리
- 일반 teacher: 담당 Classroom·Student, 자기 Poll과 실제 운영 PollSession
- student: 인증 주체가 아님

같은 학교 manager는 school-managed PollSession을 조회할 수 있지만 실제 operator가 아니면 `operate?` 권한이 없다. 화면 버튼, Turbo 구독과 별개로 모든 mutation endpoint가 policy와 service guard를 다시 확인한다.

## 상태와 결과

PollSession 상태는 `draft`, `in_progress`, `closed`, `stopped`다. Poll도 정의와 실행 범위에 맞는 lifecycle을 가지며 잘못된 상태 전이는 model/service에서 거부한다.

학생별 표시 정책은 다음과 같다.

| 내부 참여 상태 | 학생별 UI |
| --- | --- |
| `completed` | 투표 완료 |
| `abstained` | 투표 완료 |
| `absent` | 미참여 |
| participation 없음 | 대기 |

학생 이름과 기권 여부를 연결하지 않는다. 기권 수는 PollContestTally의 익명 집계와 결과 화면에서만 표시한다. 상태 점검과 결과의 표시용 완료 수는 `completed + abstained`다.

## Snapshot과 역사 기록

PollParticipant의 이름·번호는 시작 당시 Student snapshot이다. PollSession은 `classroom_name_snapshot`, `operator_name_snapshot`을 보존한다.

- snapshot이 있으면 역사 표시의 기준으로 사용한다.
- 학급명 화면에서는 snapshot의 선두 학년도만 제거해 당시 학년·반을 표시한다.
- 결과 학년 그룹도 snapshot에서 읽은 역사적 학년을 우선한다.
- snapshot이 없거나 기존 형식에서 학년을 읽을 수 없는 데이터만 현재 Classroom 값을 fallback으로 사용한다.
- 현재 Classroom·Student·User 변경으로 기존 snapshot을 수정하지 않는다.

## Realtime과 HTTP 복구

DB가 authoritative state다. Turbo Stream과 Action Cable은 빠른 갱신 수단이며 HTTP polling/recovery는 broadcast 누락, 연결 단절과 오래 열린 stale 화면을 DB 상태로 수렴시키는 안전망이다.

- 교사 진행 Turbo Frame: 진행 중 5초 polling
- 학생 ballot Turbo Frame: 5초 polling, 활성 입력 form과 terminal 상태를 고려해 교체 제어
- 학생 ballot recovery controller: 진행 중 10초 확인
- draft school-managed PollSession recovery controller: 10초 확인
- PollSession `operation_screen`: 진행 중이고 `PollSessionPolicy#operate?`가 true인 사용자만 구독
- 읽기 전용 manager: operation stream 없이 기존 교사 진행 HTTP polling으로 상태 갱신
- schoolwide runtime stream: active global admin 또는 해당 학교의 active manager별 recipient stream

Turbo broadcast는 권한 판단의 원본이 아니며 mutation 권한을 부여하지 않는다. recovery 응답도 현재 DB 상태와 요청 presentation을 기준으로 필요한 작은 영역만 갱신한다.

## 운영 무결성

- 제출·기권·미참여·진행 이동은 transaction과 Session 기준 lock을 사용한다.
- 중복 또는 stale 요청은 tally를 두 번 증가시키지 않는다.
- 진행 중 구조 변경, 비활성화와 destructive action은 model·policy·service guard를 통과해야 한다.
- 종료 전 SessionStatusCheck가 snapshot, progress, completion, participation과 tally 수치의 일관성을 확인한다.
- 결과는 개인 선택을 복원하지 않고 Session별 count-only tally를 합산한다.

세부 내용:

- [학교 기반 투표 아키텍처](school_voting_platform.md)
- [비밀투표와 집계](privacy_and_tally.md)
- [복구와 무결성](recovery_and_integrity.md)
- [역할과 권한](roles_and_permissions.md)
