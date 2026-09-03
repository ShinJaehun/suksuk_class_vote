# 관리자 학급투표 운영 현황

## 목적

global admin이 여러 학교에서 교사가 준비·실행한 일반 학급투표의 상태와 보존된 이력을
한곳에서 조사할 수 있는 읽기 전용 monitoring 화면을 제공한다. 기존 교사용 `/polls`와
운영용 `PollSession#show`는 변경하거나 재사용하지 않는다.

## 접근 권한

- global admin만 목록·상세에 접근할 수 있다.
- school manager와 일반 teacher의 navigation에는 진입점을 표시하지 않으며 직접 URL 접근도 거부한다.
- 비로그인 사용자는 기존 인증 흐름을 따른다.
- controller와 policy에서 서버 권한을 검증한다. navigation 조건은 권한 검증을 대신하지 않는다.
- 기존 admin의 Poll/PollSession 운영 권한은 바꾸지 않지만 monitoring 영역에는 mutation route,
  form 또는 action을 제공하지 않는다.

## Navigation

global admin의 상단 navigation은 다음 순서로 표시한다.

```text
전교투표  학급투표 | 학교  교실  선생님
```

- label은 `학급투표`다.
- `전교투표` 바로 뒤, 관리 영역 구분선 앞에 둔다.
- 진입 페이지 제목은 `학급투표 운영 현황`으로 한다.
- 기존 `전교투표`의 표시와 접근 정책은 변경하지 않는다.

## Default landing

`default_landing_path_for`를 사용하는 로그인 직후, `/` 접근과 권한 오류 후 fallback redirect에는
다음 기본 진입점을 적용한다.

- global admin: `/school_polls`
- school manager: `/polls`
- 일반 teacher: `/polls`

기존 비밀번호 변경 강제 흐름이 우선하며 `password_change_required?` 사용자는 지금처럼 비밀번호 변경
화면으로 먼저 이동한다.

## 조회 범위

- `Poll.school_managed = false`인 모든 PollSession을 조회한다.
- `draft`, `in_progress`, `stopped`, `closed`를 모두 포함한다.
- Poll 또는 PollSession이 보관되어도 이력에서 제외하지 않고 `보관됨`을 보조 표시한다.
- `school_managed = true`인 전교투표와 그 test run은 포함하지 않는다.
- 목록과 상세는 저장된 운영 metadata를 조회하며 교사용 준비 form이나 실제 운영 화면으로 연결하지 않는다.

## Filters

모든 필터는 GET query parameter로 유지하며 새로고침과 뒤로가기 후에도 같은 의미를 가진다.

- 학교: `전체`와 조회 가능한 전체 학교
- 학년: `전체`와 1~6학년
- 상태: `전체 / 준비 / 진행 / 중단 / 종료`
- 투표 이름: Poll.title 부분 일치 검색

select의 기본값은 모두 `전체`이고 투표 이름의 기본값은 빈 문자열이다. 각 조건은 함께 조합한다.

- 학교가 `전체`이면 학년은 `전체` 또는 1~6학년을 선택할 수 있고, 학년 선택 시 모든 학교의
  해당 학년 PollSession을 조회한다.
- 특정 학교와 학년을 함께 선택하면 두 조건을 모두 만족하는 PollSession만 조회한다.
- 투표 이름 검색은 앞뒤 whitespace를 제거한 Poll.title 부분 일치이며 빈 문자열은 조건을 적용하지
  않는다. 한글 제목 중심의 현재 용도에서 대소문자를 불필요하게 구분하지 않는다.
- 투표 이름은 학교·학년·상태와 조합되며 admin monitoring의 `school_managed: false` 범위를 넓히지 않는다.
- 잘못된 ID, 학년, 상태는 허용 목록 밖 값으로 query하지 않는다. 독립적으로 잘못된 값은 `전체`로
  처리하되, 다른 유효한 조건을 제거하거나 그 범위 밖으로 결과를 넓히지 않는다.

필터는 `school_polls/index`와 `classrooms/index`의 관리 화면을 우선 참고하여 `rounded-md`,
`border border-stone-200`, `bg-white`, `p-4`와 같은 visual language, spacing, label/select typography를
맞춘다. 4개 필터에 필요한 반응형 배치는 유지하되 별도 dashboard panel처럼 과도하게 강조하지 않는다.
학교·학년·상태 select는 기존 GET/autosubmit 패턴을 재사용한다. 투표 이름 text input은 입력할 때마다
요청하지 않고 기존 검색 submit 패턴을 재사용하거나 옆에 단순한 `검색` submit button을 둔다. 모든
조건은 같은 GET form으로 전송한다. 초기화가 필요하면 query parameter를 모두 제거하며 새로운
JavaScript, Stimulus controller 또는 filter component/framework는 도입하지 않는다.

## Ordering

별도 정렬 UI 없이 대표 활동 시각 내림차순, 동일 시각에는 PollSession ID 내림차순으로 정렬한다.

- `closed`: `closed_at`
- `stopped`: `stopped_at`
- `in_progress`: `started_at`
- `draft`: `PollSession.updated_at`, `Poll.updated_at`, 현재 존재하는 PollContest와 PollOption의
  `updated_at` 중 가장 최근 시각

단순 `created_at DESC`는 사용하지 않는다. 현재 정의 수정은 `PollSession.updated_at`을 자동으로
갱신하지 않으므로 draft에 그 값만 사용해서도 안 된다. 이 값은 현재 저장된 데이터로 계산 가능한
대표 활동 시각이며 모든 definition mutation의 완전한 audit timestamp가 아니다.

현재 ClassroomPollContest/ClassroomPollOption의 destroy는 부모를 touch하지 않고 삭제된 row의
timestamp도 query할 수 없으므로 항목이나 선택지의 삭제만 발생한 경우 대표 활동 시각 갱신을
보장하지 않는다. 이번 MVP에서는 이를 보완하는 controller·association touch, callback, audit/event,
schema를 추가하지 않는다.

## List fields

목록은 운영 기록을 빠르게 식별할 수 있도록 다음 정보만 표시한다.

- 상태 badge: 준비, 진행, 중단, 종료
- 보관된 경우 `보관됨` 보조 표시
- 학교 / 학년·학급
- 운영 선생님
- 투표 제목 / 종류: 선거, 설문조사, 토의, 토론
- 생성 시각: `Poll.created_at`
- admin 전용 상세 링크

대표 활동 시각은 목록과 상세에 표시하지 않고 계산과 최신 활동순 ordering의 내부 기준으로만
사용한다. 생성 시각은 PollSession의 대표 활동 시각이나 lifecycle 시각이 아니라 `Poll.created_at`을
표시한다. 참여 운영 집계는 목록에 표시하지 않고 admin 상세에서만 표시한다.

과거 실행 기록은 `classroom_name_snapshot`, `operator_name_snapshot`을 우선 표시한다. snapshot이
없을 때만 현재 Classroom/User 값을 fallback으로 사용하며 현재 값으로 snapshot을 덮어쓰지 않는다.
현재 학교명 snapshot 필드는 없으므로 학교는 연결된 현재 School 이름을 표시한다. 필터의 학교·학년
범위는 현재 관계의 stable ID와 Classroom 속성을 사용하고, 목록의 학년·학급과 운영자 표시값은 역사
snapshot을 우선한다.

## Status-specific behavior

admin 상세에서 `in_progress`, `closed`, `stopped`는 현재 DB의 PollParticipant/PollParticipation
상태를 집계한다.

- 전체: PollParticipant snapshot 수
- 완료: `completed` 수
- 미참여: `absent` 수
- 기권: `abstained` 수
- 대기: PollParticipation이 없는 PollParticipant 수

집계는 항상 `전체 = 완료 + 미참여 + 기권 + 대기` 의미를 유지한다. `in_progress`와 `stopped`는
대기를 반드시 표시한다. `closed`도 현재 DB 값으로 대기를 계산하며 정상 종료라면 0이어야 하지만,
0이 아닌 역사 데이터도 숨기거나 다른 수에 합치지 않는다. 기권은 count만 표시하고 학생
신원과 연결하지 않는다. 학생별 상태를 별도로 표시하는 경우 기존 용어 정책에 따라 `completed`와
`abstained`는 모두 `투표 완료`, `absent`는 `미참여`, 기록 없음은 `대기`지만 이 monitoring MVP는
학생별 상태 목록을 제공하지 않는다.

partial ballot은 별도 목록 지표로 추가하지 않으며 participation이 없는 참가자는 `대기`에 포함한다.

`draft` 상세는 참가 snapshot과 실행 집계를 추정하지 않는다. 현재 active Student 수를 참가자 수처럼
표시하지 않고 실행 집계 전체를 `-` 또는 `아직 실행되지 않음`으로 표시한다.

## Read-only detail / revote relationship / results

admin 전용 상세는 다음 순서로 표시한다.

- 기본 정보: 투표 종류·상태, 현재 연결 학교, 학년/학급 snapshot, 운영 선생님 snapshot,
  생성·시작·종료·중단 시각, Poll 또는 PollSession 보관 여부
- 참여 운영 집계
- 재투표 관계(있는 경우)
- 투표 결과(`closed`인 경우)

상세 metadata에는 Poll ID와 PollSession ID, 대표 활동 시각을 표시하지 않는다. numeric ID는 기존
상세 route의 routing/database 식별자로만 유지한다.

`replacement_of` 또는 `replacement_session`이 있으면 `중단된 원투표`와 `재투표` label에 해당 Poll
제목을 함께 표시하고 양쪽 admin monitoring 상세로 이동할 수 있게 한다. 사용자-facing link text에는
PollSession ID를 표시하지 않는다. 관계가 없으면 표시하지 않으며 관계를 생성·변경하는 action은
제공하지 않는다.

`closed` 상세 하단에는 기존 PollOptionTally/PollContestTally 기반 count-only 결과를 직접 표시한다.
별도 결과 페이지로 이동하는 버튼이나 링크는 제공하지 않으며 사용자-facing 제목은 `투표 결과`로
한다. 일반 선택식은 contest title, 후보/선택지 번호와 이름, 득표 수, 기권 수를 표시한다.
referendum은 안건/단독 후보 이름과 찬성, 반대, 기권을 표시한다.

각 option tally가 정확히 하나이고 contest tally도 정확히 하나일 때만 결과를 정상 표시한다. tally가
불완전하면 일부 값을 섞어 표시하지 않고 `이 투표 세션의 집계 정보를 확인할 수 없습니다.`를
표시한다. `draft`, `in_progress`, `stopped` 상세에는 투표 결과 영역을 표시하지 않는다.

구현 구조는 admin 전용임이 드러나는 `/admin/classroom_poll_sessions` 목록과
`/admin/classroom_poll_sessions/:id` 상세 route, controller의 `index`와 `show`만 사용한다. 별도
`/admin/classroom_poll_sessions/:id/results` route/action/view는 두지 않는다. 교사용 `/polls`와
`PollSessionsController#show`에 monitoring 분기를 추가하지 않는다.

## Privacy

목록과 상세의 투표 결과에는 다음을 노출하지 않는다.

- 학생 개인별 선택 내용 또는 ballot
- 누가 어떤 후보·선택지를 골랐는지 알 수 있는 정보
- 기권한 학생의 신원
- 개인의 선택을 추론할 수 있는 추가 정보

결과는 개인과 연결되지 않은 count-only tally만 사용한다. 내부적으로 anonymous/count-only 결과라는
privacy 정책은 유지하되 사용자-facing UI에는 `익명 결과`, `익명 결과 보기` 표현을 사용하지 않는다.

## Performance constraints

- 학교, 학급, 운영자와 replacement 관계를 목록 row마다 별도 query하지 않는다.
- 현재 규모에 맞는 includes/preload와 group aggregate를 사용한다.
- 상세 참여 집계는 group aggregate를 사용하고 `SessionStatusCheck`로 추가 query를 반복하지 않는다.
- pagination gem이나 analytics infrastructure를 추가하지 않는다. pagination은 이번 MVP 필수가 아니다.

## Acceptance criteria

### A. admin navigation

global admin은 navigation에서 `전교투표` 바로 옆의 `학급투표`를 통해 monitoring 목록에 진입한다.
school manager와 일반 teacher에게 이 항목은 표시되지 않는다.

`default_landing_path_for`를 사용하는 흐름에서 global admin의 기본 진입점은 `/school_polls`이고,
school manager와 일반 teacher의 기본 진입점은 기존 `/polls`를 유지한다. 비밀번호 변경이 필요한
사용자에게는 기본 진입점보다 기존 비밀번호 변경 강제 흐름을 우선한다.

### B. 기본 전체 목록

filter 없이 진입하면 모든 학교의 `school_managed: false` PollSession을 보관 여부와 무관하게 조회한다.
네 lifecycle 상태를 모두 포함하고 전교투표는 제외하며 대표 활동 시각순으로 표시한다. 목록 열은
상태·보관 여부, 학교/학급, 운영 선생님, 제목/종류, Poll 생성 시각과 상세 링크로 제한한다.

### C. 계층 필터

전체, 학교, 학년, 학교+학년, 상태, 투표 이름 검색과 학교+학년+상태+투표 이름 검색 조합에서 해당
PollSession만 표시한다. 검색 문자열과 일치하지 않는 Poll은 표시하지 않으며 검색 결과도
`school_managed: false`, 보관 이력 포함, 전체 lifecycle 상태 포함이라는 monitoring 범위를 유지한다.

### D. draft

draft도 metadata와 함께 목록에 표시한다. 목록에는 실행 집계를 표시하지 않는다. 상세에서도 active
Student 수를 snapshot 수로 추정하지 않고 실행 집계를 `-` 등으로 표시하며, 준비·수정 form이나
mutation action을 제공하지 않는다.

### E. 진행/종료/중단

상세에서 각 상태의 lifecycle 시각과 PollParticipant/PollParticipation 기반
전체·완료·미참여·기권·대기를 현재 DB 상태대로 표시한다. 중단 상태의 대기를 숨기지 않으며 종료
상태의 대기가 0이 아니어도 그 값을 그대로 표시한다. 목록에는 시작·종료·중단 등 실행 lifecycle
시각과 참여 집계를 표시하지 않되 Poll 생성 시각은 표시한다.

### F. 재투표

중단된 원 session과 replacement session의 관계를 PollSession ID가 아닌 관계 label과 Poll 제목으로
양쪽 상세에서 확인하고 서로 이동할 수 있다. 관계를 생성하거나 변경할 수 없다.

### G. read-only 권한

global admin만 monitoring 목록·상세를 조회한다. monitoring 영역에는 edit, start, stop, close,
revote, archive, delete, ballot operation을 표시하거나 제공하지 않는다. manager와 teacher의 직접
URL 요청은 거부하고 guest는 기존 인증 흐름을 따른다.

### H. privacy

`closed` 상세 페이지 안에 `투표 결과`를 직접 표시하며 별도 결과 페이지나 결과 보기 버튼은 제공하지
않는다. `draft`, `in_progress`, `stopped` 상세에는 결과를 표시하지 않는다. 결과는 학생 개인의 선택,
ballot, 누가 무엇을 선택했는지 또는 기권 학생 신원을 노출하지 않고 count-only tally만 사용한다.
referendum은 안건/단독 후보 이름과 찬성, 반대, 기권으로 표시한다. 각 option tally와 contest tally가
정확히 하나일 때만 정상 표시하고 불완전하면 일부 결과를 섞지 않는 기존 tally completeness 의미를
그대로 유지한다.

### I. invalid filters

존재하지 않는 학교 ID와 허용되지 않은 학년·상태는 500을 일으키지 않는다. 다른 유효한 조건을
제거하거나 그 범위 밖 결과를 표시하지 않는다.

## Non-goals

- 학급투표 생성·수정 또는 admin 대리 운영
- start, stop, close, revote, archive, delete, ballot과 bulk operation
- school manager monitoring 또는 teacher별 filter
- 자동완성, fuzzy search, 전문검색, 검색 gem, 사용자 지정 정렬, 그래프·통계 dashboard, 사용량 analytics
- 자동 이상 탐지, 운영 alert, 새 audit/event 수집
- 학생 개인 선택 조회
- 전교투표 또는 Action Cable/Turbo runtime 변경
- schema migration, pagination library 추가
- school manager 기본 진입점을 `/school_polls`로 변경
- 별도 admin dashboard 추가
- `/teachers`, `/polls`, `/school_polls` 자체 기능 또는 권한 변경
- navigation 구조 추가 변경
