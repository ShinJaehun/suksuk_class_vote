# Roles and Permissions

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`의 역할과 권한 구조를 정리하기 위한 architecture 문서다.

현재 프로젝트는 초기 설계 단계이므로, 이 문서는 실제 구현된 controller/action 매트릭스가 아니라 초기 권한 설계 원칙을 정리한다.
구현이 진행되면 실제 route, controller, policy 기준으로 권한 매트릭스를 갱신한다.

---

## 기본 원칙

* 서버측 권한 판단은 Pundit policy와 `policy_scope` 중심으로 유지한다.
* controller는 가능한 한 `authorize`, `policy_scope`를 호출하는 자리로 남긴다.
* 단건 권한 판단은 policy에 둔다.
* 목록 조회 범위 판단은 policy scope에 둔다.
* view는 가능한 한 controller와 policy에서 정리된 결과를 소비한다.
* view에서 직접 복잡한 권한 조건을 늘리지 않는다.
* admin 전용 UI라도 controller/policy가 별도 서버측 가드를 갖도록 한다.
* 권한 실패 응답은 HTML/Turbo/JSON 형식별로 일관되게 유지한다.
* 위험한 관리 기능은 감사 로그와 확인 절차를 함께 고려한다.

---

## 역할 개요

초기 역할은 `admin`, `teacher`를 중심으로 둔다.

`student`는 초기 MVP에서 로그인 계정으로 만들지 않는다.
학생은 교사 장치 앞에서 투표하는 참여자이며, 시스템상 인증 주체가 아니라 참여자 그룹의 명단 데이터로 취급한다.

---

## 역할 설명

### admin

`admin`은 서비스 전체 최고 관리자다.

가능한 역할:

* 교사 계정 생성/수정/비활성화
* 전체 교사 목록 조회
* 전체 참여자 그룹 조회/관리
* 전체 선거 조회/관리
* 전체 투표 진행 정보 조회/관리
* 전체 후보 조회/관리
* 전체 결과 조회
* 운영상 필요한 데이터 정리
* 전교임원선거 생성과 후보/사진 관리
* 학교별 공식 투표자 명단 관리와 학급 세션 배정
* 전교임원선거 시작, 중단, 재투표, 명시적 종료
* 종료된 전교임원선거 결과 집계 확인

`admin`은 특정 선거 유형에만 묶인 역할이 아니다.
학급 선거, 전교 선거, 운영 관리 전반에 대한 최고 권한을 가진다.

다만 실제 구현에서는 위험한 기능일수록 다음 장치를 둔다.

* 확인 화면
* 감사 로그
* 수정 사유 입력
* 선거 시작 후 수정 제한
* 투표 종료 후 수정 제한

---

### teacher

`teacher`는 본인이 관리하는 참여자 그룹과 선거를 운영하는 사용자다.

가능한 역할:

* 본인 계정으로 로그인
* 본인이 관리하는 참여자 그룹 생성
* 본인이 관리하는 참여자 그룹 수정/삭제
* 본인이 관리하는 참여자 그룹을 대상으로 선거 생성
* 본인 선거의 후보자 등록
* 본인 선거의 투표 진행
* 본인 선거의 투표 종료
* 본인 선거의 결과 확인
* 본인에게 배정된 전교임원선거 학급 세션 시작과 진행
* 담당 학급 학생의 미참여 처리와 학급 세션 종료
* 담당 stopped 세션 상세와 당시 진행 기록 확인
* 담당 stopped 세션을 본인 `/polls` 목록에서 숨김

제한:

* 공개 회원가입으로 직접 계정을 만들 수 없다.
* 다른 교사의 참여자 그룹에 접근할 수 없다.
* 다른 교사의 선거를 수정할 수 없다.
* 다른 교사의 투표를 진행할 수 없다.
* 다른 교사의 결과를 볼 수 없다.
* admin 기능에 접근할 수 없다.
* 전교임원선거 자체를 중단, 삭제 또는 종료할 수 없다.
* 전교임원선거 학급 재투표를 실행할 수 없다.
* 전교임원선거 비상 초기화를 실행할 수 없다.

---

### 전교임원선거 담당 교사 (미래 권한)

`school_election_manager`는 teacher 중 일부에게 부여할 예정인 전교임원선거 관리
권한이며 현재 구현되어 있지 않다.

예정 범위:

* 전교임원선거 중단
* 특정 학급 재투표

제한:

* 전교임원선거 삭제 불가
* 비상 초기화 불가
* admin 역할을 대체하지 않음

---

### student

초기 MVP에서 `student`는 로그인 계정이 아니다.

원칙:

* 학생 계정 없음
* 학생 PIN 없음
* 학생 개인 단말 투표 없음
* 학생은 교사 장치 앞에서 후보를 선택함
* 시스템 안에서 학생은 `ParticipantSlot` 또는 참여자 명단 데이터로 취급함

향후 다른 쑥쑥 서비스와 연동하더라도, `쑥쑥교실투표`의 초기 MVP에서는 학생 로그인을 도입하지 않는다.

---

### guest

로그인하지 않은 사용자는 주요 기능에 접근하지 못한다.

허용 가능 범위:

* 로그인 화면
* 서비스 소개 화면
* 비밀번호 재설정 화면

불가 범위:

* 참여자 그룹 조회
* 선거 조회
* 후보 조회
* 투표 진행
* 결과 확인
* 관리자 화면

---

## 주요 리소스별 권한 초안

현재는 구현 전이므로 리소스명은 변경될 수 있다.

### User / Teacher Account

| 리소스/액션     | admin |      teacher | guest | 비고                            |
| ---------- | ----: | -----------: | ----: | ----------------------------- |
| 교사 계정 목록   |    가능 |           불가 |    불가 | `admin/teachers#index` 구현      |
| 교사 계정 생성   |    가능 |           불가 |    불가 | `admin/teachers#new/create` 구현, role은 teacher로 강제 |
| 교사 계정 수정   |  미구현 | 본인 기본 정보만 미구현 |    불가 | 상세 범위는 구현 시 결정                |
| 교사 계정 비활성화 |  미구현 |           불가 |    불가 | 감사 로그 고려                      |

---

### 기본 진입과 내비게이션

로그인 후 기본 진입 경로는 역할별로 다르다.

| 역할 | 기본 진입 경로 | 권한 차단 redirect | 비고 |
| --- | --- | --- | --- |
| admin | `/admin/teachers` | `/admin/teachers` | 기본 관리 시작점은 교사 관리 |
| teacher | `/polls` | `/polls` | 교사용 투표 목록이 기본 업무 시작점 |
| guest | 로그인 화면 | 로그인 화면 | 주요 기능 접근 불가 |

root와 `/dashboard`는 삭제하지 않고 역할별 기본 경로로 redirect하는 안전한 진입점으로 유지한다.
중간 허브 성격의 dashboard 화면은 기본 진입점으로 사용하지 않는다.

내비게이션 정책:

* 로그인한 모든 사용자에게 `투표 목록`, `투표자 명단` 링크를 표시한다.
* admin에게는 추가로 `교사 관리`, `전교임원선거 관리` 링크를 표시한다.
* teacher에게 admin 전용 링크는 표시하지 않는다.
* admin도 기존 권한 정책에 따라 `/polls`, `/participant_groups` 접근과 내비게이션 링크를 유지한다.

---

### ParticipantGroup

참여자 그룹은 교사가 관리하는 학생 명단 묶음이다.

| 리소스/액션            | admin |   teacher | guest | 비고                  |
| ----------------- | ----: | --------: | ----: | ------------------- |
| 목록 조회             | 전체 가능 |  본인 것만 가능 |    불가 | `ParticipantGroupPolicy::Scope` 구현 |
| 상세 조회             | 전체 가능 |  본인 것만 가능 |    불가 | `show` 구현             |
| 생성                |    가능 |        가능 |    불가 | `new/create` 구현, 현재 로그인 사용자 소유로 생성 |
| 수정                |    가능 | 본인 그룹에 가능 |    불가 | `edit/update` 구현, draft/in_progress/closed 참조 여부와 무관하게 원본 그룹 이름 수정 가능 |
| 삭제                |    가능 | 본인 그룹에 가능 |    불가 | `destroy` 구현, draft 선거가 현재 참조 중이면 그룹 자체 삭제 차단 |
| 학생 1명 추가          |    가능 | 본인 그룹에 가능 |    불가 | `ParticipantSlot` 단건 `new/create` 구현 |
| 학생 명단 bulk import |    가능 | 본인 그룹에 가능 |    불가 | 학생 수 기반 bulk 추가 구현, HWP/Excel 붙여넣기는 후속 |
| 학생 이름 수정          |    가능 | 본인 그룹에 가능 |    불가 | `ParticipantSlot` `edit/update` 구현, draft/in_progress/closed 참조 여부와 무관하게 원본 수정 가능 |
| 학생 삭제              |    가능 | 본인 그룹에 가능 |    불가 | `ParticipantSlot` `destroy` 구현, 삭제 후 번호 재정렬 없음 |
| 학생 번호 재정렬         |  미구현 |        미구현 |    불가 | 투표 진행 순서와 연결되므로 별도 정책 필요 |

---

ParticipantGroup은 현재 원본 명단으로 취급한다.
Poll 생성 시 teacher는 본인 ParticipantGroup 중 하나를 선택하는 흐름을 우선한다.
선거 시작 시점에는 원본 명단을 투표 참여자 snapshot으로 복사한다.
snapshot 모델과 생성 로직은 `PollParticipant`와 `Polls::Start`로 구현되어 있다.
draft 선거는 아직 snapshot이 없고 원본 ParticipantGroup을 직접 참조한다.
draft 상태에서도 원본 참여자 그룹 이름 수정과 학생 추가/수정/삭제는 가능하다.
투표 시작 뒤에는 `PollParticipant` snapshot이 투표 진행 기준이므로 원본 참여자 그룹과 학생 명단 수정/삭제는 이미 시작된 선거에 영향을 주지 않는다.
단, draft 선거가 현재 참조 중인 원본 참여자 그룹 자체 삭제는 준비 중인 Poll이 필수 명단 설정을 잃지 않게 차단한다.

---

### Poll

선거는 참여자 그룹을 대상으로 만들어지는 투표 단위다.

| 리소스/액션 | admin |  teacher | guest | 비고                         |
| ------ | ----: | -------: | ----: | -------------------------- |
| 목록 조회  | 전체 가능 | 본인 것만 가능 |    불가 | `PollPolicy::Scope` 구현 |
| 상세 조회  | 전체 가능 | 본인 것만 가능 |    불가 | `show` 구현                  |
| 생성     |    가능 |       가능 |    불가 | `new/create` 구현, teacher는 본인 participant group 기준 |
| 수정     |    가능 | 본인 것만 가능 |    불가 | 후보자 관리는 `PollPolicy#update?` 기준 |
| 삭제     |    가능 | 본인 것만 가능 |    불가 | `draft`, `stopped`, 보관 전 `closed`에서 가능 |
| 시작     | 전체 가능 | 본인 것만 가능 |    불가 | `start` 구현, 후보자 2명 이상 일반 경쟁 투표만 지원 |
| 중단     |    가능 | 본인 것만 가능 |    불가 | `in_progress`에서만 가능, 재시작 없음 |
| 종료     |    가능 | 본인 것만 가능 |    불가 | `in_progress`에서 완료/미참여 상태 검증 |
| 보관     |    가능 | 본인 것만 가능 |    불가 | `closed`에서만 가능, `archived_at` 기록 |
| 결과 확인  | 전체 가능 | 본인 것만 가능 |    불가 | 종료 후 가능                    |

Poll 시작 권한 초안:

* `admin`은 전체 선거를 시작할 수 있다.
* `teacher`는 본인이 만든 선거만 시작할 수 있다.
* `guest`는 선거를 시작할 수 없다.

현재 `PollPolicy#start?`와 `PollsController#start`가 구현되어 있다.
권한 확인 뒤 `Polls::Start`가 `draft` 상태, 후보자 수, 명단 존재, snapshot 중복 생성 여부를 검증한다.
후보자 1명 선거는 무투표 당선/찬반 투표 정책 결정 후 지원 예정 안내로 시작을 막는다.

### Admin Election

Admin `Election`은 여러 학급 `ElectionSession`을 묶는 관리자 운영 단위다.
화면 표시에서 `school_council` kind는 `전교임원선거`로 표시한다.
`custom`, `class_officer` 등 다른 `Election` kind는 강제 번역하지 않고 원래 kind 값을 fallback으로 표시한다.
`admin/elections`의 큰 제목 `선거 관리`는 관리 영역 이름으로 유지한다.

| 리소스/액션 | admin | teacher | guest | 비고 |
| --- | ---: | ---: | ---: | --- |
| 상세 조회 | 가능 | 불가 | 불가 | `admin/elections#show` |
| 결과 집계 조회 | closed 선거에서 가능 | 불가 | 불가 | `/admin/elections/:id/results`, closed session만 표시/집계 |
| 선거 생성 | 가능 | 불가 | 불가 | 학교와 선거명을 기준으로 생성 |
| 선거 수정 | draft에서 가능 | 불가 | 불가 | 시작 뒤 구성 변경 차단 |
| 선거 시작 | 가능 | 불가 | 불가 | draft, 세션/항목/후보 구성 조건 충족 시 parent `Election`만 `in_progress`로 전환 |
| 선거 중단 | in_progress에서 가능 | 불가 | 불가 | 운영 사고 시 parent와 미종료 학급 세션 중단 |
| 선거 종료 | 모든 현재 세션 종료 후 가능 | 불가 | 불가 | parent 자동 종료 없이 admin이 명시적으로 확정 |
| 특정 학급 재투표 | in_progress parent에서 가능 | 불가 | 불가 | 기존 세션은 stopped 이력, replacement는 draft |
| 선거 삭제 | draft에서 가능 | 불가 | 불가 | in_progress/closed/stopped는 운영 이력 보존을 위해 삭제 불가 |
| 비상 초기화 | 가능 | 불가 | 불가 | admin 전용 비상 복구 기능 |
| 학급 세션 배정 | draft에서 가능 | 불가 | 불가 | 시작 후 생성 차단 |
| 학급 세션 삭제 | 제한적으로 가능 | 불가 | 불가 | parent draft, 대상 session draft, 같은 election 안에 non-draft session 없음 |
| 후보자/사진 등록·수정·삭제 | draft에서 가능 | 불가 | 불가 | 시작 후 변경 차단 |
| 공식 투표자 명단 관리 | 가능 | 그룹 metadata 변경 불가 | 불가 | teacher는 담당 명단의 학생 row 관리만 가능 |

teacher는 본인에게 배정된 `ElectionSession`만 운영할 수 있다.
Parent `Election`이 `in_progress`이면 draft/in_progress 학급 세션을 운영할 수 있다.
draft parent `Election`의 세션은 교사 목록에 보이지 않고, 직접 접근도 운영 화면으로 들어가지 못한다.
closed parent `Election`의 세션은 진행 목록이 아니라 종료/보관 흐름에서 다룬다.
stopped 학급 세션은 `/polls`에 `중단됨`으로 표시하고 상세를 읽기 전용으로 제공한다.
담당 teacher는 stopped 상세에서 해당 세션을 본인 `/polls` 목록에서 숨길 수 있다.
이 동작은 `hidden_from_teacher_at`만 기록하며 admin 이력과 직접 상세 접근은 유지한다.

`ParticipantGroup.purpose = school_election`인 명단은 전교임원선거 투표자 명단으로
구분한다. admin은 `/admin/election_rosters`에서 학급 정보와 학생 명단을 관리한다.
담당 teacher는 그룹 자체를 생성·수정·삭제할 수 없지만, 본인 학급의
`ParticipantSlot` 번호와 이름을 추가·수정·삭제할 수 있다.

Admin 전체 집계는 `closed` `ElectionSession`만 합산한다.
결과 페이지의 학급별 목록도 `closed` 세션만 표시한다.
draft/in_progress/stopped 세션은 결과 합산과 결과 검산 목록에서 제외한다.
stopped 세션은 Admin 선거 상세의 중단 이력에서 확인한다.

Admin은 draft 전교임원선거만 삭제할 수 있다. `in_progress`, `closed`, `stopped`
선거는 삭제할 수 없으며, stopped 선거도 운영 이력으로 보존한다. 특수 상황에서
삭제가 필요하면 admin이 비상 초기화로 draft로 되돌린 뒤 삭제한다.

비상 초기화는 admin 전용 권한이다. 향후 `school_election_manager`를 도입하더라도
선거 삭제와 비상 초기화 권한은 부여하지 않는다. 해당 미래 권한에는 선거 중단과
학급 재투표만 부여할 예정이며 admin 역할을 대체하지 않는다.

관리자 선거 UI 정책:

* `/admin/elections` 목록 카드는 선거 이름, `전교임원선거` 배지, 상태 배지, 관리/시작 준비 버튼 중심으로 간결하게 표시한다.
* 목록 카드에서는 후보 구성, 학급 수, 완료 수 요약을 표시하지 않는다.
* `/admin/elections/:id` 상단 요약 카드에서는 선거 이름 옆에 `전교임원선거` 배지와 상태 배지를 함께 표시한다.
* 투표/선거 이벤트 시간은 기존 KST 표시 helper 정책에 따라 KST 기준으로 표시한다.

Poll 화면 표시 용어:

* `Poll` kind `election`: `학급선거`
* `Poll` kind `discussion`: `학급토의`
* `Poll` kind `debate`: `학급토론`

Poll 상태별 현재 액션 정책:

| 상태 | 조회 | 투표 화면 | 중단 | 삭제 | 보관 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
| 준비 | 가능 | 불가 | 불가 | 가능 | 불가 | 후보자와 기본 설정을 준비 |
| 진행 | 가능 | 가능 | 가능 | 불가 | 불가 | 진행 중 투표를 실수로 삭제하지 않음 |
| 중단 | 가능 | 불가 | 불가 | 가능 | 불가 | 결과 확정 상태가 아니며 재시작하지 않음 |
| 종료 | 가능 | 불가 | 불가 | 가능 | 가능 | 보관 전에는 삭제 또는 보관 가능 |
| 보관된 종료 | 가능 | 불가 | 불가 | 불가 | 불가 | 기본 목록에서 숨기고 보관 목록에서 확인 |

보관은 `Poll` status가 아니라 `archived_at`으로 관리한다.
`closed` 상태에서 `archived_at`이 있으면 보관된 종료 투표다.
보관된 투표도 상세 화면 조회는 가능하지만 삭제할 수 없다.
보관 전 종료 투표는 삭제 또는 보관할 수 있다.
보관 해제와 종료 후 30일 자동 보관은 아직 구현하지 않았다.

---

### PollOption

후보자는 특정 선거에 속한다.

| 리소스/액션     |  admin |      teacher | guest | 비고            |
| ---------- | -----: | -----------: | ----: | ------------- |
| 목록 조회      |  전체 가능 | 본인 선거 후보만 가능 |    불가 | 선거 상세 화면에 표시 |
| 생성         |     가능 |    본인 선거에 가능 |    불가 | draft 선거에서 가능 |
| 수정         |     가능 |    본인 선거에 가능 |    불가 | draft 선거에서 가능 |
| 삭제         |     가능 |    본인 선거에 가능 |    불가 | draft 선거에서 가능 |
| 투표 시작 후 수정 | 원칙적 제한 |           제한 |    불가 | 예외 필요 시 감사 로그 |

현재 구현은 별도 `PollOptionPolicy`를 두지 않고 후보자 관리를 선거 수정 권한으로 보아 `PollPolicy#update?`를 사용한다.
후보자는 nested route로만 관리하며, 공개 후보자 index/show는 없다.
선거 시작 뒤에는 후보자 추가/수정/삭제를 금지하는 방향이다.
이 제한은 `draft` 상태 기준 guard로 구현되어 있으며, `in_progress` 이후 후보자 추가/수정/삭제 요청은 선거 상세로 redirect된다.

선거 시작 뒤 참여자 명단 제한 방향:

* 원본 `ParticipantGroup` 변경은 이미 시작된 선거의 snapshot 명단에 영향을 주지 않는다.
* 진행 중/종료된 선거가 있어도 원본 그룹 이름 수정, 학생 추가/수정/삭제, 원본 명단 삭제는 가능하다.
* 선거에 연결된 snapshot 명단은 수정하지 않는다.
* draft 선거가 현재 참조 중인 원본 명단 자체 삭제는 차단한다.

---

### PollProgress

초기 학급 MVP에서는 하나의 선거가 하나의 투표 진행 정보를 가진다.
전교 선거 확장 시 하나의 선거가 여러 학급 투표 진행 정보를 가질 수 있다.
`PollProgress`은 현재 투표 위치를 복구하기 위한 진행 상태 컨테이너이며, 후보 선택 결과나 득표수를 저장하지 않는다.
teacher는 본인 선거의 `PollProgress`만 진행할 수 있고, admin은 전체 `PollProgress`에 접근할 수 있다.

| 리소스/액션      | admin |    teacher | guest | 비고             |
| ----------- | ----: | ---------: | ----: | -------------- |
| 진행 화면 조회    | 전체 가능 | 본인 투표 진행 정보만 가능 |    불가 |                |
| 투표 시작       |    가능 | 본인 투표 진행 정보만 가능 |    불가 |                |
| 다음 학생 투표 시작 |    가능 | 본인 투표 진행 정보만 가능 |    불가 | 상태 전이 guard 필요 |
| 미참여 처리      |    가능 | 본인 투표 진행 정보만 가능 |    불가 | 학급 종료 전 범위 결정  |
| 투표 종료       |    가능 | 본인 투표 진행 정보만 가능 |    불가 | 결과 확정 전 상태 검증  |
| 복구 화면 접근    |    가능 | 본인 투표 진행 정보만 가능 |    불가 | DB 상태 기준       |

---

### VoteSession / Vote Submission

학생은 로그인하지 않지만, 투표 제출은 서버가 열어둔 vote session에 대해서만 가능해야 한다.

| 리소스/액션          | admin |    teacher | student/guest | 비고                       |
| --------------- | ----: | ---------: | ------------: | ------------------------ |
| vote session 열기 |    가능 | 본인 투표 진행 정보만 가능 |            불가 | 교사 진행 화면에서 수행            |
| 투표 화면 보기        |    가능 | 본인 투표 진행 정보만 가능 |        제한적 가능 | open session이 있을 때만      |
| 투표 제출           |    가능 | 본인 투표 진행 정보만 가능 |        제한적 가능 | open session token/상태 필요 |
| 중복 제출           |    불가 |         불가 |            불가 | 서버/DB에서 차단               |

학생은 인증 사용자가 아니므로, 실제 구현에서는 학생 투표 화면 접근 방식을 별도로 신중히 정해야 한다.

가능한 방식:

* 같은 교사 세션 안에서 학생 투표 화면을 제공
* 짧게 유효한 signed token 사용
* 투표 진행 정보의 open vote session이 있을 때만 booth 화면 활성화

초기 구현에서는 학생 개인 인증을 도입하지 않는다.

---

### Result / Tally

결과는 투표 종료 후 확인 가능하다.

| 리소스/액션    |  admin |   teacher | guest | 비고         |
| --------- | -----: | --------: | ----: | ---------- |
| 결과 조회     |  전체 가능 | 본인 선거만 가능 |    불가 | 종료 후       |
| 결과 수정     | 원칙적 불가 |        불가 |    불가 | 예외 시 감사 로그 |
| 결과 export |     가능 |  본인 선거 가능 |    불가 | 추후 기능      |

---

## 권한 경계 원칙

### 소유권 기준

초기 MVP에서 teacher 권한의 기본 경계는 소유권이다.

* teacher가 만든 참여자 그룹
* teacher가 만든 선거
* teacher가 관리하는 투표 진행 정보
* teacher가 진행한 결과

teacher는 이 범위를 벗어난 데이터에 접근하지 못한다.

---

### admin 예외

admin은 전체 데이터를 관리할 수 있다.

다만 admin 권한이 있다고 해서 모든 위험한 작업을 아무 제한 없이 처리하지 않는다.
선거 시작 후, 투표 진행 중, 투표 종료 후 데이터 수정은 별도 확인과 로그가 필요하다.
현재 Admin `Election` 흐름에서는 시작 후 학급 세션과 후보자 구성을 서버측에서 변경할 수 없게 막는다.

---

### 학생 비계정 원칙

초기 MVP에서 학생은 계정이 아니다.

따라서 다음 정책은 도입하지 않는다.

* 학생 로그인
* 학생별 비밀번호
* 학생 PIN
* 학생별 세션
* 학생별 권한 scope

학생은 참여자 그룹의 row 또는 participant slot으로 취급한다.

---

## 권한 실패 응답 원칙

초기 원칙:

* HTML 요청

  * redirect + alert

* Turbo 요청

  * flash 영역 갱신 또는 적절한 status 응답

* JSON 요청

  * `403 Forbidden`
  * `{ ok: false, error: "not_authorized" }`

실제 응답 형식은 구현 시 프로젝트 전체 스타일에 맞춰 조정한다.

---

## 구현 시 policy 후보

초기 구현에서 예상되는 policy:

* `UserPolicy`
* `ParticipantGroupPolicy`
* `PollPolicy`
* `PollOptionPolicy`
* `PollProgressPolicy`
* `VoteSessionPolicy`
* `ResultPolicy`

단, 실제 policy 수는 구현 복잡도에 따라 줄일 수 있다.
초기에는 과도하게 policy를 분리하기보다, 실제 controller/resource 경계를 기준으로 단순하게 시작한다.

---

## 테스트 우선순위

권한 테스트는 request spec과 policy spec을 조합한다.

우선 고정할 항목:

* teacher는 본인 participant group만 볼 수 있다.
* teacher는 다른 teacher의 participant group을 볼 수 없다.
* teacher는 본인 election만 만들고 관리할 수 있다.
* teacher는 다른 teacher의 election을 수정할 수 없다.
* teacher는 본인 polling station만 진행할 수 있다.
* teacher는 다른 teacher의 결과를 볼 수 없다.
* admin은 전체 participant group/poll/result에 접근할 수 있다.
* guest는 주요 리소스에 접근할 수 없다.
* 학생 계정 없이도 vote session이 열려 있을 때만 학생 투표 화면이 동작한다.
* open vote session이 없으면 학생 투표 제출이 거부된다.

---

## 전교임원선거의 미구현 역할

현재 전교임원선거는 `admin`과 `teacher` 역할만 사용한다.
구체적인 운영 권한은 `docs/specs/school_council_election.md`를 따른다.

선거관리위원의 개표 승인이나 결과 확인 입회가 필요해지면
`election_officer` 같은 별도 역할을 검토할 수 있다. 현재 배포 범위에는 포함하지 않는다.

---

## 문서 유지 원칙

* 권한 문서는 policy, controller, service guard 순으로 확인한 뒤 갱신한다.
* “보이는 버튼”이 아니라 서버측 `authorize`, `policy_scope`, 소유권 조건을 기준으로 쓴다.
* 새 액션이 추가되면 해당 endpoint의 권한 기준을 함께 문서화한다.
* 문서와 코드가 충돌하면 문서를 먼저 의심하고, 코드 근거가 확인된 후 갱신한다.
* 구현 전 문서의 매트릭스는 “계획”으로 취급하고, 구현 후에는 실제 동작 기준으로 갱신한다.
