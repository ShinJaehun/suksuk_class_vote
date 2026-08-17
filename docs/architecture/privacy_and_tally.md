# 비밀투표와 집계

## 목적

이 문서는 현재 Poll/PollSession runtime의 비밀투표, 학생별 상태 표시와 count-only 집계 원칙을 정의한다.

## 기본 원칙

시스템은 다음 연결을 저장하거나 외부에 표시하지 않는다.

```text
특정 학생 → 특정 후보 또는 선택지
특정 학생 → 기권
```

학생별 진행 상태와 실제 선택 결과를 분리한다. 운영자가 알아야 하는 것은 현재 학생이 투표 절차를 마쳤는지 또는 미참여 처리됐는지이며, 어떤 선택을 했거나 기권했는지가 아니다.

## PollParticipant snapshot

PollParticipant는 PollSession 시작 시 active Student에서 복사한 번호·이름·순서 snapshot이다. 이 snapshot은 진행 순서, 학생별 완료 여부와 역사 명단 표시의 기준이다.

PollParticipant는 선택한 PollOption을 저장하지 않는다. 원본 Student가 나중에 수정되거나 inactive가 되어도 이미 시작된 Session의 snapshot은 바뀌지 않는다.

## 참여와 항목 완료

`PollParticipation`은 학생별 절차 상태를 저장한다.

- `completed`: 투표 절차 완료
- `abstained`: 내부적으로 기권 완료를 표현하는 상태
- `absent`: 운영자가 처리한 미참여

`PollContestCompletion`은 학생이 특정 Contest 제출을 마쳤다는 사실만 저장한다. 선택한 PollOption은 연결하지 않는다.

이 상태는 중복 제출 방지와 진행 무결성을 위해 내부에 필요하지만 학생별 UI에서는 다음처럼 제한해 표시한다.

| 내부 상태 | 학생별 명단·교사 진행 화면 |
| --- | --- |
| `completed` | 투표 완료 |
| `abstained` | 투표 완료 |
| `absent` | 미참여 |
| participation 없음 | 대기 |

따라서 학생 이름 옆에 `기권` 또는 `기권 처리되었습니다`를 표시하지 않는다. `absent`는 학생의 선택이 아니라 운영자의 출석·참여 처리이므로 `미참여`로 구분한다.

## Count-only tally

실제 결과는 participant와 분리된 집계 row에 저장한다.

- `PollOptionTally`: PollSession·PollOption별 득표 수
- `PollContestTally`: PollSession·PollContest별 기권 수

선택 제출은 해당 option tally를 증가시키고, 항목 기권은 contest tally의 abstentions count를 증가시킨다. completion과 tally 갱신은 같은 transaction과 row lock 안에서 처리한다.

결과 화면은 후보·선택지별 표와 Contest별 기권 수를 표시할 수 있다. 이 수치는 익명 집계이며 PollParticipant와 연결되지 않는다.

## 표시용 참여 집계

상태 점검과 결과 요약은 다음 의미를 사용한다.

- 투표 대상자: Session의 PollParticipant 수
- 투표 완료: `completed + abstained`
- 미참여: `absent`
- 대기: PollParticipation이 없는 participant

이 집계에서도 학생별 기권 여부를 분리해 보여주지 않는다. 익명 기권표 수는 PollContestTally 결과에서만 다룬다.

## 운영 이벤트

PollEvent는 시작, ballot 열기·잠금, 학생 이동, 종료·중단 같은 운영 사실을 기록한다. 선택한 option이나 특정 학생의 기권 내용을 event payload에 남기지 않는다.

## 결과와 무결성

Session 종료 전 검사는 다음 수치 관계를 확인한다.

- participant와 participation 상태 수
- Contest completion 수
- option votes와 contest abstentions의 합
- Session·Poll·Contest·Option 연결 일치

검사는 개인별 선택을 복원하거나 대조하지 않는다. 결과와 인쇄 화면도 count-only tally를 사용하며 학생별 명단에는 제한된 참여 상태만 표시한다.

transaction, lock과 stale 요청 방어는 [복구와 무결성](recovery_and_integrity.md)을 따른다.
