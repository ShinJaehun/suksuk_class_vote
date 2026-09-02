# 관리자 학급투표 운영 현황

## 목적

global admin이 여러 학교에서 교사가 준비·실행한 일반 학급투표의 상태와 보존된 이력을
한곳에서 조사할 수 있는 읽기 전용 monitoring 화면을 제공한다. 기존 교사용 `/polls`와
운영용 `PollSession#show`는 변경하거나 재사용하지 않는다.

## 접근 권한

- global admin만 목록·상세·종료 결과에 접근할 수 있다.
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
- 학급: `전체`와 특정 학교를 선택했을 때 그 학교·학년에 맞는 학급
- 상태: `전체 / 준비 / 진행 / 중단 / 종료`

기본값은 모두 `전체`다. 학교, 학년, 학급, 상태 조건은 다음 계층으로 조합한다.

- 학교가 `전체`이면 학년은 `전체` 또는 1~6학년을 선택할 수 있고, 학년 선택 시 모든 학교의
  해당 학년 PollSession을 조회한다. 학급은 `전체`로 유지하며 query의 `classroom_id`도 무시한다.
  서로 다른 학교의 동명 학급을 하나의 선택지에 섞지 않는다.
- 특정 학교를 선택하면 학급 선택지는 그 학교의 학급만 표시한다. 학년까지 선택하면 해당 학교와
  해당 학년을 모두 만족하는 학급만 표시하며, 이 범위에서 특정 학급을 선택할 수 있다.
- 유효한 특정 학급을 선택하면 그 학급의 PollSession만 조회한다.
- 학교 또는 학년 변경으로 학급 선택이 유효하지 않으면 학급 조건만 `전체`로 처리한다.
- 유효한 학교, 학년, 상태 조건은 학급 조건을 초기화할 때도 유지한다.
- 잘못된 ID, 학년, 상태는 허용 목록 밖 값으로 query하지 않는다. 독립적으로 잘못된 값은 `전체`로
  처리하되, 다른 유효한 조건을 제거하거나 그 범위 밖으로 결과를 넓히지 않는다.

필터는 `school_polls/index`와 `classrooms/index`의 관리 화면을 우선 참고하여 `rounded-md`,
`border border-stone-200`, `bg-white`, `p-4`와 같은 visual language, spacing, label/select typography를
맞춘다. 4개 필터에 필요한 반응형 배치는 유지하되 별도 dashboard panel처럼 과도하게 강조하지 않는다.
기존 GET/autosubmit 패턴을 재사용하며 새로운 JavaScript나 filter component/framework는 도입하지 않는다.

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
- admin 전용 상세 링크

대표 활동 시각과 참여 운영 집계는 목록에 표시하지 않고 admin 상세에서 표시한다. 대표 활동 시각
계산과 최신 활동순 ordering은 목록 내부 기준으로 계속 사용한다.

과거 실행 기록은 `classroom_name_snapshot`, `operator_name_snapshot`을 우선 표시한다. snapshot이
없을 때만 현재 Classroom/User 값을 fallback으로 사용하며 현재 값으로 snapshot을 덮어쓰지 않는다.
현재 학교명 snapshot 필드는 없으므로 학교는 연결된 현재 School 이름을 표시한다. 필터의
학교·학년·학급 범위는 현재 관계의 stable ID와 Classroom 속성을 사용하고, 학년·학급과 운영자
표시값은 역사 snapshot을 우선한다.

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

## Read-only detail / revote relationship

admin 전용 상세는 다음을 표시한다.

- Poll/PollSession 기본 metadata와 투표 종류·상태
- 현재 연결 학교, 학년/학급 snapshot과 운영 선생님 snapshot
- 생성, 시작, 종료, 중단과 대표 활동 시각
- 상태별 참여 운영 집계
- Poll 또는 PollSession 보관 여부
- 원투표와 재투표 관계

`replacement_of` 또는 `replacement_session`이 있으면 `중단된 원투표`와 `재투표` label로 관계를
표시하고 양쪽 admin monitoring 상세로 이동할 수 있게 한다. 관계가 없으면 표시하지 않는다.
관계를 생성·변경하는 action은 제공하지 않는다.

`closed` 상세에서는 기존 PollOptionTally/PollContestTally 기반 count-only 익명 결과를 조사할 수
있어야 한다. 기존 결과 표현을 재사용하더라도 admin monitoring 전용 read-only 응답에서 mutation
UI를 배제한다. 다른 상태에는 종료 결과를 제공하지 않는다.

구현 구조는 admin 전용임이 드러나는 `/admin/classroom_poll_sessions` 계열의 목록·상세·종료 결과
route와 controller를 우선한다. 교사용 `/polls`와 `PollSessionsController#show`에 monitoring 분기를
추가하지 않는다.

## Privacy

목록, 상세, 결과에는 다음을 노출하지 않는다.

- 학생 개인별 선택 내용 또는 ballot
- 누가 어떤 후보·선택지를 골랐는지 알 수 있는 정보
- 기권한 학생의 신원
- 개인의 선택을 추론할 수 있는 추가 정보

결과는 개인과 연결되지 않은 count-only tally만 사용한다.

## Performance constraints

- 학교, 학급, 운영자와 replacement 관계를 목록 row마다 별도 query하지 않는다.
- 현재 규모에 맞는 includes/preload와 group aggregate를 사용한다.
- 상세 참여 집계는 group aggregate를 사용하고 `SessionStatusCheck`로 추가 query를 반복하지 않는다.
- pagination gem이나 analytics infrastructure를 추가하지 않는다. pagination은 이번 MVP 필수가 아니다.

## Acceptance criteria

### A. admin navigation

global admin은 navigation에서 `전교투표` 바로 옆의 `학급투표`를 통해 monitoring 목록에 진입한다.
school manager와 일반 teacher에게 이 항목은 표시되지 않는다.

### B. 기본 전체 목록

filter 없이 진입하면 모든 학교의 `school_managed: false` PollSession을 보관 여부와 무관하게 조회한다.
네 lifecycle 상태를 모두 포함하고 전교투표는 제외하며 대표 활동 시각순으로 표시한다. 목록 열은
상태·보관 여부, 학교/학급, 운영 선생님, 제목/종류와 상세 링크로 제한한다.

### C. 계층 필터

전체, 학년만, 학교만, 학교+학년, 학교+학년+학급과 각 조합에 상태를 더한 조건에서 해당 범위의
PollSession만 표시한다. 학교가 `전체`이면 학급 선택과 `classroom_id`를 무시한다. 학교 또는 학년에
맞지 않는 학급 선택은 무시하되 유효한 학교·학년·상태 조건은 유지한다.

### D. draft

draft도 metadata와 함께 목록에 표시한다. 목록에는 실행 집계를 표시하지 않는다. 상세에서도 active
Student 수를 snapshot 수로 추정하지 않고 실행 집계를 `-` 등으로 표시하며, 준비·수정 form이나
mutation action을 제공하지 않는다.

### E. 진행/종료/중단

상세에서 각 상태의 lifecycle 시각과 PollParticipant/PollParticipation 기반
전체·완료·미참여·기권·대기를 현재 DB 상태대로 표시한다. 중단 상태의 대기를 숨기지 않으며 종료
상태의 대기가 0이 아니어도 그 값을 그대로 표시한다. 목록에는 시각과 참여 집계를 표시하지 않는다.

### F. 재투표

중단된 원 session과 replacement session의 관계를 양쪽 상세에서 확인하고 서로 이동할 수 있다.
관계를 생성하거나 변경할 수 없다.

### G. read-only 권한

global admin만 monitoring 목록·상세·결과를 조회한다. monitoring 영역에는 edit, start, stop, close,
revote, archive, delete, ballot operation을 표시하거나 제공하지 않는다. manager와 teacher의 직접
URL 요청은 거부하고 guest는 기존 인증 흐름을 따른다.

### H. privacy

목록·상세·결과는 학생 개인의 선택, ballot 또는 기권 학생 신원을 노출하지 않고 익명 count-only
결과만 표시한다.

### I. invalid filters

존재하지 않는 학교·학급 ID, 허용되지 않은 학년·상태, 서로 맞지 않는 학교-학급 조합은 500을
일으키지 않는다. 다른 유효한 상위 조건을 제거하거나 그 범위 밖 결과를 표시하지 않는다.

## Non-goals

- 학급투표 생성·수정 또는 admin 대리 운영
- start, stop, close, revote, archive, delete, ballot과 bulk operation
- school manager monitoring 또는 teacher별 filter
- 검색, 사용자 지정 정렬, 그래프·통계 dashboard, 사용량 analytics
- 자동 이상 탐지, 운영 alert, 새 audit/event 수집
- 학생 개인 선택 조회
- 전교투표 또는 Action Cable/Turbo runtime 변경
- schema migration, pagination library 추가
