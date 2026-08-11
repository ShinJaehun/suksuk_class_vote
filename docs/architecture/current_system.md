# Current System

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`의 현재 구현 상태와 문서 구조를 요약한다.

모든 신규 학급투표와 전교투표는 `Poll` 정의와 학급별 `PollSession`으로 운영한다.
`Poll.kind`는 선거, 설문조사, 토의, 토론을 표현한다. 기존 `Election`/`ElectionSession`
runtime은 Election ID 6의 historical Poll 변환과 검증이 끝날 때까지 호환 목적으로 남지만,
신규 Election 기능은 더 이상 개발하지 않는다.

---

## 제품 방향

`쑥쑥교실투표`는 학생 개인 온라인투표 서비스가 아니다.

초기 방향은 다음과 같다.

- 학생은 계정, PIN, 개인 단말 없이 교사 장치 앞에서 투표한다.
- 교사는 참여자 그룹을 등록하고, 그 그룹을 대상으로 투표를 만든다.
- 교사는 활동 유형에 맞는 선택지를 등록한 뒤 출석번호 순서로 투표를 진행한다.
- 투표가 끝나면 결과를 확인한다.
- 투표 중 새로고침, 브라우저 종료, 컴퓨터 재부팅, 교사 재로그인이 발생해도 서버 DB 기준으로 진행 위치를 복구할 수 있어야 한다.

---

## 초기 MVP 범위

초기 MVP는 학급 반장/부반장 선거에 집중한다.

포함 범위:

- 교사 로그인
- 참여자 그룹 등록
- Excel/HWP 표 복사·붙여넣기 기반 학생 명단 등록
- 학급 선거 생성
- 후보자 등록
- 투표 진행 화면
- 학생 투표 화면
- 미참여/무투표 처리
- 투표 종료
- 결과 확인
- 투표 도중 장애 복구
- 중복 제출 방지
- 종료 투표 수동 보관

다음은 초기 MVP에서 제외됐던 범위다. 이 가운데 전교투표 중앙 집계와 관리자 화면은
신규 Classroom/PollSession runtime에서 현재 구현됐다.

- 학급 election과 전교 non-election의 사진 등록
- 선거관리위원 개표 승인
- 암호화 개표
- 학생 개인 계정/PIN 로그인
- 학생 개인 단말 투표
- ActionCable 기반 실시간 대시보드
- PDF 출력 고도화

전교투표 관리자는 Poll 정의, 항목과 선택지, 여러 Classroom PollSession을 구성하고 전체 Poll을
시작·종료한다. 담당 교사는 parent Poll이 in_progress가 된 뒤 자기 PollSession을 운영한다.
학급투표 사진과 전교 non-election 이미지는 후속 작업이다.

## 배포 저장소 정책

production에서 Active Storage local service를 사용할 수 있다.
단, Docker 컨테이너 내부 writable layer에만 `/rails/storage` 또는 `storage/`를 두면
컨테이너 재생성이나 이미지 교체 시 업로드 파일이 사라질 수 있다.
OCI 단일 VM 배포에서는 host directory 또는 Docker volume을 Rails container의 storage 경로에 mount하는 방식을 기본 운영안으로 둔다.
예를 들어 host `/var/www/suksuk_class_vote/storage`를 container `/rails/storage`에 mount한다.
서버를 여러 대로 늘리거나 ephemeral filesystem 환경을 쓰게 되면 OCI Object Storage 또는 S3 같은 object storage 전환을 검토한다.

---

## 현재 구현 상태

현재 상태:

### 초기·legacy runtime 구현 연혁

- Rails 앱 생성
- PostgreSQL 사용
- Tailwind CSS 사용
- 투표 도메인은 신규 Classroom/PollSession runtime까지 구현하고 legacy runtime을 단계적으로 전환 중
- Devise 기반 `User` 인증 구조 추가
- Devise `registerable` 미사용: 교사 공개 회원가입 없음
- `User` role enum 추가: `teacher`, `admin`
- 개발용 admin seed 추가: `admin@example.com`
- 로그인 후 기본 진입 경로 정리: teacher는 `/polls`, admin은 `/admin/teachers`
- root와 `/dashboard`는 삭제하지 않고 역할별 기본 경로로 redirect하는 안전한 진입점으로 유지
- admin의 교사 계정 목록/생성 기능 추가
- `ParticipantGroup` / `ParticipantSlot` 모델 기반 추가
- 참여자 그룹 index/new/create/show/edit/update/destroy 추가
- 참여자 그룹 상세 화면에서 `ParticipantSlot` 1명 추가 기능 추가
- `ParticipantSlot` 학생 이름 수정/삭제 기능 추가
- 학생 수 기반 bulk 입력으로 `ParticipantSlot` 여러 명 추가 기능 추가
- `Poll` 최소 모델 추가
- 투표 index/new/create/show 추가
- 투표 생성 시 학생이 등록된 `ParticipantGroup` 선택 기능 추가
- `PollOption` 최소 모델 추가
- draft 상태 투표의 선택지 new/create/edit/update/destroy 추가
- 선거 시작 조건과 투표 참여자 명단 snapshot 정책 문서화
- `Poll` status enum을 `draft`, `in_progress`, `stopped`, `closed`로 확장
- `PollParticipant` snapshot 모델 추가
- 선택지 2개 이상 일반 경쟁 투표에 한해 투표 시작 기능 추가
- `Polls::Start` service로 투표 참여자 명단 snapshot 생성과 `in_progress` 상태 전이를 transaction 처리
- `PollProgress` 모델 추가
- 투표 시작 성공 시 첫 번째 `PollParticipant`를 현재 위치로 가리키는 `PollProgress` 생성
- Pundit 기본 설치
- RSpec 테스트 환경 추가
- 투표 진행 상태 1차 구현
- 투표 완료 기록과 후보별 count-only 집계 구조 문서화
- `PollParticipation`과 `PollOptionTally` 최소 모델 추가
- 투표 시작 성공 시 선택지별 `PollOptionTally`를 0표로 생성
- `Polls::SubmitVote` service 추가
- 투표 상세 화면에서 현재 참여자의 선택 제출 연결
- 투표 시작 후 선택지 추가/수정/삭제 차단
- draft 투표는 아직 `PollParticipant` snapshot이 없고 원본 참여자 그룹을 직접 참조
- draft 상태에서도 원본 참여자 그룹 이름 수정과 학생 추가/수정/삭제 허용
- draft 투표가 현재 참조 중인 원본 참여자 그룹 자체 삭제 차단
- 진행 중/종료된 투표는 `PollParticipant` snapshot 기준으로 진행·보존하므로 원본 참여자 그룹/학생 명단 편집/추가/삭제 허용
- 현재 참여자를 미참여 또는 기권으로 확정 처리하는 기능 추가
- 확정 상태인 현재 참여자에서 다음 `PollParticipant`로 이동하는 기능 추가
- 마지막 참여자 확정 뒤 투표 종료와 선택지별 count-only 결과 표시 추가
- closed 결과 화면에 참여 요약과 최다 득표 후보 표시 추가
- `Polls::IntegrityReport` service와 선거 상세 상태 점검 카드 추가
- in_progress / closed 상태의 운영 요약 표시 추가
- 현재 참여자 포인터가 비어 있는 제한 상황에서 첫 미처리 학생으로 재개하는 기능 추가
- `PollEvent` 모델과 투표 운영 이벤트 기록 추가
- 투표 상세 화면에 최근 운영 기록 표시 추가
- 진행 중인 투표 중단 기능 추가
- 후보 선택/기권/미참여 요청에 현재 참여자 id를 포함하고, service가 lock 이후 현재 참여자를 재확인해 오래 열린 투표 화면의 stale 제출을 거부
- 다음 참여자 이동/투표 종료 요청도 현재 참여자 id를 포함하고, service가 lock 이후 현재 참여자를 재확인해 늦게 도착한 운영 요청을 거부
- 투표 화면과 운영 액션 버튼에 Turbo submit 중 문구를 적용해 중복 클릭으로 인한 혼란 완화
- 교사 승인형 ballot 흐름 추가: 투표 시작 직후 ballot은 locked이며, 교사가 현재/다음 투표자 버튼을 눌러야 해당 학생 ballot이 열린다.
- 학생 투표 화면은 PollContest별로 현재 항목 하나의 선택 또는 기권만 제출하며, 다음 미완료 항목부터 이어서 진행
- `PollContestCompletion`은 항목 제출 완료 사실만 저장하고 학생이 선택한 PollOption은 저장하지 않음
- 모든 PollContest를 완료한 시점에만 completed participation을 만들고 ballot을 다시 locked 상태로 전환
- 부분 완료 학생은 남은 항목을 마칠 때까지 미참여 처리, 다음 투표자 이동과 PollSession 종료를 차단
- 상태 점검 카드의 표시용 투표 완료 수는 `completed + abstained`이며, 기권 항목은 별도로 표시하지 않음
- 학생 submit/기권/미참여/다음 투표자 진행 직후 투표 진행, 운영 기록, 상태 점검 카드가 Turbo로 갱신됨
- `Polls::Close`가 `closed` 전환 직전에 참여 처리 수, count-only tally 합계, 선택지/tally row 대응, 다른 투표 선택지 연결, 음수 득표수를 검증
- draft, stopped, 보관 전 closed 투표 삭제 기능 추가
- closed 투표 수동 보관 기능 추가
- 보관은 status가 아니라 `archived_at`으로 관리
- 기본 투표 목록 `/polls`에서는 보관된 투표를 숨기고, 보관 목록 `/polls/archived`에서 확인
- 보관된 투표 상세 `/polls/:id` 접근 가능
- Admin `Election` 상세 화면에 상태점검, 기본 정보, 학급 세션 목록을 표시하고 Turbo Stream `admin_overview`로 갱신
- Admin `Election`이 `closed` 된 뒤 접근 가능한 결과 페이지 `/admin/elections/:id/results` 추가
- Admin `Election` 목록 `/admin/elections`는 선거 이름, 종류 배지, 상태 배지, 관리/시작 준비 버튼 중심으로 간결하게 표시
- Admin `Election` 목록 카드에서는 후보 구성, 학급 수, 완료 수 요약을 표시하지 않음
- Admin `Election` 상세 상단 요약 카드에서는 선거 이름 옆에 종류 배지와 상태 배지를 함께 표시
- Admin 전체 집계는 `closed` `ElectionSession`의 tally만 합산하고, draft/in_progress/stopped 세션은 전체 득표 합산에서 제외
- 결과 페이지의 전체 진행 현황과 학급별 집계도 `closed` `ElectionSession`만 표시
- draft/in_progress/stopped 세션은 결과 페이지에 표시하지 않으며, stopped 이력은 Admin 선거 상세에서 별도 보존
- admin의 `Election` 시작 조건 검증 추가: draft 상태, 학급 세션 1개 이상, 선거 항목 1개 이상, 각 항목 후보자 1명 이상
- 중단 이력인 `stopped` 세션을 제외한 모든 `ElectionSession`이 `closed`가 되어도 parent `Election`은 `in_progress`를 유지하며, admin이 명시적으로 종료할 때만 `closed`로 전환
- admin은 특정 학급 세션을 stopped 이력으로 보존하고 같은 학급의 draft replacement 세션을 만드는 재투표를 실행할 수 있음
- stopped 세션은 Admin 선거 상세와 직접 상세에서 voter, participation, tally, event와 함께 보존
- 담당 교사는 stopped 세션 상세에서 `hidden_from_teacher_at`을 기록해 본인의 `/polls` 목록에서만 숨길 수 있음
- `Election` 시작 뒤 학급 세션 추가/삭제와 후보자 등록/수정/삭제 차단
- 화면 표시 용어 정리: 사용자 범위는 `학급투표`와 `전교투표`, Poll kind는 `선거`, `설문조사`, `토의`, `토론`으로 표시
- 알 수 없거나 custom인 `Election` kind는 강제 번역하지 않고 원래 kind 값을 fallback으로 표시
- `admin/elections`의 큰 제목 `선거 관리`는 관리 영역 이름으로 유지
- 투표/선거 이벤트 시간은 기존 KST 표시 helper 정책에 따라 KST 기준으로 표시
### 신규 Classroom/PollSession runtime

- School·SchoolMembership·Classroom·Student 조직 기반 구현
- admin은 전체 학교, manager는 소속 학교, 일반 teacher는 담임 Classroom 범위에서 학급·학생을 관리
- Student 단일·bulk 등록과 비활성화·복구 구현
- PollSession foundation과 실행 기록의 nullable `poll_session_id` 연결 구현: 신규 기록은 `poll_id`와 `poll_session_id`를 함께, legacy 기록은 `poll_session_id = NULL`로 유지
- 신규 Poll 정의와 최초 draft PollSession 동시 생성, 시작 시 active Student의 PollParticipant snapshot 생성 구현
- `/polls/new`는 투표 이름과 활동 유형만 입력받고 현재 사용자의 active Classroom을 서버에서 사용한다.
  생성 transaction은 draft Poll, 기본 PollContest 1개, option이 없는 draft PollSession을 만들고
  해당 PollSession 초안 작업 화면으로 이동한다.
- draft PollSession에서 투표 이름·활동 유형, Contest·Option, 학생 명단 연결, 준비 상태와 시작을 관리한다.
  학급투표 Contest·Option은 inline Turbo Frame으로 편집하며 전교투표의 전체 페이지 편집과 후보 사진 흐름은 유지한다.
- Poll 활동 용어는 `Poll#activity_label`, `#contest_label`, `#choice_label`, `#choice_number_label`을 단일 출처로 사용한다.
- Contest·Option 변경 뒤 변경 영역과 상태 점검·시작 영역만 갱신하며 준비 상태는 `Polls::SessionStatusCheck`로 판정한다.
- 초안 화면의 학생 명단 관리는 검증된 `return_poll_id`, `return_poll_session_id` context로 기존 Classroom 학생 화면과 왕복한다.
- 시작·종료 form은 성공 응답의 outer `teacher_progress` Turbo Frame을 target으로 삼아 nested frame의
  `Content missing`을 피하며 기존 lifecycle, action, redirect, snapshot, event와 권한 정책은 바꾸지 않는다.
- PollSession의 고정 학생 투표 창, 교사 ballot open 승인, Contest별 단계 제출과 복구, count-only tally·완료 기록, 미참여 처리와 명시적 다음 학생 진행 구현
- PollSession 명시적 종료와 현재 Session tally·시작 당시 snapshot 기반 결과/투표자 명단 구현
- 일반 학급투표 PollSession 중단·stopped 이력 보존과 replacement Poll/PollSession 재투표,
  전교투표 학급 Session의 stopped/closed source를 보존하는 replacement 재투표 구현
- PollSession 교사 operation·학생 ballot 화면은 Turbo Stream을 우선 사용하고, 10초 간격의 가벼운
  recovery polling으로 누락된 stale/terminal 상태만 DB 기준으로 복구한다. hidden tab에서는 timer를
  중단하고, 다시 visible이 되면 즉시 확인한 뒤 재시작한다.
- `Polls::SessionStatusCheck`의 draft/in_progress/closed 단계 점검과 실제 PollSession action service 차단 연결
- `/school_polls` 전교투표 정의·항목·여러 Classroom 배정·전체 결과 관리 구현
- 전교투표 전체 준비 점검과 명시적 시작·종료, `Poll.started_at`/`closed_at`, Poll-level event 기록 구현
- 전교투표 parent가 in_progress일 때만 담당 교사가 draft PollSession을 시작하도록 제한
- 전교투표 종료·중단 시 operation과 ballot을 terminal 상태로 동기화하며, child Test Poll 강제 중단도
  ballot lock과 terminal 갱신을 수행하고 이미 closed인 Session 상태·결과는 보존한다.
- 전교투표 batch lifecycle의 Session별 aggregate broadcast를 transaction 동안 합치고 완료 뒤 최종 상태를
  broadcast한다. 전체 종료 readiness는 non-closed Session을 먼저 빠르게 거르고, 모두 closed일 때만
  preload된 association을 재사용하는 최종 무결성 검사를 수행한다.

### 전교 election 후보 UI

- 전교 election PollOption에만 JPG·PNG·WebP, 최대 15MB 후보 사진과 ballot 900×900·thumbnail 400×400 variant 지원
- 사진이 없는 전교 election 후보는 deterministic avatar를 표시하고 legacy 후보 카드·투표 도장 UI를 사용하되 Contest별 서버 제출 유지
- 후보 수에 따라 1·2·3·4·6·7열 grid를 사용
- global admin 전용 테스트 선거 항목 4개·후보 50명 생성 도구 구현

### 기존 Election/ElectionSession runtime

- 신규 ElectionSession은 Classroom 기반이며 기존 운영 데이터는 전환 기간 동안 ParticipantGroup 기반을 유지할 수 있는 dual-source 구조 구현
- 선택 Election의 명단 source를 Classroom/Student로 바꾸는 dry-run 기본·`APPLY=1` 변환 도구 구현
- 실제 Election ID 6 운영 데이터에는 변환 도구를 적용하지 않음

현재 PollSession 흐름은 교사 시작 → active Student snapshot과 첫 current 지정 → ballot locked → 학생
투표 창 → 교사 승인으로 ballot open → Contest별 제출과 tally/completion 기록 → 모든 Contest 완료 뒤
participation 기록과 ballot locked → 교사의
명시적 다음 학생 지정 → 반복 → 교사의 명시적 종료 순서다. 자동 다음 학생 전환과 자동 종료는
의도적으로 사용하지 않는다. 개인별 학생 선택은 저장하거나 표시하지 않는다. 부분 완료는 다음 미완료
Contest부터 복구하며 완료한 Contest의 취소·개별 재투표는 지원하지 않는다. 학생별 선택 후보는 사진
표시와 무관하게 저장하지 않는다.

일반 학급투표 생성은 Poll과 최초 PollSession을 만들고, 전교투표는 Poll 정의를 만든 뒤 여러
Classroom Session을 배정한다. 현재 runtime 경계는 다음과 같다.

1. 신규 Classroom/PollSession runtime: 위 학급·전교투표 흐름을 사용한다.
2. legacy ParticipantGroup 기반 Poll runtime: 기존 기록 호환을 위해 별도 경로가 남아 있다.
3. 기존 Election/ElectionSession runtime: Classroom/ParticipantGroup dual-source로 운영 기록을 호환한다.

PollSession 중단·stopped 운영 이력과 일반·전교투표 replacement 재투표는 구현됐다.
historical/read_only Poll과 Election ID 6의 historical Poll·후보 사진 변환은 미구현이며 운영 데이터에는
Classroom 변환 task조차 아직 적용하지 않았다. 신규/legacy Poll runtime 서버 측 분리, 운영 Poll
보존 범위 조사와 PollSession backfill 뒤 Election runtime/table과 ParticipantGroup·ParticipantSlot
제거를 판단한다.

현재 `Poll` 상태 흐름:

- `draft`: 준비
- `in_progress`: 진행
- `stopped`: 중단
- `closed`: 종료

`stopped`는 결과 확정 상태가 아니며 재시작하지 않는다.
`closed`는 결과와 기록 보존 대상이며 보관 전에는 삭제하거나 보관할 수 있다.
보관된 종료 투표는 `closed` 상태이면서 `archived_at`이 있는 투표다.
보관된 종료 투표는 기록으로 남기기로 한 상태이므로 삭제하지 않는다.
보관 해제와 종료 후 30일 자동 보관은 아직 구현하지 않았다.

### 학급투표와 전교투표의 경계

학급투표는 교사가 만드는 `school_managed: false` Poll과 담당 PollSession이다.
전교투표는 global admin 또는 같은 학교 manager가 만드는 `school_managed: true` Poll이며,
여러 Classroom PollSession을 배정한다. 관리자가 전체 Poll을 시작하면 담당 교사가 각 Session을
운영하고, 모든 Session이 closed가 된 뒤 관리자가 전체 Poll을 종료한다. 전체 결과에는 closed
Session tally만 포함한다.

기존 Election ID 6은 추후 historical Poll로 변환하고 검증한 뒤 Election runtime과 table을
제거한다. historical/read_only 상태는 변환 전에 별도 구현한다.

---

## 기준 문서

### 작업 원칙

- `AGENTS.md`
  - 에이전트 작업 원칙
  - 문서 참조 순서
  - 변경 승인 원칙
  - 브랜치/커밋/테스트 원칙

### 아키텍처 문서

- `docs/architecture/current_system.md`
  - 현재 구현 상태와 문서 허브

- `docs/architecture/recovery_and_integrity.md`
  - 투표 도중 장애 복구
  - 중복 제출 방지
  - DB source of truth
  - 트랜잭션 기반 집계 원칙

- `docs/architecture/privacy_and_tally.md`
  - 출석번호 진행 상태와 실제 투표 결과 분리
  - 비밀투표
  - 집계 방향 후보

- `docs/architecture/voting_domain.md`
  - ParticipantGroup 원본 명단
  - 선거 생성 시 ParticipantGroup 선택 정책
  - 선거 시작 조건 초안
  - `PollParticipant` snapshot 모델 설계
  - `Polls::Start` service 책임 설계
  - 투표 참여자 명단 snapshot 생성 시점과 무결성 원칙
  - Poll, PollProgress 등 후속 도메인 구조 초안

- `docs/architecture/roles_and_permissions.md`
  - admin/teacher/student 역할과 권한
  - 선거 시작 권한 초안

### Spec 문서

- `docs/specs/classroom_election_mvp.md`
  - 학급 반장/부반장 선거 MVP 흐름

- `docs/specs/bulk_student_import.md`
  - Excel/HWP 표 복사·붙여넣기 기반 학생 명단 등록

추후 추가 예정:

- `docs/specs/schoolwide_election_future.md`
  - 전교임원선거 확장 구상

---

## 우선 개발 순서

현재 신규 Classroom/PollSession의 생성·초안 편집·감독형 진행·결과 흐름까지 구현됐다.
남은 작업은 다음 순서로 진행한다.

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

현재 구현된 복구/무결성 화면:

- 선거 상세 상태 점검 카드
- 진행 중/종료 선거의 운영 요약
- 제한 조건을 만족할 때 첫 미처리 학생으로 재개
- 최근 운영 기록

현재 구현된 목록/보관 정책:

- 기본 투표 목록 `/polls`는 보관되지 않은 투표를 보여준다.
- 보관 목록 `/polls/archived`는 `archived_at`이 있는 종료 투표를 보여준다.
- 보관된 종료 투표도 상세 화면 `/polls/:id`로 접근할 수 있다.
- 보관 전 종료 투표는 삭제 또는 보관할 수 있고, 보관된 종료 투표는 삭제할 수 없다.
- 보관 해제와 종료 후 30일 자동 보관은 후속 과제다.

현재 구현된 진입/내비게이션 정책:

- teacher 로그인 후 기본 진입 경로는 `/polls`다.
- admin 로그인 후 기본 진입 경로는 `/admin/teachers`다.
- root와 `/dashboard`는 삭제하지 않고 역할별 기본 경로로 redirect한다.
- 로그인한 모든 사용자에게 `투표 목록`, `투표자 명단` 링크를 표시한다.
- admin에게는 추가로 `교사 관리`, `전교임원선거 관리` 링크를 표시한다.
- teacher에게 admin 전용 링크는 표시하지 않는다.

현재 검증 상태:

- 최근 전교 election 후보 사진·투표 카드 관련 집중 spec과 브라우저 검증은 통과했다.
- 최신 HEAD 전체 RSpec은 별도로 확인해야 한다.
- smoke 확인 항목:
  - admin root/dashboard -> `/admin/teachers`
  - teacher root/dashboard -> `/polls`
  - admin nav에 `투표 목록`, `투표자 명단`, `교사 관리`, `전교임원선거 관리` 표시
  - teacher nav에는 `투표 목록`, `투표자 명단`만 표시
  - admin/elections 목록 카드 단순화 확인
  - admin/elections/:id 제목 옆 배지 배치 확인

---

## 핵심 개발 원칙

이 프로젝트의 핵심은 기능 수가 아니라 안정성이다.

특히 다음 원칙을 우선한다.

- 브라우저 상태에 투표 진행을 의존하지 않는다.
- 현재 투표 중인 학생 위치는 DB 기준으로 복구한다.
- 투표 제출은 트랜잭션으로 처리한다.
- 중복 제출은 UI가 아니라 서버와 DB에서 막는다.
- 출석번호 진행 상태와 후보 선택 결과를 연결하지 않는다.
- 구현보다 먼저 spec과 도메인 원칙을 문서로 고정한다.
