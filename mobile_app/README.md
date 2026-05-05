# Mobile App (`/mobile_app`)

This Flutter application is the trial-facing client for MeMoSA Clinical Trial. It supports role-based workflows for Study Coordinators, Clinicians, and Admins while integrating securely with Firebase and backend APIs.

## User Personas and UX Flows

### Study Coordinator

Primary responsibilities:

- create and maintain case drafts,
- capture/upload required lesion images,
- submit complete case data,
- update case records with additional reference information.

Typical flow:

1. Login.
2. Open **Draft Cases** to create/edit in-progress submissions.
3. Submit case through backend (`/dbmanager/case/create`), which triggers AI processing.
4. Use **Browse Cases** and **Edit Case** for ongoing curation and ground-truth updates.

### Clinician

Primary responsibilities:

- review pending cases assigned for diagnosis,
- submit lesion-level clinical assessments.

Typical flow:

1. Login.
2. Open **Undiagnosed Cases**.
3. Review case material and submit diagnosis payload (`/dbmanager/case/diagnose`).

### Admin

Primary responsibilities:

- control user access (invite codes and user lifecycle),
- export Human-vs-AI bundles for trial reporting.

Typical flow:

1. Login.
2. Manage invite codes and user records.
3. Trigger **Export Bundle** and securely share package/password with authorized analysis stakeholders.

## Application Architecture

| Layer             | Key Files                                           | Responsibility                                                              |
| ----------------- | --------------------------------------------------- | --------------------------------------------------------------------------- |
| Entry             | `lib/main.dart`, `lib/features/auth/auth_gate.dart` | App startup, Firebase init, route bootstrap, persisted session check.       |
| Auth              | `lib/core/services/auth.dart`                       | Firebase login/register/forgot password and backend auth route integration. |
| Case API          | `lib/core/services/dbmanager.dart`                  | Case create/read/edit/list, clinician diagnosis, admin export API calls.    |
| Storage           | `lib/core/services/storage.dart`                    | Upload/download encrypted payload blobs via Firebase Storage URLs.          |
| Role UI           | `lib/features/roles/**`                             | Role-specific screens for coordinator, clinician, and admin workflows.      |
| Local Persistence | `shared_preferences` + draft services               | Session and draft metadata persistence.                                     |

## Setup

This repository uses **Flutter**.

### 1) Prerequisites

- Flutter SDK (matching project constraints; Dart SDK `^3.8.1`)
- Android Studio/Xcode toolchains as needed
- Firebase project configuration for this app

### 2) Install dependencies

```bash
cd mobile_app
flutter pub get
```

### 3) Environment configuration

- Copy/create `mobile_app/.env` from project standards.
- Ensure backend URL and encryption settings match your deployed/local backend.
- Confirm Firebase configuration files are present and valid for your target platform.

### 4) Run app

```bash
flutter run
```

For emulator-local backend development, current service defaults use `http://10.0.2.2:8000`.

## State Management and Data Sync

The app uses a **service-driven state model** (without Redux/BLoC libraries):

- UI screens trigger async operations through service classes (`AuthService`, `DbManagerService`, `StorageService`).
- Authentication state is persisted via `shared_preferences` and restored by `AuthGate`.
- Case operations are API-driven and role-gated by backend token verification.
- Large crypto/parsing tasks use async/background patterns to keep UI responsive.

Real-time behavior in practice:

- Data is synchronized through explicit API fetches and submits (request/response model).
- Firebase Authentication provides live session identity, while Firestore/Storage are accessed through backend-mediated workflows for trial data integrity.

## Tech Stack

| Area             | Technology                          | Role                                                |
| ---------------- | ----------------------------------- | --------------------------------------------------- |
| Framework        | Flutter, Dart                       | Cross-platform clinical trial mobile client.        |
| Auth             | Firebase Authentication             | User login, token issuance, password reset.         |
| File Storage     | Firebase Storage                    | Encrypted blob/object upload and retrieval.         |
| Networking       | `http` package                      | REST communication with FastAPI backend.            |
| Local Storage    | `shared_preferences`                | Session persistence and lightweight local settings. |
| Crypto/Utilities | `pointycastle`, custom crypto utils | Client-side encryption and key handling.            |

## Build and Release

### Android APK / App Bundle

```bash
cd mobile_app
flutter clean
flutter pub get
flutter build apk --release
# or
flutter build appbundle --release
```

Output examples:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

### Android Keystore Setup (Production Signing)

Generate production keystore (`.jks`) once and store it securely:

```bash
keytool -genkeypair -v \
  -keystore android/app/memosa-release-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias memosa_release
```

Create `android/key.properties`:

```properties
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=memosa_release
storeFile=app/memosa-release-key.jks
```

Then ensure `android/app/build.gradle.kts` (or Gradle signing config) references `key.properties` for release signing.

Security reminders:

- Never commit raw keystore passwords to git.
- Keep `.jks` backup in approved secure storage (team vault).
- Restrict access to release signing assets to release maintainers.

### iOS IPA, macOS only (Future development)

```bash
cd mobile_app
flutter clean
flutter pub get
flutter build ios --release
```

Then archive/sign in Xcode:

1. Open `ios/Runner.xcworkspace`.
2. Configure signing/team/profile.
3. Archive and export IPA for test distribution.

## Firebase Client Keys for Project Migration

When migrating the app to the CRMY Firebase project, replace platform client config files before building release artifacts.

### Android

1. Download the new `google-services.json` from the CRMY Firebase project.
2. Replace `mobile_app/android/app/google-services.json`.
3. Re-run:

```bash
flutter clean
flutter pub get
```

### iOS (when enabled)

- Replace `GoogleService-Info.plist` in `ios/Runner/` with the CRMY project version.

Validation checklist after replacement:

- Login works against the correct Firebase project.
- Registration/invite flow uses CRMY backend + Firebase resources.
- Storage uploads resolve to CRMY bucket.

## Testing and Quality Checks

```bash
flutter analyze
flutter test
```

## Useful Development Commands

```bash
flutter doctor
flutter devices
flutter run
adb devices
```

## Directory Overview

```text
mobile_app/
├── lib/
│   ├── core/
│   │   ├── models/
│   │   ├── services/
│   │   └── utils/
│   ├── features/
│   │   ├── auth/
│   │   └── roles/
│   └── main.dart
├── android/
├── ios/
├── pubspec.yaml
└── README.md
```
