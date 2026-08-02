# 전교임원선거 배포 체크리스트

> 역사 문서: 이 문서는 legacy Poll 기반 전교임원선거 운영 당시의 기록이며 현재
> 운영 절차로 그대로 사용할 수 없다. 현재 구조와 운영 기준은
> `docs/architecture/school_voting_platform.md`를 참고한다.

## 목적

이 문서는 전교임원선거를 production에 배포하고 실제 선거를 운영하기 전에 확인할
최소 체크리스트다. 정책 기준은
`docs/specs/school_council_election.md`를 따른다.

## 1. 배포와 데이터베이스

- [ ] 배포 대상 commit과 branch를 확인한다.
- [ ] production DB 백업을 생성하고 복구 방법을 확인한다.
- [ ] 미적용 migration 목록과 적용 순서를 확인한다.
- [ ] active 학급 세션 partial unique index migration 적용 여부를 확인한다.
- [ ] `election_sessions.hidden_from_teacher_at` migration 적용 여부를 확인한다.
- [ ] migration 이후 application boot와 health check를 확인한다.
- [ ] migration 실패 시 중단 기준과 rollback 절차를 준비한다.

## 2. Production 환경

- [ ] `RAILS_ENV`, `RAILS_MASTER_KEY` 또는 credentials 주입을 확인한다.
- [ ] `DATABASE_URL` 또는 `SUKSUK_CLASS_VOTE_DATABASE_PASSWORD` 기반 production DB 연결을 확인한다.
- [ ] `SECRET_KEY_BASE`와 세션 cookie 설정을 확인한다.
- [ ] production 로그 출력, host, HTTPS 관련 설정을 확인한다.
- [ ] Action Cable 연결 경로와 reverse proxy의 WebSocket 설정을 확인한다.
- [ ] production 시간대 표시가 KST로 보이는지 확인한다.

## 3. Active Storage

- [ ] 후보 사진 업로드에 사용하는 Active Storage service를 확인한다.
- [ ] local storage 사용 시 host directory 또는 Docker volume이 `/rails/storage`에 영구 mount되어 있는지 확인한다.
- [ ] container 재생성 뒤에도 기존 후보 사진이 유지되는지 확인한다.
- [ ] storage directory 권한과 남은 디스크 용량을 확인한다.
- [ ] 배포 전 후보 사진 업로드와 표시를 한 번 검증한다.

## 4. 운영 계정과 기준 데이터

- [ ] 실제 운영 admin 계정을 준비하고 로그인한다.
- [ ] 담당 교사 계정과 이름, 학급 배정을 확인한다.
- [ ] 학교 정보가 올바른지 확인한다.
- [ ] `/admin/election_rosters`에서 공식 투표자 명단을 준비한다.
- [ ] 학년, 반, 담당 교사, 학생 번호와 이름을 검수한다.
- [ ] 학생 번호 중복과 빈 이름이 없는지 확인한다.
- [ ] 이미 다른 활성 세션에 잘못 배정된 명단이 없는지 확인한다.

## 5. 선거 구성

- [ ] 선거명과 대상 학교를 확인한다.
- [ ] 회장, 부회장 등 선출 항목을 확인한다.
- [ ] 후보 번호, 이름, 소속 표시를 확인한다.
- [ ] 후보 사진의 방향, 크롭, 누락 여부를 확인한다.
- [ ] 각 학급의 담당 교사와 공식 명단을 세션으로 배정한다.
- [ ] 배정 학급 수와 예상 투표자 수를 대조한다.
- [ ] 선거 시작 전 후보와 학급 구성을 최종 확정한다.

## 6. 운영 전 Smoke Test

production과 같은 브라우저·네트워크 조건에서 별도의 모의 선거로 확인한다.

- [ ] Admin이 draft 선거를 시작할 수 있다.
- [ ] Teacher `/polls`에 본인 학급 세션만 표시된다.
- [ ] Teacher가 학급 세션을 시작하면 voter snapshot과 첫 학생 진행 상태가 생성된다.
- [ ] 후보 선택 제출과 기권 제출이 각각 한 번만 반영된다.
- [ ] 미참여 처리와 다음 학생 이동이 정상 동작한다.
- [ ] 마지막 학생 처리 뒤 `투표 화면 열기`가 사라지고 `투표 종료`가 표시된다.
- [ ] 학급 세션 종료 뒤 parent 선거는 자동 종료되지 않는다.

### Ballot 창

- [ ] 첫 클릭에서 ballot 창이 한 개 열린다.
- [ ] 같은 교사 화면에서 반복 클릭해도 새 창이 추가되지 않는다.
- [ ] 반복 클릭 시 기존 ballot 창이 focus되거나 안내가 표시된다.
- [ ] ballot 창을 닫은 뒤 다시 열면 실제 ballot 화면이 열린다.
- [ ] 대기 학생이 없으면 ballot 열기 링크가 표시되지 않는다.
- [ ] 직접 ballot URL 접근은 서버 guard가 상태에 맞게 차단한다.

### 화면 동기화와 복구

- [ ] 학생 제출 뒤 교사 화면에 다음 학생 또는 종료 안내가 표시된다.
- [ ] Action Cable broadcast를 놓쳐도 polling으로 수 초 안에 DB 상태가 복구된다.
- [ ] 교사 화면 새로고침 뒤 현재 학생과 처리 수가 유지된다.
- [ ] 교사 로그아웃·재로그인 뒤 진행 위치가 유지된다.
- [ ] 브라우저 종료 또는 컴퓨터 재부팅 뒤 DB 상태에서 계속 운영할 수 있다.
- [ ] 오래 열린 이전 ballot의 stale 제출이 거부된다.

## 7. 중단과 재투표

- [ ] 전체 중단 시 parent 선거와 미종료 학급 세션이 stopped가 된다.
- [ ] Parent stopped 선거의 admin 상세에 학급 세션이 사라지지 않는다.
- [ ] 특정 학급 재투표 시 기존 세션이 stopped 이력으로 남는다.
- [ ] Replacement 세션이 같은 선거, 학급, 교사의 draft로 생성된다.
- [ ] 기존 voter, participation, tally, event가 삭제되지 않는다.
- [ ] 기존 ballot 창에는 중단 안내만 표시되고 제출 UI가 없다.
- [ ] Admin 상세에서 현재 세션과 stopped 이력을 모두 확인할 수 있다.
- [ ] Teacher는 stopped 상세를 확인한 뒤 본인의 `/polls` 목록에서만 숨길 수 있다.
- [ ] 숨긴 뒤에도 admin stopped 이력과 직접 상세 접근이 유지된다.

## 8. 정상 종료와 결과

- [ ] 모든 현재 non-stopped 학급 세션이 closed인지 확인한다.
- [ ] Admin 화면에 모든 학급 투표 종료 안내와 `선거 종료`가 표시된다.
- [ ] Admin이 명시적으로 선거를 종료해야 parent `Election`이 closed가 된다.
- [ ] 종료 전 results 직접 접근이 차단된다.
- [ ] 종료 후 결과 페이지에 closed 학급 세션만 표시된다.
- [ ] stopped, draft, in_progress 세션과 제외 카드가 results에 표시되지 않는다.
- [ ] 완료 학급 numerator와 denominator가 closed 세션 기준으로 일치한다.
- [ ] 후보별 득표, 기권, 투표 완료, 미참여 합계를 학급별 기록과 대조한다.
- [ ] 결과 인쇄 화면의 선거명, 시행일, 후보, 득표를 확인한다.

## 9. 실제 선거 당일 운영

- [ ] Admin과 담당 교사의 연락 수단과 장애 보고 절차를 공유한다.
- [ ] 재투표 판단과 전체 중단 판단 권한을 admin으로 한정한다.
- [ ] 장애 시 반복 클릭보다 새로고침과 DB 상태 확인을 우선한다.
- [ ] 잘못된 세션을 삭제하거나 DB에서 직접 수정하지 않는다.
- [ ] 재투표 전 대상 학급과 기존 세션을 다시 확인한다.
- [ ] 선거 종료는 모든 학급 현황과 stopped 대체 여부를 확인한 뒤 실행한다.

## 10. 선거 후 보존

- [ ] 종료 직후 production DB 백업을 생성한다.
- [ ] Active Storage 후보 사진과 DB 백업의 보존 위치를 기록한다.
- [ ] Admin 결과 화면과 학급별 closed 세션을 검산한다.
- [ ] stopped 세션, voter, participation, tally, event를 삭제하지 않는다.
- [ ] 운영 중 발생한 중단, 재투표, 네트워크 장애를 별도 기록한다.
- [ ] 백업 복구 가능성을 확인한 뒤 후속 정리 작업을 시작한다.

## 선거 후 별도 리팩터링

실제 선거 전에는 legacy Poll-backed `school_election` 코드를 제거하지 않는다.
선거 완료와 백업·검산 이후 별도 브랜치에서 다음을 조사한다.

- Poll source link 기반 전교임원선거 흐름
- `SchoolElectionClassroomSession`과 관련 controller/view
- Poll 화면과 `PollsController`의 `school_election` 조건 분기
- 현재 `Election` / `ElectionSession` 흐름으로 대체된 route, policy, spec, 문서

정리 작업은 사용 여부와 보존 데이터 영향을 확인한 뒤 별도 승인으로 진행한다.
