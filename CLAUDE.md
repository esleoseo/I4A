# I4A 작업 규칙

## CI(GitHub Actions)는 꼭 필요할 때만, 허락받고

GitHub Actions 이용량이 넉넉하지 않다. 꼭 필요하지 않으면 CI를 돌리지 않는다.

- **금지**: 워크플로 추가, 수동 실행(workflow_dispatch), 재실행, 빈 커밋으로 CI 깨우기.
- 검사는 세션 안에서 직접 한다(아래 목록).
- CI가 꼭 필요하면 **먼저 사용자에게 이유를 말하고 허락을 받는다.**
- `.github/workflows/ci.yml`은 push마다 자동으로 실행된다. 허락받지 않은 push는 커밋 메시지에 `[skip ci]`를 넣어 CI가 돌지 않게 한다.
- 실행 기록이나 로그를 읽는 것은 괜찮다(이용량을 쓰지 않음).

## 세션 안에서 하는 검사

Xcode가 없는 환경이라 Swift 컴파일과 단위 테스트는 세션에서 돌릴 수 없다. 그 외에는 직접 확인한다.

- **페이지 스크립트**(`I4A/ContentScripts.swift`): Swift 문자열에서 CSS/JS를 뽑아 `node --check`로 문법을 보고, Playwright Chromium으로 모의 인스타그램 DOM에서 동작을 확인한다.
  - Swift 여러 줄 문자열 안의 JS 백슬래시는 `\\`로 써야 한다. `\/`처럼 하나만 쓰면 Swift 컴파일 에러가 난다(JS 추출 테스트로는 안 잡힘). 고친 뒤 `grep -nP '(?<!\\)\\[^\\(n"]' I4A/ContentScripts.swift`로 남은 게 없는지 확인한다.
- **관리자 서버**(`admin/`): `npx wrangler dev`로 띄워 curl과 Playwright로 API와 페이지를 확인한다. `.dev.vars`에 `ADMIN_TOKEN=...`을 넣는다(커밋하지 않음).
- **프로젝트 파일**: `xmllint --noout`로 plist/scheme을, Python `openstep_parser`로 `project.pbxproj`를 파싱하고 모든 ID 참조가 존재하는지 확인한다.
- Swift 코드를 바꿨을 때는 API 시그니처와 iOS 16 배포 대상 호환성을 직접 꼼꼼히 검토한다. 컴파일 확인이 꼭 필요하면 위 규칙대로 허락을 받는다.
