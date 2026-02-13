# dogfinder

Dog sighting/lost report app (Flutter).

## Added in this update

- Sighting/Lost time picker now uses explicit hour/minute selectors.
- Color field supports custom input when `Other` is selected.
- Location input now supports:
  - current device location
  - map selection (OpenStreetMap via `flutter_map`)
  - reverse geocoded address preview (district/neighborhood style)
- `My Activity` now requires login and supports:
  - Kakao login
  - Naver login
- New `Shelter/Protection` flow:
  - new `보호` post type in feed filters and cards
  - dedicated `보호 등록` page in Register tab
  - `My Activity` supports `내 보호글`
- Realtime in-app alerts (backend mode):
  - periodic pull sync detects new nearby posts and new tips on my posts
  - Nearby app bar bell opens live alert sheet
- FCM/APNs push wiring (new):
  - foreground push is shown as local notification
  - FCM token is registered to backend (`/v1/push/tokens`)

## OAuth setup (required for real social login)

### 1) Dart define for Kakao SDK init

Run app with:

```bash
flutter run --dart-define=KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY
```

### 2) Android keys (`android/gradle.properties`)

Set:

```properties
KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY
NAVER_CLIENT_ID=YOUR_NAVER_CLIENT_ID
NAVER_CLIENT_SECRET=YOUR_NAVER_CLIENT_SECRET
NAVER_CLIENT_NAME=YOUR_NAVER_CLIENT_NAME
```

### 3) iOS keys (`ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig`)

Set:

```xcconfig
KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY
NAVER_CLIENT_ID=YOUR_NAVER_CLIENT_ID
NAVER_CLIENT_SECRET=YOUR_NAVER_CLIENT_SECRET
NAVER_CLIENT_NAME=YOUR_NAVER_CLIENT_NAME
NAVER_URL_SCHEME=YOUR_NAVER_URL_SCHEME
```

`Info.plist` already references these values.

## Validate

```bash
flutter pub get
flutter analyze
```

## 🚀 실행 스크립트 (웹/안드로이드/iOS)

이 프로젝트는 Flutter 실행 시 기존 프로세스 충돌을 줄이기 위해 스크립트를 제공합니다.

⚠️ iOS 주의
`run-ios.ps1`는 **macOS + Xcode** 환경에서만 동작합니다. Windows에서는 iOS 실행이 불가능합니다.

- Windows에서 즉시 사용 가능: `run-web.ps1`, `run-android.ps1`
- macOS에서 iOS 포함 사용 가능: `run-ios.ps1`

### 1) 기본 실행

- 웹: `.\run-web.ps1`
- 안드로이드: `.\run-android.ps1`
- iOS: `.\run-ios.ps1`

### 2) 실전용 템플릿

웹 예시

```bash
.\run-web.ps1 -DartDefineString "BACKEND_BASE_URL=http://localhost:3000;KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY;NAVER_CLIENT_ID=YOUR_NAVER_CLIENT_ID;NAVER_CLIENT_SECRET=YOUR_NAVER_CLIENT_SECRET;NAVER_CLIENT_NAME=YOUR_NAVER_CLIENT_NAME;FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY;FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID;FIREBASE_MESSAGING_SENDER_ID=YOUR_FIREBASE_MESSAGING_SENDER_ID;FIREBASE_ANDROID_APP_ID=YOUR_FIREBASE_ANDROID_APP_ID;FIREBASE_IOS_APP_ID=YOUR_FIREBASE_IOS_APP_ID;FIREBASE_IOS_BUNDLE_ID=YOUR_FIREBASE_IOS_BUNDLE_ID;FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET"
```

안드로이드 예시

```bash
.\run-android.ps1 -DartDefine @(
  "BACKEND_BASE_URL=http://localhost:3000",
  "KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY",
  "NAVER_CLIENT_ID=YOUR_NAVER_CLIENT_ID",
  "NAVER_CLIENT_SECRET=YOUR_NAVER_CLIENT_SECRET",
  "NAVER_CLIENT_NAME=YOUR_NAVER_CLIENT_NAME",
  "FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY",
  "FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID",
  "FIREBASE_MESSAGING_SENDER_ID=YOUR_FIREBASE_MESSAGING_SENDER_ID",
  "FIREBASE_ANDROID_APP_ID=YOUR_FIREBASE_ANDROID_APP_ID",
  "FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET"
)
```

iOS 예시 (macOS에서만)

```bash
.\run-ios.ps1 -DartDefine @(
  "BACKEND_BASE_URL=http://localhost:3000",
  "KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY",
  "NAVER_CLIENT_ID=YOUR_NAVER_CLIENT_ID",
  "NAVER_CLIENT_SECRET=YOUR_NAVER_CLIENT_SECRET",
  "NAVER_CLIENT_NAME=YOUR_NAVER_CLIENT_NAME",
  "NAVER_URL_SCHEME=YOUR_NAVER_URL_SCHEME",
  "FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY",
  "FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID",
  "FIREBASE_MESSAGING_SENDER_ID=YOUR_FIREBASE_MESSAGING_SENDER_ID",
  "FIREBASE_IOS_APP_ID=YOUR_FIREBASE_IOS_APP_ID",
  "FIREBASE_IOS_BUNDLE_ID=YOUR_FIREBASE_IOS_BUNDLE_ID",
  "FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET"
)
```

### 3) release 모드

- 안드로이드

```bash
.\run-android.ps1 -Release
```

- iOS (macOS)

```bash
.\run-ios.ps1 -Release
```

### 4) 기존 프로세스 정리

- 기본값: 기존 프로세스를 자동 종료하지 않음(안전 모드)
- 필요할 때만 현재 프로젝트 관련 프로세스 정리:

```bash
.\run-web.ps1 -KillExisting
```

### 5) 배치 래퍼 사용

- `run-web.bat`, `run-android.bat`, `run-ios.bat`는 PowerShell 스크립트 래퍼입니다.

```bash
.\run-android.bat -DartDefine "BACKEND_BASE_URL=http://localhost:3000"
```

### 6) 문제 해결(자주 묻는 질문)

- `Target of URI doesn't exist` 오류: import 경로 오류 가능성이 크므로 `run` 스크립트가 참조하는 파일 경로가 최신인지 확인
- 이전 실행이 살아 있는 것처럼 보임: `-KillExisting`로 현재 프로젝트 관련 프로세스만 정리 후 재실행
- 여러 터미널 동시 실행: 권장되지 않음. 새 실행 전 한 터미널에서만 실행
## Firebase push setup (required for real push)

Run with Firebase options:

```bash
flutter run \
  --dart-define=FIREBASE_API_KEY=YOUR_API_KEY \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID \
  --dart-define=FIREBASE_ANDROID_APP_ID=YOUR_ANDROID_APP_ID \
  --dart-define=FIREBASE_IOS_APP_ID=YOUR_IOS_APP_ID \
  --dart-define=FIREBASE_IOS_BUNDLE_ID=YOUR_IOS_BUNDLE_ID
```

Optional:

```bash
--dart-define=FIREBASE_STORAGE_BUCKET=YOUR_STORAGE_BUCKET
```

## Optional backend wiring (new)

If you already have an API server that follows `docs/api_schema.md`, run with:

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:3000
```

- When `BACKEND_BASE_URL` is not set, the app keeps using local `SharedPreferences` data.
- REST client code lives in `lib/backend/rest_backend_api.dart`.
- Fallback policy:
  - Auth (`email sign-up/sign-in`): server-first, and local fallback only for network/server failures.
  - Post/Tip/Resolve actions: server-first, and if server sync fails the app still saves locally.
  - Failed writes are queued in local pending ops and retried automatically on next sign-in/app start.
  - On app start with backend enabled, pending writes are retried first, then remote posts/tips are pulled.
  - `My Activity` app bar has a manual sync button for immediate retry/pull.
  - `Nearby` tab app bar also has a manual sync button for feed refresh.
  - Sync buttons show a red pending indicator when offline queue has unsynced operations.
  - Long-press sync buttons to inspect pending operation list.
  - Pending list sheet supports `retry now` and `clear queue`.
  - Pending list also supports removing a single queued item.
  - Repeated failures increase `retryCount`; jobs are auto-suspended after threshold and can be cleaned separately.
  - Failed jobs set `nextRetryAt` with exponential backoff; early retries are skipped and counted as waiting.
  - Pending sheet supports `전체/활성/중단` filtering.
  - Pending sheet also supports operation type filtering (`등록/수정/해결/제보`).
  - Pending sheet supports sorting (`빠른재시도` / `최근순`).
  - Pending sheet remembers last filter/sort state.
  - Pending sheet supports batch actions on current filter result (`비우기`, `재활성화`).
  - Pending sheet controls are chip-based for quick one-hand filtering/sorting.
  - Pending actions are disabled while a sync/clear task is running.
  - Manual sync now reports summary counts with remaining queue size.
  - Pending sheet has `강제 재시도` with mode selection (`활성 항목만` / `전체(중단 제외)`).
  - Pending item rows can be expanded to inspect payload JSON.
  - Expanded payload supports one-tap copy.
  - Suspended items can be reactivated individually.
  - Failed jobs keep `lastError`/timestamp and surface the reason in the pending list.
  - `My Activity > 제보` now shows reports created by the current user.
  - `My Activity > 저장` now shows bookmarked posts from post detail.
  - Bookmark toggle is available directly on feed/post cards.
  - Post detail share/contact actions now copy ready-to-send text/links to clipboard.
  - Match page empty-state share now copies a ready-to-send text.
  - Owners can now edit title/location/body from post detail.
  - Pending sync queue dedupes repeated post updates/resolves by post id.
  - Pending sheet now has multi-select mode with batch actions (retry selected, reactivate selected suspended items, delete selected).
  - In select mode, you can toggle `current filter select all` or `queue-wide select all`, and selection summary is shown.
  - Selected retry toast now reports selected scope result and both selected/total remaining counts.

