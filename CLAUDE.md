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
key results as an accordion. Areas are headings, not destinations;
objectives are the only expand/collapse level. There is no per-area or
per-objective screen — entity actions live on long-press (`showActionSheet`),
including adding a child ("Add objective" on an area, "Add key result" on an
objective), so no row carries a permanent add affordance. `InlineAddField`
survives at the bottom of a list, once per tab: "Add area" on the OKR tree and
"Add streak" on the habits list (where the picked emoji is prefixed onto the
name — habits have no icon column).

Every level can be **reordered**, and **a row reorders its children, never its
siblings** — "Reorder objectives" is on the area, "Reorder key results" on the
objective, and "Reorder areas" in the tab's overflow menu, an area's parent
being the tab. That is one entry per list instead of the same entry repeated on
every row of a level, where it read as a property of the row. It is offered only
once the list has two rows in it, and opens `showReorderSheet` (`ui/kit.dart`), a
drag-handle list of that one level — the tree itself carries no drag affordance.
It writes `sort_order`, which every tree query already ordered by: a reorder
renumbers the list 0..n-1 in one transaction (`reorderAreas` /
`reorderObjectives` / `reorderKeyResults`), and inserts take `MAX(sort_order)+1`
among their siblings so a new row lands last instead of tying at 0 and surfacing
mid-list. With the archive hidden, a reorder renumbers only the visible
objectives — accepted; archived rows are an edge state.
`test/reorder_test.dart` covers the round trip.

Every row is two lines: a title, and a `ScoreBar` spanning the full width of the
card beneath it. A key result's `X / Y` shares the *first* line with its title,
right-aligned — which is what lets its bar be as long as its objective's, so two
bars on the same 0..1 scale can be compared by eye instead of ending at
different arbitrary places. An area heading, having no bar, states its rollup as
`fmtPct` on the right of its label; `fmtScore` (a raw 0..1) stays
quarter-close-only. Those rows live in `okr/rows.dart`: `KrValueCell` is the
`X / Y` cell, `KrSummaryRow` is the whole row — which is how `KrDetailScreen`
opens, the same shape the tree row you tapped had, so the number can't read
differently on the two screens (**restructure one and you must restructure the
other**) — and `AreaHeading` is the heading the tree and the Record page share,
gestureless, so each caller wraps it in its own. The tree passes `KrValueCell` a
narrower `maxWidth` than the detail screen's default; it scales the text down
rather than wrapping.

**Hierarchy comes from containment, never from horizontal offset.** An objective
and its key results are one card — `AppCard` (`ui/kit.dart`):
`surfaceContainerLow` at `kRadiusCard`, elevation 0, an `outlineVariant` border,
and `deeper: true` for a tone deeper at `surfaceContainer` once archived — *not*
`surfaceContainerLowest`, which is pure white and glows against the page. It's in
the kit rather than the tree because the Record pages build the same card, and
two copies would drift. Every row starts on one edge — `kGapSm` of page padding plus
`kGapMd` of card padding — so nothing is indented and, crucially, **no child sits
left of its parent**. That was the bug: a *leading* chevron took 24dp and pushed
an objective's own title in to 32 while its key results stayed at 4. The chevron
is trailing now, and it needs no tap target of its own because the whole header
toggles. Indenting the children instead was tried and reverted — it left 136dp of
title on a 360dp phone. Don't reintroduce a level indent or a leading chevron;
the card and the type weights (objective `titleSmall` w700, key result
`bodyMedium` w600) already say what an indent would.
`test/okr_tree_layout_test.dart` pins the shared edge.

The card is **ruled**, by `AppRule` (`ui/kit.dart`): under each area heading,
between an objective's own summary and its children, and between every pair of
key-result rows. The fill and the two-line rhythm were not enough on a real
screen — a card only a tone off the page had an ambiguous edge, and a row's title
sits 8dp above its own bar but only 16dp below the previous row's, so a bar read
as easily upward as downward. Proximity can't carry that at a 2:1 ratio; the
rules can.

Only leaf pages push: `KrDetailScreen`, `KrEditScreen`, `QuarterCloseScreen`, and
the two Record pages below. Both tabs carry the "Record" FAB; backing out of it
lands on the OKR tab with the last-logged key result's objective expanded
(`RecordScreen.onLogged` → `GoalsTabState.reveal`), and stays put when nothing was
logged. Measurement writes go through `okr/log_value.dart` so every logging
surface stays in step — the one exception is `DBHelper._insertCompletion`, below.

**Recording is two steps, because filling is objective-scoped.** A workout is
every key result under one objective, not rows scattered through everything.
`okr/record_screen.dart` is the picker — area headings and one `AppCard` per
objective, `getAreasWithRollup` order throughout, so it reads as the same outline
as the tree and honours the same Reorder choices. `okr/record_objective.dart` is
the fill page: that objective's key results in one ruled card, each the tree's own
two-line row with a value field on the bar's line, and one `Log N` bar (or the
keyboard's done key) writing every filled field through `logKrValue`. Text lives
in a `Map<String, TextEditingController>` keyed by id, for the visit only.

A flat, recency-ordered list came first and was wrong: every row had to repeat its
objective in a subtitle *beside* a bar *beside* a field, which wrapped into three
cramped lines. Knowing the objective is what buys the space back. `byRecency` went
with it — you can't group by area and sort by recency, and the grouping is what
makes the page navigable, which is also why there's no search box.

Five things hold the fill page together and shouldn't be undone piecemeal:

- **A blank field is a key result you didn't do**, which is why there's no
  selection step. A field whose text won't parse keeps it, so one bad entry
  doesn't cost the rest of the pass.
- **Each row states value *and* progress**, via `KrValueCell` and `ScoreBar` —
  choosing what to fill has to be possible without leaving the page. The field
  carries no unit and no hint of its own — `80 / 90 kg` sits directly above it, so
  repeating either only cost width — and where the two compete for the row, the
  number gives: `KrValueCell(dense: true)` drops it to `bodySmall`, matching the
  `DeltaText` under it, so the field stays comfortably tappable.
- **A `COUNT` keeps its one-tap `+1` and gets no field.** `aggregateValues` counts
  *rows*, so a "3" typed into a COUNT would write one row worth 3 and score as 1.
  A tally's unit of record is one occurrence.
- **Leaving with text in a field asks first** (`PopScope` + `confirmDiscard`).
  Committing is already reversible — any measurement can be deleted from its
  entry — so the guard exists for the typing, not the writes. Nothing is
  persisted: no draft outlives the visit.
- **An objective with no key results is absent from the picker**, and an area
  whose objectives all drop out loses its heading. There's nothing to record in
  one, so offering it would be a dead end.

`test/record_multi_test.dart` walks both steps and pins all five.

`KrDetailScreen` **states the number, shows the history, and records into it**.
Its history is one list with no view switch: `byPeriodDesc` (`okr/period.dart`)
buckets entries into quarters, and each quarter heading carries the total and the
grade the by-quarter view used to show. The sparkline plots `trendSeries`
(`okr/scoring.dart`), a running total for `SUM` and `COUNT` — a COUNT's raw
values are all 1 and would draw a flat line.

It carries the same "Record" FAB as the OKR tab, scoped to the one key result,
and splits the same two ways the Record page's rows do: a `COUNT` is a one-tap
`bumpKr`, anything else asks for a value through `promptLogValue` (`ui/kit.dart`)
and writes it with `logKrValue`. The FAB is the only logging affordance here —
the old inline form is gone — but both surfaces still go through
`okr/log_value.dart`, which is what keeps them from drifting.

Long-pressing an entry deletes it, the same `showActionSheet` idiom as every
other row. `deleteMeasurement` is the only way a measurement is removed
deliberately, and an entry a habit produced is removed by deleting *that
completion* so the cascade takes the count — the tick and the count are one fact,
and the sheet's label says the habit gets un-ticked rather than reporting it
after. It returns whether a completion went with it.

**Anything recorded can be un-recorded**, since nothing here is worth keeping by
accident. Long-press deletes an OKR entry (above), and a day in
`HabitHistoryDialog` — `deleteCompletionOn` takes it by date, because a
completion *is* a day: both write paths refuse a second one for the same day.
That dialog is the only way to reach a day that isn't today; the tile's toggle
can't. An archived objective can be reopened from its long-press sheet, which is
also where "Close quarter" is *withheld* once archived — closing clones into the
next quarter, so offering it twice would mint a second copy.

`reviews` has no foreign key, deliberately: a grade has to outlive the objective
`renewObjective` archives. That means nothing reclaims a grade when its subject is
genuinely deleted, so `_deleteReviewsUnder` does, running before the parent delete
while the subtree is still there to find. Add a level to the hierarchy and it
needs a branch there.

**Nothing exports.** There is no backup, no import, and no share — with no
account and no backend, the database on the phone is the only copy. A clipboard
JSON dump (`exportAll` / `exportedTables`) existed and was removed as more menu
than it earned; the OKR tab's overflow menu holds only the archived toggle and
"Reorder areas".

A habit can **feed a COUNT key result**: ticking the habit also counts there.
The link is offered on the habit side only — `habit_detail_sheet.dart` gains
"Link to OKR" / "Unlink from …" and `habits/link_kr_sheet.dart` is the picker.
The OKR tab shows no sign of it and needs none; a linked key result just
receives measurements from a second source. Don't add an affordance for it
there. Habits still import nothing from `okr/` — they reach the OKR tables
through `DBHelper`, which sits below both. That is also why the habits tab's
"Record" FAB is an injected callback: `RootNav` brokers the push and the
landing, since `main.dart` sits above both modules.

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
  `DBHelper()` (a singleton) and refreshes after a push. The three tab roots
  name theirs `reload()`, public, because `RootNav` calls it on the tab being
  entered — the `IndexedStack` keeps sibling tabs alive across writes, so tab
  entry is what reloads them (`test/tab_reload_test.dart` pins this). UI-only
  state (which Record row is open, whether archived objectives show) lives in
  `setState` and is never persisted — except which objectives are collapsed,
  which is `objectives.collapsed` so the tree reopens the way it was left.
- Spacing comes from `ui/kit.dart` (`kGapXs`=4 … `kGapXl`=24). Reuse
  `showActionSheet`, `confirmDelete`, `promptText`, `pickEmoji`, `EmojiWell`,
  `InlineAddField`, `ScoreBar`. A row carrying both an emoji and a name edits
  them in one action: `promptNameAndEmoji` is `promptText` with an `EmojiWell`
  beside the field, which is what an area's "Edit" opens, writing both in one
  `updateArea` call. Two menu entries for one edit is what it replaced.
- `ScoreBar` takes its colour from the scheme — `primary`, or `tertiary` for a
  key result that wants its number to go *down* — so it holds contrast on any
  surface, and a dark theme would need nothing. It is otherwise pure colour, so
  pass it a `label`: that plus its percentage is all a screen reader gets.

## Schema

Version 7, ten tables. `areas → objectives → key_results` is intent;
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

`objectives.collapsed` is the accordion's fold state — user input, not a
computed value, which is why it doesn't break the rule above. Its setter
(`setObjectiveCollapsed`) skips `updated_at`: folding a row isn't an edit. One
row at a time is all there is — expand-all and collapse-all were removed along
with the bulk setter. The default 0 is what keeps a new or renewed objective
expanded; `okr_tree.dart` seeds its `_collapsed` set from the rows on every
`_load()`, so archived-but-hidden objectives keep their state in the DB.

`key_results.habit_id` is the habit → COUNT key result link, at most one habit
per KR and one KR per habit. Every path that completes a habit goes through
`DBHelper._insertCompletion`, which writes the completion *and* mirrors it as one
measurement tagged `measurements.habit_completion_id`. That tag is the whole undo
story: the FK cascades, so un-ticking a habit or deleting one takes its counts
back off the key result with no code to run. Two consequences to preserve —
mirror straight to `key_result_id` (`logKrValue` would route a trackable-backed
KR somewhere `computeKr` can't see), and `renewObjective` clears `habit_id` on
the archived copy so the link doesn't end up claimed at both ends.

Because the migrations and these cascades are SQLite behaviour rather than pure
rules, they are tested against a real database via `sqflite_common_ffi` and
`DBHelper.openAt` — see `test/habit_okr_link_test.dart` and the
`*_migration_test.dart` files, which declare the pre-migration schema
verbatim because `_onCreate` always builds the current one.

## Keeping this file current

Update it in the same change that makes it stale: a new top-level `lib/`
directory or layering change, a schema/version bump, an SDK upgrade, or a new
command. Treat a wrong statement here as a bug and fix it in passing.
