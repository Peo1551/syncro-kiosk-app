# Syncro Kiosk

A shared, locked-down landscape tablet for Syncro Connect. Employees sign in
one at a time (card tap, or clock number + clock PIN), use self-service, and
sign out. Android and iPad.

What an employee can do is the employee app's **My Work** tab and nothing more:
Request Leave, Request History, Upcoming Leave, My Entitlement, My Clocking Hub
(when their mobile app group allows timesheet viewing) and My Flexi (only when
`flexi-summary.php` says `on_flexi: true`). There is no clocking, manager
area, profile, password, passcode, GPS, push or Firebase.

If the employee's group allows signing timesheets and last week (Monday to
Sunday) has sessions awaiting their sign-off, they are asked to confirm those
hours before reaching the home screen.

Only the tablet pairing (token, tablet id, tablet details) is stored, in
secure storage. Employee sessions and data are held in memory and dropped on
sign-out, idle time-out, or when the app goes to the background.

## Where the code came from

- `lib/src/features/` (leave, flexi, timesheets), `lib/src/theme/`,
  `lib/src/core/widgets/app_modal.dart`, `cookie_utils.dart`: copied from the
  employee app (`syncroconnect-app`, branch `feature/flexi`). The feature pages
  in `features/work/employee_workspace.dart` are the My Work pages lifted out of
  its `home_page.dart`.
- `lib/src/kiosk/` pairing flow and recovery, kiosk service (immersive mode,
  landscape lock, wake lock, Android lock task) and card reader rules, plus
  `MainActivity.kt`: from the Visitor Connect tablet app.

## Build

Flutter lives at `~/.local/flutter/bin/flutter`.

```sh
~/.local/flutter/bin/flutter pub get
~/.local/flutter/bin/flutter analyze
~/.local/flutter/bin/flutter test
export JAVA_HOME=$HOME/.local/android-toolchain/jdk ANDROID_HOME=$HOME/.local/android-toolchain/sdk
~/.local/flutter/bin/flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
Release signing is not configured in this repository.

Android application id and iOS bundle id: `com.syncroconnect.kiosk`.
For full lock-down use Android screen pinning / device-owner kiosk mode, or
iPad Guided Access / MDM Single App Mode.

## Server API

The base URL is set in `lib/src/config/app_config.dart`
(`https://syncroconnect.com`). Every request carries `X-Kiosk-Token` once the
tablet is paired.

Tablet endpoints (JSON in, JSON out, failures carry `error` and `code`):

| Endpoint | Use |
|---|---|
| `POST /kiosk/api/pair.php` | 6-digit code → access token and tablet details |
| `POST /kiosk/api/heartbeat.php` | every 60 s and at start; 401 `KIOSK_NOT_PAIRED` wipes the pairing, 403 `KIOSK_UNLICENSED` shows the blocking screen |
| `POST /kiosk/api/admin-pin.php` | opens tablet settings |
| `POST /kiosk/api/unpair.php` | removes the pairing (admin PIN required) |
| `POST /kiosk/api/sign-in.php` | `{card}` or `{clock_number, pin}` → session cookie, CSRF, idle seconds |
| `POST /kiosk/api/sign-out.php` | fire and forget |

Employee endpoints, called the way the employee app calls them (session cookie,
`X-CSRF-Token` on POSTs): `/employee/status-json.php`,
`/employee/api/leave-requests.php`, `/employee/api/holiday-summary.php`,
`/employee/api/upcoming-leave.php`, `/employee/api/timesheets.php`,
`/employee/api/timesheet-approve.php`, `/employee/api/flexi-summary.php`.
A 401, `auth_expired` or `KIOSK_SESSION_ENDED` ends the session on the tablet.
