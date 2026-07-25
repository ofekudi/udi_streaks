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

The OKR tab is **one screen**: `okr/okr_tree.dart` renders areas → objectives →
key results as an indented accordion. Areas are headings, not destinations;
objectives are the only expand/collapse level. There is no per-area or
per-objective screen — entity actions live on long-press (`showActionSheet`),
including adding a child ("Add objective" on an area, "Add key result" on an
objective), so no row carries a permanent add affordance. `InlineAddField`
survives only for "Add area", once, at the bottom of the list.

An objective with **exactly one key result collapses into a single row**
(`_mergedRow`) titled with the *key result* — the objective title and the KR
title otherwise say the same thing twice over five rows. It's presentation only:
the objective still exists, still rolls up, still gets graded at quarter close,
and its long-press sheet carries both entities' actions. Adding a second key
result unfolds it back into a chevron row with children, for free.
Every row is at most two lines — title, then a `ScoreBar` — and the only number
in the tree is a key result's `X / Y`, in a right-hand column beside both lines
so the title keeps its own line. Objectives and areas show their rollup as the
bar alone; `fmtScore` is only used by the quarter-close screen.
Only leaf pages push: `KrDetailScreen`, `KrEditScreen`,
`QuarterCloseScreen`, and `okr/record_screen.dart` (the "Record" FAB — a flat,
most-recently-logged-first capture list). Measurement writes go through
`okr/log_value.dart` so the Record page and KR detail can't drift apart.

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
  `DBHelper()` (a singleton) and refreshes after a push. UI-only state (which
  objectives are collapsed, which Record row is open) lives in `setState` and is
  never persisted.
- Spacing comes from `ui/kit.dart` (`kGapXs`=4 … `kGapXl`=24). Reuse
  `showActionSheet`, `confirmDelete`, `promptText`, `pickEmoji`,
  `InlineAddField`, `ScoreBar`.

## Schema

Version 5, ten tables. `areas → objectives → key_results` is intent;
`executions → measurements` is doing; `reviews` holds quarterly grades.
`executions` and `trackables` exist but have no CRUD yet — leave them.
`key_results.target_raw`, `key_results.baseline_raw` and `measurements.note`
hold the notation the user typed ("3x10"); it's input, not a computed value —
display it wherever a target, a starting point or an entry is *stated*, but
every comparison runs on the parsed number. `currentLabel` / `targetLabel` in
`okr/log_value.dart` are how rows render it, so `3x10 / 3x12 reps` is what the
tree shows; with nothing logged `currentLabel` reads as the baseline, because
that is where the key result stands.

`key_results.baseline_value` is where a KR started. When set, `scoreFor`
measures `(current - baseline) / (target - baseline)`, so `3x10 → 3x12` reads 0%
at 3x10 instead of 83%, and the sign of `target - baseline` carries the
direction (`wantsDown`) — the `direction` column only matters without a
baseline. Offered on `LATEST` key results only: `SUM` and `COUNT` restart at
zero each quarter by definition. `renewObjective` seeds the next quarter's
baseline from the KR's last entry, so progressive goals need no rebuilding.
New migrations go in `_onUpgrade` behind `if (oldVersion < N)`.

## Keeping this file current

Update it in the same change that makes it stale: a new top-level `lib/`
directory or layering change, a schema/version bump, an SDK upgrade, or a new
command. Treat a wrong statement here as a bug and fix it in passing.
