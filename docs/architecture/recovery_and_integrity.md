# 복구와 무결성

## 목적

이 문서는 현재 PollSession runtime이 새로고침, 중복 요청, broadcast 유실, 중단과 재투표 상황에서도 DB 상태로 안전하게 수렴하기 위한 원칙을 정의한다.

## authoritative state

화면과 Action Cable 메시지가 아니라 PostgreSQL의 PollSession, PollProgress, PollParticipant, PollParticipation, PollContestCompletion과 tally가 authoritative state다.

사용자가 페이지를 새로고침하거나 다시 로그인하면 controller는 현재 DB 상태를 읽어 같은 진행 위치와 terminal 상태를 렌더링한다. Turbo Stream은 이 상태를 빠르게 전달하지만 별도의 정답 상태를 소유하지 않는다.

## 시작의 원자성

PollSession 시작은 하나의 transaction에서 다음을 함께 처리한다.

- 실행 가능한 draft 상태와 학교·Classroom 상태 재확인
- active Student의 PollParticipant snapshot 생성
- PollProgress와 option·contest tally 생성
- 첫 current participant와 locked ballot 설정
- Session 시작 시각·상태와 event 저장

부분 저장은 허용하지 않는다. 시작이 실패하면 snapshot, progress와 tally를 모두 rollback한다.

## 제출과 중복 방지

학생 제출은 요청 파라미터를 신뢰하기 전에 현재 Session, current participant, ballot 상태와 미완료 Contest를 DB에서 다시 확인한다.

- 주요 Session 경로는 PollSession 다음 PollProgress 순서로 lock한다.
- Contest completion은 participant·contest 조합의 완료 사실을 고정한다.
- option vote 또는 contest abstention과 completion은 같은 transaction에서 갱신한다.
- 중복·stale 요청은 이미 완료된 Contest나 현재 위치 불일치로 거부한다.
- 실패한 transaction은 tally와 진행 위치를 함께 rollback한다.

개인 선택은 저장하지 않으며 무결성 검사는 count와 관계만 확인한다.

## 참여와 진행

학생의 확정 참여 상태는 `completed`, `absent`, `abstained`다. participation이 없으면 대기 상태다. 다음 학생 이동은 현재 학생에게 처리되지 않은 Contest가 없는지 확인한 뒤 명시적으로 수행한다.

학생별 UI에서는 completed와 abstained를 모두 `투표 완료`로 표시한다. absent만 `미참여`, participation 없음은 `대기`다. 내부 abstained 상태가 복구·집계에 사용되더라도 이름과 기권 여부를 연결해 노출하지 않는다.

부분 완료 학생은 남은 Contest를 마치기 전까지 다음 학생 이동, 미참여 처리와 Session 종료를 할 수 없다.

## 종료와 상태 점검

Polls::SessionStatusCheck는 상태별로 필요한 정의와 runtime 관계를 확인한다.

- PollSession·PollProgress 상태와 시각 일치
- PollParticipant snapshot 존재와 current 위치
- participation과 Contest completion 수
- option votes와 contest abstentions 수
- Poll·Session·Contest·Option 관계

종료는 모든 학생 처리가 확정되고 tally 식이 맞을 때만 허용한다. closed·stopped 상태에서는 추가 제출과 진행 mutation을 차단한다.

## 중단과 replacement

중단은 Session을 stopped로 전환하고 기존 participant, progress, completion, tally와 event를 보존한다. 중단된 Session을 초기화하거나 재개하지 않는다.

재투표는 source Session을 가리키는 새 replacement Session을 만든다. source와 replacement를 모두 보존하며 current execution은 replacement가 없는 Session이다. 학교 전체 결과에는 최종 current closed Session만 포함한다.

## Realtime과 polling

Action Cable/Turbo Stream은 빠른 갱신 경로이고 HTTP polling/recovery는 안전망이다.

### 교사 운영 화면

- 진행 중 teacher progress Turbo Frame은 5초 간격으로 operation frame을 확인한다.
- `operation_screen` Turbo Stream은 진행 중이며 `PollSessionPolicy#operate?`가 true인 사용자만 구독한다.
- 실제 operator와 허용된 admin은 realtime 갱신을 받는다.
- 조회만 가능한 school manager는 operation stream을 구독하지 않지만 같은 HTTP polling frame으로 DB 진행 상태를 갱신한다.
- terminal marker가 나타나면 polling 교체가 종료 상태로 수렴한다.

### 학생 ballot

- ballot 화면은 `ballot_screen` Turbo Stream을 구독한다.
- ballot Turbo Frame은 5초 polling을 사용한다.
- 입력 form이 활성 상태일 때 사용자의 선택을 불필요하게 덮어쓰지 않도록 pause selector를 적용한다.
- 별도 recovery controller가 진행 중 10초 간격으로 현재 runtime fingerprint와 DB 상태를 확인한다.
- terminal 상태 또는 current participant·ballot 상태 변경이 확인되면 필요한 ballot 영역만 교체한다.

### Draft school-managed Session

draft school-managed PollSession 화면은 10초 recovery 확인으로 상태 변경이나 권한·운영 조건 변화를 DB 기준으로 반영한다.

### Schoolwide 관리 화면

schoolwide runtime broadcast는 user별 stream을 사용한다. active global admin과 Poll의 같은 학교 active manager만 recipient가 된다. Classroom Session 상태와 전체 status runtime을 필요한 대상에 replace한다.

recipient stream과 view 구독 조건은 UI 정보 노출을 줄이기 위한 경계다. mutation의 최종 권한은 항상 controller policy와 service guard가 다시 검증한다.

## Broadcast 실패와 HTTP 수렴

DB transaction 성공과 broadcast 성공은 같은 의미가 아니다. mutation이 저장된 뒤 broadcast 렌더링이나 전송이 실패해도 저장된 DB 상태가 기준이다. 오류는 운영 로그에 남기고, 열린 화면은 다음 polling/recovery 또는 새로고침에서 현재 상태로 수렴한다.

따라서 broadcast 실패를 이유로 성공한 tally를 다시 적용하거나 transaction을 임의로 반복하지 않는다.

## 진행 중 구조 변경 보호

진행 중 일반 PollSession 또는 진행 중 school-managed Poll에 연결된 current Session이 있으면 관련 model validation과 service가 다음 변경을 제한한다.

- Classroom 담임·학년과 비활성화
- operator·Session 관계 변경
- 결과 의미에 영향을 주는 Poll 정의·대상 변경
- active teacher lifecycle 변경

admin도 이 무결성 guard를 우회하지 않는다. 변경이 필요하면 지원되는 중단·replacement 절차를 사용한다.

## Snapshot 복구 기준

복구와 역사 표시는 시작 당시 snapshot을 기준으로 한다.

- PollParticipant의 이름·번호·순서
- PollSession의 학급명·운영자명
- Session별 participation, completion, progress와 tally

현재 Student, Classroom 또는 User 변경으로 과거 snapshot을 갱신하지 않는다. 결과 학년은 학급 snapshot에서 읽은 역사적 학년을 우선하며, snapshot이 없거나 형식을 읽지 못할 때만 현재 Classroom grade를 fallback으로 사용한다.

비밀투표와 count-only 집계 계약은 [비밀투표와 집계](privacy_and_tally.md)를 따른다.
