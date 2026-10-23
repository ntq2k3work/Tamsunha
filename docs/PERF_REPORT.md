# Tường Nhỏ performance and device acceptance

**Status:** NOT RUN — no Flutter/Dart SDK, generated mobile runner, Android SDK/ADB, emulator, or physical test device is available in the current workspace. No frame, memory, battery, or accessibility measurements are claimed.

## Required run before G1/G4 can pass

On a clean machine with Flutter stable 3.47+ and the local Laravel API/MySQL environment configured:

1. Generate Android/iOS runners, resolve dependencies, then pass `dart format`, `flutter analyze`, `flutter test`, and an Android debug build.
2. On a lower-tier and a current Android device, capture a 10-minute profile run with 10k notes and record device model, OS, build mode, viewport/zoom, Flutter/Flame version, p50/p95 frame time, jank count, and memory at 0/5/10 minutes.
3. Exercise four-direction pan, anchored pinch at each viewport edge, note open/close/system Back for 30 cycles, placement collision, tile changes, keyboard/safe-area, offline/reconnect, and app pause/resume.
4. Verify reduced motion removes perpetual motion, text scaling, TalkBack labels/order, at least 44dp interactive targets, empty/error states, and that no wall sprite exposes note text or identity.
5. Capture screenshots/video for two viewport sizes. Run a separate iOS QA pass on macOS/Xcode before iOS release.

| Measure | Result |
|---|---|
| Android profile / frame time | NOT RUN |
| Android memory over 10 minutes | NOT RUN |
| Android interaction / accessibility | NOT RUN |
| iOS build / device QA | NOT RUN |
| Evidence attachments | None captured |

Do not mark G1 or G4 passed until a device owner replaces the NOT RUN entries with measured evidence and resolves any release-blocking findings.
