# Election ID 6 복원 계약

## 1. 목적과 범위

이 문서는 2026-07-16 실제 전교임원선거인 legacy `Election ID 6`을 향후
`Classroom`·`Student` 및 `Poll`·`PollSession` 구조로 선택적 historical import할 때의
복원 성공 조건(acceptance criteria)을 정의한다. 구현 계획서나 다른 선거를 위한 범용
migration framework가 아니다. 아래 숫자는 현재 production 데이터의 일반 규칙이 아니라
오직 **2026-07-16 Election ID 6 복원을 위한 검증 기준**이다.

목표는 DB 전체 restore가 아니라 필요한 실제 운영 기록만 새 구조로 옮기는 것이다.
학생 이름, 교사 실명, 비밀번호, `encrypted_password`, 개별 로그인 ID 목록과 개별 투표
내용은 이 문서나 Git에 기록하지 않는다.

## 2. 기준 백업과 provenance

- 기준 백업: `20260716_134503_post_election`
- 시점: 2026-07-16 실제 전교임원선거 종료 후
- 구성: PostgreSQL dump와 Active Storage 백업
- 확인 사항: 분석 시 DB dump의 SHA256 검증 성공

로컬 PC의 절대 경로는 기록하지 않는다. 실제 import는 이 기준 백업에서 출처를 확인할 수
있어야 하며, 현재 production DB나 개발 DB에 dump를 그대로 덮어쓰지 않는다.

## 3. 사용자에게 복원되어야 할 상태

### 교사

- 실제 선거에 참여한 교사 계정 40개가 존재한다.
- 각 교사는 새 임시 비밀번호로 로그인하고, `password_change_required` 상태에서 자기
  비밀번호로 변경한다.
- 각 교사에게 당시 담당 `Classroom`과 그 학급의 `Student` 명단이 연결된다.
- 각 교사는 **내 투표 > 보관된 투표**에서 자기 학급의 Election ID 6 전교투표
  `PollSession` 결과를 확인할 수 있다.

### 관리자

- 전교투표 관리 영역에서 Election ID 6에 대응하는 historical school-managed `Poll`
  하나를 확인할 수 있다.
- 해당 Poll에서 최종 40개 학급 결과와 전체 집계 결과를 확인할 수 있다.

교사용 학급 Poll 40개를 별도로 복제하지 않는다. 하나의 `school_managed: true` Poll 아래에
학급별 `PollSession` 40개가 존재하는 현재 구조를 사용한다.

## 4. 필수 복원 데이터

| 대상 | 복원 기준 |
| --- | ---: |
| School | 1개(아라초등학교) |
| 실제 교사 계정 | 40개 |
| 최종 Classroom | 40개 |
| 최종 Student | 967명 |
| 실제 전교투표 | Election ID 6 한 건 |
| 선거 항목 | 3개 |
| 후보 | 24명 |
| 후보 사진 | 24개, attachment 및 storage 파일 24/24 확인 |
| 최종 학급 실행 | 40개 |
| 원본 ElectionSession | 42개(최종 40개 + 교체된 중단 세션 2개) |

## 5. old → new 대응

| old | new | 복원 계약 |
| --- | --- | --- |
| `School` | `School` | 학교 1개 보존 |
| 실제 teacher `User` | `User` + `SchoolMembership` | 실제 교사 40명만 복원 |
| `ParticipantGroup` | `Classroom` | 최종 40개 학급의 학교·학년·반 식별 정보 보존 |
| `ParticipantSlot` | `Student` | 최종 명단 967명의 `number`, `name` 보존 |
| `Election ID 6` | `Poll` | `school_managed = true`, `kind = election`, `status = closed`인 archived historical record |
| `ElectionContest` | `PollContest` | 3개 항목 보존 |
| `ElectionCandidate` | `PollOption` | 24명 후보 보존 |
| `ElectionCandidate` photo | `PollOption` photo | 이미지 content를 정상 attachment |
| `ElectionSession` | `PollSession` | 최종 40개 closed session 필수 |
| `ElectionVoter` | `PollParticipant` | 실행 당시 학생 snapshot 보존 |
| `ElectionParticipation` | `PollParticipation` | 최종 참여 상태 보존 |
| `ElectionCandidateTally` | `PollOptionTally` | count-only 집계 보존 |
| `ElectionContestTally` | `PollContestTally` | 항목별 기권 집계 보존 |
| `ElectionProgress` | closed `PollProgress` | closed session 무결성 충족 |
| `ElectionEvent` | 필수 대응 없음 | 전체 1:1 복원 제외 |

## 6. 교사 계정 계약

백업의 실제 선거 교사 계정 40개만 복원한다.

- `name` 등 필요한 계정 식별 정보를 보존하고, 필요한 경우 기존 email을 보존한다.
- `login_id`는 기존 계정 식별 정보에서 결정적으로 변환하되 개별 값은 문서화하지 않는다.
- 기존 `encrypted_password`는 가져오지 않는다.
- 교사별 새 임시 비밀번호를 발급하지만 문서나 Git에 기록하지 않는다.
- `password_change_required = true`, `active = true`로 복원한다.
- 아라초등학교 `SchoolMembership`을 만들고 해당 Classroom의 teacher로 연결한다.

legacy 테스트 교사와 legacy 관리자 계정은 복원하지 않는다. historical Poll owner가
필요하면 실제 import 시점에 지정된 production admin 계정을 사용한다. 학교 manager 지정은
필수 복원 조건이 아니며 필요할 때 운영 단계에서 별도로 지정한다.

## 7. 학급과 학생 계약

최종 40개 `ParticipantGroup`의 학교·학년·반 식별 정보를 `Classroom`으로 옮기고, 해당
최종 명단의 `ParticipantSlot` 967명을 `Student`로 옮긴다. 학생의 `number`와 `name`을
보존하되 개별 학생 정보는 기록하지 않는다.

백업 분석에서 확인된 무결성 기준은 다음과 같다.

- 최종 ParticipantSlot: 967명
- 빈 이름: 0
- 학급 내 번호 중복: 0
- 최종 ElectionVoter snapshot과 ParticipantSlot 비교: source 누락 0, 번호 불일치 0,
  이름 불일치 0, 학급 불일치 0

## 8. PollParticipant snapshot 계약

`PollParticipant`는 현재 `Student` 자체가 아니라 해당 투표 실행 당시 학생 snapshot이다.
따라서 복원된 PollParticipant의 `number`, `name`, `poll_session`, `poll`은 당시
`ElectionVoter` snapshot을 기준으로 보존한다. 향후 `ParticipantSlot`을 제거하므로 새
PollParticipant가 `source_participant_slot`에 의존하도록 설계하지 않는다.

## 9. PollParticipation와 completion 계약

legacy `ElectionParticipation`의 상태는 `pending`, `completed`, `absent`, `abstained`이고,
현재 `PollParticipation` row의 상태는 `completed`, `absent`, `abstained`다. 의미는 다음과
같이 고정한다.

- `completed + abstained` = 참여
- `absent` = 미참여
- participation row 없음 = pending

최종 closed 40개 세션에는 pending이 없어야 한다.

| 상태 | 최종 수치 |
| --- | ---: |
| completed | 947 |
| absent | 14 |
| abstained | 6 |
| 합계 | 967 |
| participated (`completed + abstained`) | 953 |

legacy Election 엔진에는 현재의 `PollContestCompletion`과 동일한 row가 없다. 최종 closed
세션에서는 absent가 아닌 953명 모두 3개 contest 처리를 마친 것으로 복원한다. 따라서
completion acceptance count는 **953 × 3 = 2,859 rows**이며 absent 14명에게는 completion을
만들지 않는다. PollContestCompletion은 contest 완료 사실만 나타내며 선택 내용을 저장하지
않는다. 개인이 어느 후보를 선택했는지는 복원하거나 추론하지 않는다.

## 10. 집계와 비밀투표 계약

개별 표를 재구성하지 않는다. 기존 count-only tally만 privacy를 유지해
`ElectionCandidateTally`에서 `PollOptionTally`로, `ElectionContestTally`에서
`PollContestTally`로 옮긴다.

전체 검산은 각 contest마다 다음을 만족해야 한다.

```text
후보 득표 합계 + contest abstentions = participated = 953
```

확인된 contest abstention 합계는 회장 9, 6학년 부회장 25, 5학년 부회장 23이다. 각 최종
학급 session에서도 다음 식이 성립해야 한다.

```text
후보 득표 합계 + 해당 contest 기권 수 = 그 학급의 completed + abstained 수
```

## 11. PollProgress 계약

각 최종 PollSession에는 현재 closed session integrity 검사를 통과하는 정상적인 closed
`PollProgress`가 있어야 한다. 원본 시작·종료 시각을 가능한 범위에서 보존하고 다음 조건을
충족한다.

- `status = closed`
- ballot locked
- `started_at` 존재
- `closed_at` 존재

현재 투표자 포인터는 historical 결과에 필요하지 않다면 `nil`일 수 있다. 중간 실행 화면
상태를 완벽하게 재현하는 것은 복원 목표가 아니다.

## 12. 재투표 이력 정책

필수 acceptance criteria는 최종 결과에 포함되는 **40개 closed PollSession**이다. 중단 후
재투표로 교체된 원본 세션 2개는 historical operation detail이다. 새 PollSession의
`replacement_of`/`replacement_session` 구조에 안전하고 단순하게 대응할 수 있으면 함께
보존할 수 있으나, 이 2개를 복원하지 못해도 ID 6 최종 결과 복원 실패로 판단하지 않는다.

- 필수: 최종 40개 closed PollSession
- 선택: superseded/stopped 원본 2개

다만 원본 백업에 교체된 중단 세션 2개가 존재했다는 provenance 자체는 리팩터링 중 잃지
않는다.

## 13. PollEvent 정책

`ElectionEvent` 전체를 새 `PollEvent`로 1:1 이관하는 것은 필수 조건이 아니다. 학급별
보관 결과, 관리자 전체 결과, 참여 상태, 집계와 재투표 결과의 최종성을 보존하는 것이
목표다. legacy operation event log의 완전한 재현을 위해 새 Poll 구조를 복잡하게 만들지
않는다. import provenance를 위한 최소 historical/import event가 필요한지는 향후 구현
단계에서 판단하며, 이 문서에서는 방식을 확정하지 않는다.

## 14. 후보 사진 계약

후보 24명의 사진은 필수 복원 대상이며 백업에서 attachment와 storage 파일이 24/24 존재함을
확인했다. legacy Active Storage record ID는 보존할 필요가 없다. 새 `PollOption`에 실제 이미지
content가 정상 attachment되어 화면에 표시되면 된다.

## 15. 제외 데이터

다음 데이터는 가져오지 않는다.

- Election ID 6 이외의 모의·테스트 Election
- legacy 테스트 교사 계정
- legacy 관리자 계정 자체
- 백업에 있던 테스트 Poll
- 실제 데이터가 없던 legacy SchoolElection 구조
- 기존 `encrypted_password`
- 개별 학생의 후보 선택 추론 또는 복원
- legacy event log의 완전한 1:1 재현
- 개발·테스트용 데이터

이는 DB 전체 restore가 아니라 Election ID 6을 위한 **선택적 historical import**다.

## 16. 리팩터링과 실제 import 순서

1. 이 recovery contract를 확정한다.
2. legacy Election runtime을 제거한다.
3. ParticipantGroup·ParticipantSlot·roster legacy를 제거한다.
4. Poll·PollSession 구조를 최종 정리한다.
5. 최종 schema 기준 one-off importer를 작성한다.
6. Valkyrie에서 빈 새 DB에 import를 리허설한다.
7. 이 문서의 acceptance count를 전부 검산한다.
8. 브라우저에서 교사·관리자 복원 흐름을 확인한다.
9. 마지막 production 배포 때 실제 import를 수행한다.

현재 단계에서는 production DB를 변경하지 않으며 개발 DB에도 백업 dump를 덮어쓰지 않는다.

## 17. Recovery acceptance checklist

### 데이터와 무결성

- [ ] School: 1
- [ ] Teacher User: 40
- [ ] Classroom: 40
- [ ] Student: 967
- [ ] historical school-managed Poll: 1
- [ ] PollContest: 3
- [ ] PollOption: 24
- [ ] candidate photo: 24/24
- [ ] current/final closed PollSession: 40
- [ ] final PollParticipant: 967
- [ ] completed: 947
- [ ] absent: 14
- [ ] abstained: 6
- [ ] participated: 953
- [ ] PollContestCompletion: 2,859
- [ ] 각 contest에서 option tally 합 + abstention tally = 953
- [ ] 각 학급·contest에서 option tally 합 + abstention tally = 학급의 completed + abstained
- [ ] 원본에 superseded/stopped 세션 2개가 존재했다는 provenance 보존

### 교사 브라우저 acceptance

- [ ] 임시 비밀번호 로그인
- [ ] 비밀번호 변경
- [ ] 자기 Classroom 확인
- [ ] Student 명단 확인
- [ ] 내 투표 > 보관된 투표 진입
- [ ] 자기 학급의 ID 6 결과 확인

### 관리자 브라우저 acceptance

- [ ] 전교투표 진입
- [ ] historical ID 6 Poll 확인
- [ ] 최종 40개 학급 결과 확인
- [ ] 전체 결과 확인
