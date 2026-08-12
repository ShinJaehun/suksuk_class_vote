# Roles and Permissions

## 목적

이 문서는 `쑥쑥교실투표(suksuk_class_vote)`의 현재 역할과 서버측 권한 경계를 정리한다.
실제 controller와 Pundit policy를 기준으로 유지하며, 화면에 버튼이 보이는지만으로 권한을 판단하지 않는다.

---

## 기본 원칙

* 서버측 권한 판단은 Pundit policy와 `policy_scope` 중심으로 유지한다.
* controller는 가능한 한 `authorize`, `policy_scope`를 호출하는 자리로 남긴다.
* 단건 권한 판단은 policy에 두고 목록 조회 범위는 policy scope에 둔다.
* view는 controller와 policy에서 정리된 결과를 소비하며 복잡한 권한 조건을 늘리지 않는다.
* 관리 UI에는 controller/policy의 별도 서버측 guard를 둔다.
* 위험한 운영 기능은 상태 조건, 확인 절차와 감사 기록을 함께 적용한다.

---

## 역할 구조

### User의 global 역할

`User.role`은 다음 두 값만 사용한다.

* `admin`: 서비스 전체 최고 관리자
* `teacher`: 교사 로그인 사용자

### 학교 내부 역할

teacher는 하나의 `SchoolMembership`을 통해 학교에 속할 수 있다.

* `member`: 일반 학교 구성원
* `manager`: 해당 학교의 대표 교사

`manager`는 별도 global User 역할이 아니다. 한 학교에는 manager membership을 하나만 둘 수 있으며,
manager 지정과 해제는 global admin만 수행한다.

`User`는 `login_id` 기반으로 로그인하는 실제 사람의 계정이며 `active`, `password_change_required` 상태를 가진다. 과거 운영 기록 때문에 계정을 단순 재사용하거나 교체하지 않는다. 한 User는 한 학교 membership만 가지며, membership의 grade는 1~6 또는 미배정(nil)이다. `Classroom.teacher`는 현재 담임 배정으로 membership의 grade와 별개이며, 활성 teacher 한 명은 활성 Classroom 하나만 담당한다.

### Student와 guest

`Student`는 Classroom의 학년도별 학생 명단 모델이며 로그인 계정이 아니다. 학생 계정, PIN,
개인 인증 scope를 두지 않으며 PollSession 또는 Classroom 기반 ElectionSession 시작 시 voter snapshot의
원본이 될 수 있다. guest는 로그인·비밀번호 재설정 외 주요 관리·투표 기능에 접근하지 못한다.

---

## 역할별 현재 범위

### global admin

admin은 다음 범위의 최고 관리 권한을 가진다.

* 모든 School 조회·생성·수정
* 모든 Classroom 조회·생성·수정과 Student 관리
* `/teachers`의 모든 학교 교사 계정 목록·단일/bulk 생성과 학교·학년 단위 일괄 편집·담임 배정, 선택 학년 배정·활성화·비활성화와 삭제 조건을 충족한 계정의 삭제 시도
* SchoolMembership 목록·추가·제거와 manager 지정·해제
* 일반 Poll과 PollSession의 조회·운영·상태 lifecycle
* school-managed Poll의 정의·전체 lifecycle·학급 Session 재투표와 reset
* legacy Election의 생성·구성·세션 배정·비상 초기화 등 관리
* 모든 ElectionSession 조회·운영과 admin 전용 학급 재투표

교사 학교 이전은 현재 구현된 권한으로 간주하지 않는다. admin은 관리 대상 교사, manager는 자기 학교 교사의 임시 비밀번호를 개별 재발급할 수 있다. 또한 admin 권한이라도 Poll/Election
상태와 보존 조건을 무시하지 않으며 각 policy와 service guard를 통과해야 한다.

### SchoolMembership manager

manager 권한은 membership이 속한 학교로 한정된다.

* 자기 School 목록·상세 조회
* 자기 학교 Classroom 목록·생성·수정과 Student 관리
* `/teachers`의 자기 학교 교사 목록·단일/bulk 생성과 자기 학교·학년 단위 일괄 편집·담임 배정
* 자기 학교 학년·미배정 교사의 선택 학년 배정·활성화·비활성화와 삭제 조건을 충족한 계정의 삭제 시도
* 자기 학교 membership 목록 조회와 소속 없는 teacher 추가
* 자기 자신이 아닌 일반 member의 membership 제거
* 자기 학교 school-managed Poll 목록·생성·조회·수정 가능한 정의 관리
* 상태 조건을 충족하는 school-managed Poll 시작·중단·종료·reset·삭제
* 자기 학교 전교투표 학급 Session의 시작과 replacement 재투표

manager는 다른 학교 자원에 접근하지 못한다. manager 지정·해제는 할 수 없고, 담당 Classroom이 남은
교사의 membership도 제거할 수 없다. legacy `Election` 관리 권한은 없으며 해당 기능은 admin-only다.
manager는 자기 profile과 비밀번호를 변경할 수 있지만 자기 계정을 비활성화하거나 삭제할 수 없다. 자기 학교 일반 선생님의 lifecycle 관리는 기존 범위에서 가능하며, 자기 lifecycle 제한은 UI뿐 아니라 `UserPolicy`의 record authorization으로 강제한다. global admin의 기존 선생님 관리 권한은 유지된다.

### 일반 teacher/member

일반 teacher의 신규 구조 권한은 담당 Classroom과 실제 운영 Session을 중심으로 한다.

일반 teacher는 다른 교사 목록이나 계정에 접근할 수 없지만 자신의 개인 계정 설정에서 이름·로그인 ID·이메일을 수정하고, 현재 비밀번호 확인 후 자신의 비밀번호를 변경할 수 있다. admin/manager는 다른 teacher의 영구 비밀번호를 직접 지정하지 않고 임시 비밀번호만 재발급한다. 학년·담임·활성 상태·학교 role은 개인 설정에서 변경할 수 없다.

* 자기 학교에서 자신이 담임인 Classroom 조회·수정
* 담당 Classroom의 Student 단일·bulk 등록, 수정, inactive와 복구
* 자신의 일반 학급 Poll 생성·조회
* 자신이 operator이거나 담당 Classroom에 연결된 일반 PollSession의 정의·상태 lifecycle 관리
* 자신에게 배정된 school-managed PollSession 시작
* 자신이 operator인 PollSession의 ballot·참여자 진행과 종료 운영
* 자신에게 배정된 legacy ElectionSession 운영과 stopped 상세 숨김

다른 교사의 Classroom·Student, 다른 학교 자원, school-managed Poll 전체 lifecycle에는 접근하지 못한다.
전교투표 학급 Session의 replacement 재투표도 manager 또는 admin 권한이며 일반 teacher 권한이 아니다.

---

## 주요 자원별 현재 권한

### School

* admin: 전체 scope, 생성·수정·상세 조회
* manager: 자기 학교만 목록·상세 조회
* 일반 member: School 관리 화면 접근 불가

### Classroom / Student

`ClassroomPolicy::Scope`는 admin에게 전체 Classroom, manager에게 자기 학교 Classroom, 일반 member에게
자기 학교에서 본인이 담임인 Classroom만 반환한다.

Classroom 생성은 admin과 manager가 할 수 있다. 수정과 Student 관리는 admin, 같은 학교 manager,
해당 Classroom 담임에게 허용된다. `ClassroomStudentsController`도 scope로 Classroom을 조회한 뒤
`manage_students?`를 확인한다.

### SchoolMembership

admin과 같은 학교 manager는 membership 목록을 보고 소속 없는 teacher를 member로 추가할 수 있다.
manager 승격·해제는 admin-only다. admin은 membership을 제거할 수 있고, manager는 자기 학교의 일반
member만 제거할 수 있다. controller는 담당 Classroom이 남아 있으면 제거를 추가로 차단한다.
`SchoolMembership.grade`는 학교 내 학년 소속을 나타내며 nullable이다. `Classroom.grade`는 교실의
학년이고 `Classroom.teacher`는 실제 담임 배정이므로, 학년 소속과 담당 반은 독립적으로 관리한다.

선생님 비활성화는 현재 담당 Classroom을 해제하고 grade는 보존한다. 재활성화해도 Classroom을 자동 복원하지 않는다. 삭제는 inactive, grade nil, Classroom 없음 조건에서만 시도하며 기존 기록의 FK/restrict가 있으면 실패한다. `login_id` uniqueness는 비활성화·삭제 정책과 별도로 유지한다.

### 일반 Poll / PollSession

일반 Poll은 `school_managed: false`인 학급 Poll이다.

* Poll 생성은 로그인한 admin 또는 teacher에게 허용된다.
* `/polls` scope는 현재 사용자가 소유한 Poll을 반환하며 admin은 단건 policy로 다른 Poll에도 접근할 수 있다.
* legacy 직접 실행 Poll action은 admin 또는 Poll owner에게 허용된다.
* Classroom 기반 Poll lifecycle은 연결된 PollSession policy를 사용한다.
* 일반 PollSession의 시작·중단·replacement 재투표·보관·삭제는 admin 또는 실제 operator/담임의
  lifecycle 권한과 상태 조건을 따른다.
* ballot 진행은 admin 또는 `PollSession.operator`만 수행한다.

### school-managed Poll

school-managed Poll 전체 lifecycle과 학급 Session 운영은 분리한다.

* parent Poll 목록·생성·조회와 상태별 시작·중단·종료·reset은 global admin 또는 해당 학교 manager에게 허용된다.
* 정의 수정은 test run이 아닌 draft 등 각 action의 추가 상태 조건을 따른다.
* 삭제 가능 범위는 실제 투표/test run, 상태와 보관 여부에 따라 제한되며 강제 확인은 admin-only다.
* 학급 PollSession 시작은 admin, 해당 학교 manager 또는 해당 Classroom 담임에게 허용된다.
* 학급 PollSession의 실제 ballot 운영은 admin 또는 배정된 operator에게 허용된다.
* 학급 Session replacement 재투표는 admin 또는 해당 학교 manager에게 허용된다.

일반 teacher가 학급 Session을 운영할 수 있다는 사실은 parent 전교투표 전체 lifecycle 권한을 뜻하지 않는다.

### legacy Election / ElectionSession

`Election` / `ElectionSession` runtime은 historical Poll 전환 전까지 호환 목적으로 남아 있다.

* `ElectionPolicy`의 목록·조회·생성·수정·삭제·세션 관리·비상 초기화는 admin-only다.
* SchoolMembership manager에게 legacy Election 관리 권한은 없다.
* admin은 모든 ElectionSession을 운영하고 in_progress parent의 학급 재투표를 실행할 수 있다.
* 배정된 teacher는 parent가 draft가 아닐 때 자기 ElectionSession을 조회·시작·ballot 운영·종료할 수 있다.
* 배정된 teacher는 자기 stopped Session을 본인 목록에서 숨길 수 있다.

---

## legacy ParticipantGroup / ParticipantSlot

`ParticipantGroup`과 `ParticipantSlot`은 legacy Poll/Election 호환을 위해 아직 남아 있다. 신규
Classroom/PollSession 구조의 기본 명단 관리 방식은 아니며, 신규 투표는 Classroom의 active Student를
snapshot 원본으로 사용한다.

legacy 관리 화면에서는 기존 policy에 따라 admin이 전체 group을, teacher가 본인 group을 관리한다.
legacy Poll/Election 기록과 직접 연결된 세부 권한은 해당 runtime policy를 따른다. 이 구조는 운영 데이터
조사·backfill과 legacy runtime 제거가 끝나기 전까지 임의로 삭제하지 않는다.

---

## 기본 진입과 내비게이션

* admin 로그인 및 권한 실패 기본 경로: `/teachers`
* teacher 로그인 및 권한 실패 기본 경로: `/polls`
* 로그인 사용자는 내 투표와 legacy 투표자 목록, 권한 범위의 Classroom 화면에 접근한다.
* admin과 manager는 학교·전교투표 메뉴를 사용한다.
* admin은 global 교사 관리와 legacy 전교임원선거 메뉴를 사용한다.
* manager는 `/teachers`의 자기 학교 교사 관리와 별도 membership 관리 기능을 사용한다.

내비게이션 노출은 편의를 위한 것이며 실제 접근 권한은 controller와 policy가 결정한다.

---

## 권한 실패 응답 원칙

Pundit 권한 실패는 현재 사용자 역할의 기본 경로로 redirect하고 접근 권한 안내를 표시한다.
Turbo/HTML 응답도 view 조건만으로 권한을 대체하지 않으며 각 controller action에서 서버측 검증을 유지한다.

---

## 문서 유지 원칙

* 권한 문서는 policy, controller, service guard 순으로 확인한 뒤 갱신한다.
* “보이는 버튼”이 아니라 서버측 `authorize`, `policy_scope`, 소유권 조건을 기준으로 쓴다.
* 새 action이 추가되면 해당 endpoint의 권한 기준을 함께 문서화한다.
* 문서와 코드가 충돌하면 실제 policy와 controller guard를 확인한 뒤 문서를 갱신한다.
