# Current System

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`의 현재 구현 상태와 문서 구조를 요약한다.

현재 프로젝트는 교사가 교실에서 장치 하나로 선거, 토의, 토론 유형의 투표를 운영할 수 있도록
기존 선거 흐름을 `Poll` 중심 도메인으로 확장하는 단계다.
초기 운영 목표는 학급 반장/부반장 선거를 안정적으로 진행할 수 있는 MVP이며,
토의/토론은 같은 진행·집계 구조를 재사용하는 방향으로 넓힌다.

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
- 투표 중단 후 복구
- 중복 제출 방지

초기 MVP 제외 범위:

- 전교어린이회 선거 중앙 집계
- 전교 투표용 관리자 대시보드
- 후보 사진 등록
- 선거관리위원 개표 승인
- 암호화 개표
- 학생 개인 계정/PIN 로그인
- 학생 개인 단말 투표
- ActionCable 기반 실시간 대시보드
- PDF 출력 고도화

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
- 로그인 후 역할별 placeholder dashboard 추가
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
- `Poll` status enum을 `draft`, `in_progress`, `closed`로 확장
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
- 문서 기반 설계 정리 중

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
  - 투표 중단 복구
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
  - 전교어린이회 선거 확장 구상

---

## 우선 개발 순서

1. 프로젝트 문서 기반 정리
2. 인증/역할 기본 구조
   - 교사 계정은 공개 가입이 아니라 admin 관리 기능에서 생성하는 방향
   - 로그인 후 admin/teacher별 placeholder dashboard 제공
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
   - 구현됨: `Poll` enum을 `draft`, `in_progress`, `closed`로 확장
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
