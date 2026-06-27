# Current System

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`의 현재 구현 상태와 문서 구조를 요약한다.

현재 프로젝트에는 두 운영 흐름이 있다. 교사가 학급에서 선거, 토의, 토론을 운영하는
`Poll` 흐름과, admin이 여러 학급의 전교임원선거를 구성하고 각 교사가
`ElectionSession`을 운영하는 `Election` 흐름이다.
두 흐름은 화면 일부를 공유하지만 상태, 권한, 결과 집계 기준은 분리한다.

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

교사 주도 학급 `Poll` MVP 자체의 제외 범위이며, 일부는 별도 Admin `Election`
흐름으로 구현되어 있다.

- 전교임원선거 중앙 집계
- 전교 투표용 관리자 대시보드
- 후보 사진 등록
- 선거관리위원 개표 승인
- 암호화 개표
- 학생 개인 계정/PIN 로그인
- 학생 개인 단말 투표
- ActionCable 기반 실시간 대시보드
- PDF 출력 고도화

별도 Admin `Election` 흐름에서는 전교/여러 학급 운영을 위한 관리 기능이 구현되어 있다.
admin은 공식 명단, 후보, 후보 사진, 학급 세션을 구성하고 draft `Election`을 시작한다.
교사는 parent `Election`이 시작된 뒤 본인에게 배정된 `ElectionSession`을 운영한다.
중단된 세션도 `/polls`에서 확인할 수 있으며, 상세를 확인한 뒤 본인 목록에서만 숨길 수 있다.
Admin `ElectionCandidate` 후보자 사진은 전교임원선거 등에서 후보 식별을 돕기 위한 선택 입력이다.
교사 주도 학급 `Poll` 흐름에는 사진 기능을 도입하지 않는다.

전교임원선거의 canonical 정책은 `docs/specs/school_council_election.md`를 따른다.

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

- Rails 앱 생성
- PostgreSQL 사용
- Tailwind CSS 사용 예정
- 투표 도메인 모델을 MVP 순서대로 구현 중
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
- 학생 투표 화면은 후보 선택과 기권만 제공하고, 미참여 처리와 다음 투표자 이동은 교사 투표 정보 화면에서만 제공
- 학생이 후보 선택 또는 기권을 완료하면 ballot은 다시 locked 상태가 되고, 교사 화면에는 완료 상태와 다음 투표자 진행 버튼을 표시
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
- 화면 표시 용어 정리: `Election` kind `school_council`은 `전교임원선거`, `Poll` kind `election`은 `학급선거`, `discussion`은 `학급토의`, `debate`는 `학급토론`으로 표시
- 알 수 없거나 custom인 `Election` kind는 강제 번역하지 않고 원래 kind 값을 fallback으로 표시
- `admin/elections`의 큰 제목 `선거 관리`는 관리 영역 이름으로 유지
- 투표/선거 이벤트 시간은 기존 KST 표시 helper 정책에 따라 KST 기준으로 표시
- 문서 기반 설계 정리 중

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

### Poll과 전교임원선거의 경계

`Poll`은 교사가 직접 만드는 학급 활동 단위다. 생성, 후보/선택지 구성, 진행, 중단,
종료, 보관을 해당 교사가 담당한다.

전교임원선거는 admin이 만든 parent `Election` 아래에 학급별 `ElectionSession`을
배정하는 구조다. Admin은 전체 구성, 중단, 재투표, 최종 종료와 결과 집계를 담당하고,
teacher는 본인 학급 세션의 시작과 진행만 담당한다.

Legacy Poll-backed `school_election` 구현은 현재 배포 전에 제거하지 않는다.
실제 선거와 데이터 백업이 끝난 뒤 별도 리팩터링 대상으로 검토한다.

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

1. 프로젝트 문서 기반 정리
2. 인증/역할 기본 구조
   - 교사 계정은 공개 가입이 아니라 admin 관리 기능에서 생성하는 방향
   - 로그인 후 teacher는 `/polls`, admin은 `/admin/teachers`로 진입
   - root와 `/dashboard`는 역할별 기본 경로로 redirect하는 안전한 진입점으로 유지
   - admin은 교사 계정 목록 조회와 생성 가능
3. 참여자 그룹 등록
   - 참여자 그룹 기본 CRUD 중 index/new/create/show/edit/update/destroy 구현
   - 학생 1명 추가 구현
   - 학생 이름 수정/삭제 구현
   - 학생 수 입력 후 이름 입력칸을 만드는 bulk 추가 구현
4. 학생 명단 bulk import
   - HWP/Excel 붙여넣기 import는 후속 기능
5. 학급 선거 생성
   - 최소 draft 선거 생성 구현
   - 투표 참여자 명단 snapshot은 투표 시작 시점에 생성
6. 후보자 등록
   - draft 선거에서 후보자 이름 등록/수정/삭제 구현
   - 후보자 번호는 선거 안에서 자동 부여하며 삭제 후 재정렬하지 않음
7. 선거 시작 조건과 투표 참여자 명단 snapshot 구현
   - 구현됨: `Poll` enum을 `draft`, `in_progress`, `stopped`, `closed`로 확장
   - 구현됨: `PollParticipant` 모델 추가
   - 구현됨: `Polls::Start` service 추가
   - 구현됨: 후보자 2명 이상 일반 경쟁 투표 start 조건 검증
   - 구현됨: 선거 시작 시점에 snapshot 생성
   - 구현됨: snapshot 생성, 상태 변경, `PollProgress` 생성을 transaction으로 처리
   - 구현됨: 선거 시작 성공 시 첫 번째 `PollParticipant`를 `PollProgress.current_poll_participant_id`로 저장
   - 후보자 1명 무투표 당선/찬반 투표 정책은 후속 결정
8. 투표 진행 상태 모델링
   - 문서화됨: `PollParticipant`는 고정 명단으로 유지
   - 문서화됨: 진행 상태와 실제 투표 결과 분리
   - 구현됨: `PollProgress`을 초기 MVP 진행 상태 모델명으로 사용
   - 구현됨: `PollProgress.current_poll_participant_id`를 현재 위치 복구 기준으로 사용
   - 문서화됨: `VoteSession`은 학생 화면/토큰/제출 세션이 복잡해질 때 후속 검토
9. 교사용 진행 화면
10. 학생 투표 화면
11. 트랜잭션 기반 투표 제출
12. 중단 복구/중복 제출 방지 테스트
13. 결과 확인 화면

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

- 전체 RSpec 1029 examples, 0 failures 통과.
- 브라우저 smoke test 통과.
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
