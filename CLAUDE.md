# UdiStreaks

Flutter habit-streak tracker with an OKR/life-tracker layer and an Android
home-screen widget. Local-only: sqflite, no backend, no accounts.

## Flutter SDK
- Path: `/opt/homebrew/bin/flutter` (Homebrew cask, Flutter 3.44.4 / Dart 3.12.2)
- Run app: `flutter run`
- Get dependencies: `flutter pub get`
- Test: `flutter test` · Analyze: `flutter analyze` (keep both clean)

## Android SDK Configuration
`android/app/build.gradle` inherits the Flutter Gradle defaults rather than
pinning numbers, so these track the SDK version above:
- compileSdk: 36 (`flutter.compileSdkVersion`)
- minSdk: 24 (`flutter.minSdkVersion`)
- targetSdk: 36 (`flutter.targetSdkVersion`)
- Java/Kotlin: VERSION_1_8
- `glance-appwidget` is pinned to 1.1.1 — the open range resolves to an alpha
  needing compileSdk 37.

## Architecture

Dependencies point downward; nothing may import from a layer above it.

```
main.dart          app setup + bottom-nav shell only
habits/  okr/      feature modules: screens, sheets, dialogs
ui/kit.dart        shared design kit (spacing, sheets, dialogs, charts)
db_helper.dart     all persistence — schema, migrations, CRUD
core/ + *_rules/scoring/rollup/period    pure domain logic
```

**Nothing computed is ever stored.** Streaks, KR scores, pace and rollups are
folded from the log on every read. Those rules live in pure functions that take
their inputs explicitly (including `now`), so they are unit tested without a
database — `habits/streak_rules.dart`, `okr/scoring.dart`, `okr/rollup.dart`,
`okr/period.dart`, `core/dates.dart`. Don't add a `score` or `streak` column,
and don't recompute a rule inline in a widget.

## Conventions

- Rows are raw `Map<String, dynamic>`, sometimes merged with computed fields
  (`{...kr, ...computeKr(kr)}`). No model layer — column names are the map keys.
- State is plain `setState`; each screen has a `_load()` that queries
  `DBHelper()` (a singleton) and refreshes after a push.
- Spacing comes from `ui/kit.dart` (`kGapXs`=4 … `kGapXl`=24). Reuse
  `showActionSheet`, `confirmDelete`, `pickEmoji`, `InlineAddField`, `ScoreBar`.

## Schema

Version 3, ten tables. `areas → objectives → key_results` is intent;
`executions → measurements` is doing; `reviews` holds quarterly grades.
`executions` and `trackables` exist but have no CRUD yet — leave them.
New migrations go in `_onUpgrade` behind `if (oldVersion < N)`.

## Keeping this file current

Update it in the same change that makes it stale: a new top-level `lib/`
directory or layering change, a schema/version bump, an SDK upgrade, or a new
command. Treat a wrong statement here as a bug and fix it in passing.
