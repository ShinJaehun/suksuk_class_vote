# 로그인 rate-limit credential 복구 정책

## 목적

로그인 실패 제한은 유지하면서, 실제 로그인 비밀번호가 변경된 뒤에도 이전 비밀번호의
차단이 남아 새 자격 증명의 사용을 막는 운영 결함을 방지한다. 새 임시 비밀번호 발급과
정상적인 비밀번호 변경은 별도 수동 unlock이나 대기 없이 즉시 복구 수단이 되어야 한다.

## Requirements

- 로그인 실패 제한은 정규화한 `login_id`와 요청 IP를 기준으로 5회 실패 시 10분간 적용한다.
- 실패 횟수와 차단 상태는 현재 credential generation에 귀속한다.
- 관리자가 새 임시 비밀번호를 발급하거나 사용자가 비밀번호를 정상 변경하여 실제 로그인
  비밀번호가 바뀌면, 이전 credential generation의 실패와 차단은 새 credential에 영향을 주지 않는다.
- 기존 credential이 차단된 상태여도 정확한 새 임시 비밀번호로 즉시 로그인할 수 있어야 한다.
- 새 credential에서 발생한 실패는 0회부터 다시 누적하고, 5회 실패하면 다시 10분간 차단한다.
- 현재 credential로 로그인에 성공하면 그 credential의 실패와 차단 상태를 초기화한다.
- 동일한 credential이 차단된 동안에는 올바른 비밀번호도 검증 전에 계속 차단할 수 있다.
- 복구를 위해 운영자 수동 unlock을 요구하지 않는다.

## Security constraints

- 임시 비밀번호 사용자에게 무제한 로그인 시도를 허용하지 않는다.
- 존재하지 않는 `login_id`도 동일한 5회/10분 정책으로 throttle하며, credential generation을
  알 수 없는 경우 사용할 안전하고 안정적인 namespace를 둔다.
- 인증 실패 메시지와 처리 결과로 계정 존재 여부를 추론할 수 없어야 한다.
- plaintext 비밀번호, 임시 비밀번호와 `encrypted_password` 자체를 로그나 cache key에 기록하지 않는다.
- credential generation 식별이 필요하면 비가역 fingerprint처럼 원래 값을 복원할 수 없는 값을 사용한다.
- cache key는 정규화한 `login_id`, IP와 credential 식별 원문을 직접 노출하지 않는다.

## Recovery behavior

- `429 Too Many Requests` 응답은 일반 인증 실패와 구분하여 로그인 시도가 너무 많아 잠시
  제한되었음을 명확히 안내한다.
- 안내에는 필요한 경우 관리자에게 새 임시 비밀번호 발급을 요청할 수 있다고 표시하되, 현재
  입력한 `login_id`가 실제 존재하는 계정임을 암시하지 않는다. 실제 계정에 새 임시 비밀번호가
  발급되면 기존 credential의 차단과 관계없이 즉시 다시 로그인할 수 있다.
- 정확한 남은 제한 시간은 표시하지 않아도 된다.
- `Retry-After` 헤더는 현재 구조에서 작은 변경으로 제공할 수 있을 때만 고려하며 필수 요건이 아니다.
- 오류 화면과 응답에는 입력한 비밀번호나 임시 비밀번호 등 민감정보를 노출하지 않는다.

## Acceptance criteria

### A. 같은 credential의 차단 유지

기존 credential로 5회 실패하면 차단된다. 이어서 같은 credential의 올바른 비밀번호를
입력해도 차단은 유지되고 로그인되지 않는다.

### B. 새 임시 비밀번호로 즉시 복구

기존 credential로 5회 실패해 차단된 뒤 관리자가 새 임시 비밀번호를 발급하면, 정확한 새
임시 비밀번호 입력은 10분을 기다리지 않고 즉시 로그인에 성공한다.

### C. 새 credential의 독립적인 재차단

기존 credential 차단 뒤 새 임시 비밀번호를 발급하고 이를 5회 잘못 입력하면, 새 credential
기준으로 다시 10분간 차단된다.

### D. 정상 비밀번호 변경

기존 credential에 실패 기록이 있어도 사용자가 비밀번호를 정상 변경하면, 이전 기록은 새
credential 로그인에 영향을 주지 않는다.

### E. 존재하지 않는 login_id

존재하지 않는 `login_id`의 반복 실패도 기존과 동등하게 throttle된다. 응답 상태와 메시지로
계정 존재 여부를 노출하지 않는다.

### F. 429 UX와 민감정보

429 응답에는 일반 인증 실패와 구분되는 rate-limit 안내와 필요한 경우 관리자에게 새 임시
비밀번호 발급을 요청할 수 있다는 안내만 외부적으로 표시하며, 현재 입력한 `login_id`의 계정
존재 여부를 암시하지 않는다. 응답, 로그와 cache key에는 비밀번호 등의 민감정보가 노출되지 않는다.

## 설계 메모

현재 `encrypted_password`의 비가역 fingerprint를 limiter namespace에 포함하여 비밀번호 변경이
자연스럽게 새 namespace를 만들도록 하는 접근을 우선 검토한다. 존재하지 않는 계정에는 안전한
고정 generation을 사용해 반복 요청을 계속 제한할 수 있어야 한다. request spec은 위 관찰 가능한
행동을 검증하고 fingerprint 형식이나 cache key 조립 방식에는 결합하지 않는다.

관련 검증 위치는 `spec/requests/user_sessions_spec.rb`, `spec/requests/teachers_spec.rb`,
`spec/requests/password_changes_spec.rb`다.

## Non-goals

- 로그인 제한 횟수 또는 시간 변경
- CAPTCHA
- 계정 잠금 시스템 신설
- 관리자용 수동 unlock UI
- 이메일 또는 SMS 복구
- 로그인 감사 대시보드
- admin 학급투표 운영 현황
- 기타 인증 구조 리팩터링
