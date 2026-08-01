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
main.dart          app setup + bottom-nav shell only (two tabs: Habits, OKR)
habits/  okr/      feature modules: screens, sheets, dialogs
ui/kit.dart        shared design kit (widgets: cards, sheets, dialogs, charts)
ui/theme.dart      buildAppTheme() — the ColorScheme and every component theme
ui/tokens.dart     colour, spacing, radius, type and motion consts
db_helper.dart     all persistence — schema, migrations, CRUD
core/ + *_rules/scoring/rollup/period    pure domain logic
```

`ui/tokens.dart` is plain top-level `const`s and **not** a `ThemeExtension`,
because five widget tests pump a bare `MaterialApp` with no theme, where an
extension lookup would throw. Light-only is what licenses literal colours: with
no second brightness to derive, a semantic value can just *be* a colour instead
of being squeezed into whichever `ColorScheme` role nearly fits. `kit.dart`
re-exports it, so a screen needs one import to build a row.

Colour carries **four meanings**, and adding a fifth needs a reason: `kAccent`
teal is progress, done, and a delta going the right way; `kCaution` amber is at
risk, skipped, or a delta going backwards; `kDanger` red is destructive or a
broken streak; `kDown` blue marks only the "lower is better" side of the
direction toggle in `KrEditScreen`, the one control whose subject *is* direction.
`theme.dart`
also maps these onto the scheme roles the kit reads (`primary`, `tertiary`,
`error`, the `surfaceContainer*` set, `outlineVariant`), so a widget still on a
`Theme.of(context)` lookup lands on the right colour anyway. Don't reach for a
`Colors.*` swatch — that is what left orange meaning "skipped", "at risk" *and*
"streak flame" on one habit row.

Component themes are not decoration: they are how a bare `showModalBottomSheet`,
`AlertDialog` or `TextField` gets the same chrome as its dressed-up sibling.
`bottomSheetTheme` is why the action and reorder sheets have `showAppSheet`'s
rounded top and drag handle without repeating it, and `inputDecorationTheme` is
why every field is filled at `kRadiusField` — a filled field reads as somewhere
to type, which an outlined box the colour of the card does not. `appBarTheme`
paints the bar `kPage` and closes it with a hairline, so **no screen sets its own
`backgroundColor`**; three once set `inversePrimary`, the Flutter template's
lavender, and fought it.

Type is the **system font** throughout — no font asset, no `google_fonts`.
Precision comes from weight, size, tracking, and `FontFeature.tabularFigures()`
on every number, without which a value column reflows each time a digit changes
width. The tree's three levels are a real ramp — area `kTypeAreaLabel` 11 faint
caps, objective `kTypeObjective` 15, key result `kTypeKr` 14 — where they were
once all 14sp separated only by weight. An area label is the *smallest* thing in
the tree on purpose: it marks a section, it isn't the subject of one.

Motion is subtle and short (`kDurFast` 120 … `kDurSlow` 260, all on `kCurve`).
Every animated widget takes its duration from `motion(context, …)`, so honouring
reduce-motion is one call rather than a convention to remember. That covers the
accordion, the chevron, `ScoreBar` growing to value, `Sparkline` drawing itself
in, and the habit tick.

The OKR tab is **one screen**: `okr/okr_tree.dart` renders areas → objectives →
key results as an accordion. Areas are headings, not destinations;
objectives are the only expand/collapse level. There is no per-area or
per-objective screen — entity actions live on long-press (`showActionSheet`),
including adding a child ("Add objective" on an area, "Add key result" on an
objective), so no row carries a permanent add affordance. `InlineAddField`
survives at the bottom of a list, once per tab: "Add area" on the OKR tree and
"Add streak" on the habits list (where the picked emoji is prefixed onto the
name — habits have no icon column).

Both tabs now speak one visual language: the habits list is **one `AppCard`
ruled between habits**, the same containment an objective and its key results
get, and it uses the kit's type set rather than raw `TextStyle(fontSize: …)`.
Both also have a loading state, an empty state and pull-to-refresh — the habits
tab had none of the three, which is why `_select` in `main.dart` can say
re-tapping the open tab is covered by pull-to-refresh and be telling the truth.

The habit tick (`HabitCheck`) is the app's one core gesture, so it is the one
place with a haptic: it fires `HapticFeedback.selectionClick()`, animates its
fill, and **paints optimistically** — the row flips under the finger while the
write and reload settle behind it. It is a filled box with a check, not an
`IconButton`, and the streak number beside it is the loudest thing on the row at
`kTypeNumber` 15. It used to be 14sp, exactly the size of the habit's name, in an
app named after streaks.

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
`fmtPct` on the right of its label; `fmtScore` (a raw 0..1) belongs to the
close flow's score step alone, where the number is the thing being graded
against rather than a rollup being read. Those rows live in `okr/rows.dart`: `KrValueCell` is the
`X / Y` cell, `KrSummaryRow` is the whole row — which is how `KrDetailScreen`
opens, the same shape the tree row you tapped had, so the number can't read
differently on the two screens (**restructure one and you must restructure the
other**) — and `AreaHeading` is the heading the tree and the Record page share,
gestureless, so each caller wraps it in its own. The tree passes `KrValueCell` a
narrower `maxWidth` than the detail screen's default; it scales the text down
rather than wrapping.

Two things hold those rows together. A bar's **height** says which level it
measures — `kBarThick` on an objective, `kBarThin` on a key result — while its
**length is deliberately identical**, since length is what makes two scores on one
0..1 scale comparable by eye. Don't "fix" the heights back: at one weight a
rollup and a leaf metric were pixel-identical, and only a hairline said which was
which. And a value cell is sized to the title beside it (15/15 on the detail
screen, 14/14 in the tree, 14/13 when `dense`), which is what puts the two on one
baseline — a `FittedBox` reports no baseline for `CrossAxisAlignment.baseline` to
use, so equal sizes are the only alignment available. Inside the cell the current
value is loud (`kTypeNumber`) and `/ target unit` recedes (`kTypeUnit`); it is one
`Text.rich` rather than sibling `Text`s so `find.text('1 / 20')` still matches.

**Every bar is one colour filling one direction, always 0..100.** `scoreFor` has
already folded direction into the fraction — "84kg heading for 78" is a portion
of the distance covered — so the bar has nothing left to say about which way the
number moves, and a bar that changed colour or grew from the other end only
raised the question of how to read it. A pace tick marking how far through the
quarter you are was tried here and removed for the same reason: one bar readable
in two directions is one too many. The quarter's elapsed percent stays in the app
bar, stated once.

**Hierarchy comes from containment, never from horizontal offset.** An objective
and its key results are one card — `AppCard` (`ui/kit.dart`): `kCard` white at
`kRadiusCard`, a `kHairline` border, one 4%-ink micro-shadow, and `deeper: true`
for `kCardDeep` and no shadow once archived. Pure white was once rejected here as
"glowing against the page", and that was true only while the page was itself
near-white; against `kPage` the white is what makes the card an object. Its
hairline is a **`foregroundDecoration`**, not a border in `decoration` — a border
there insets the child by its width, and that one pixel pushes an objective's
title off the edge its area heading and key results share
(`test/okr_tree_layout_test.dart` catches exactly this). It's in the kit rather
than the tree because the Record pages and the habits list build the same card,
and copies would drift. Every row starts on one edge — `kGapSm` of page padding plus
`kGapMd` of card padding — so nothing is indented and, crucially, **no child sits
left of its parent**. That was the bug: a *leading* chevron took 24dp and pushed
an objective's own title in to 32 while its key results stayed at 4. The chevron
is trailing now, and it needs no tap target of its own because the whole header
toggles. Indenting the children instead was tried and reverted — it left 136dp of
title on a 360dp phone. Don't reintroduce a level indent or a leading chevron;
the card and the type ramp already say what an indent would.
`test/okr_tree_layout_test.dart` pins the shared edge.

The card is **ruled**, by `AppRule` (`ui/kit.dart`): between an objective's own
summary and its children, between every pair of key-result rows, and between
habits. The fill and the two-line rhythm were not enough on a real screen — a card
only a tone off the page had an ambiguous edge, and a row's title sits 8dp above
its own bar but only 16dp below the previous row's, so a bar read as easily
upward as downward. Proximity can't carry that at a 2:1 ratio; the rules can.
`AppRule.flush()` is the same line without the inset, for a rule that closes a
page section (an area heading, a quarter heading) rather than parting two rows of
one card. **Those two are the only dividers in the app** — there were four, one of
them a hand-rolled `Divider(indent: 72)` in the habits list that was also
misaligned, since that text column started at 80.

Only leaf pages push: `KrDetailScreen`, `KrEditScreen`, `ClosePeriodScreen`,
`PastPeriodsScreen`, `PeriodReportScreen`, and the two Record pages below. Both tabs carry the "Record" FAB; backing out of it
lands on the OKR tab with the last-logged key result's objective expanded
(`RecordScreen.onLogged` → `GoalsTabState.reveal`), and stays put when nothing was
logged. Measurement writes go through `okr/log_value.dart` so every logging
surface stays in step — the one exception is `DBHelper._insertCompletion`, below.

**Recording is two steps, because filling is objective-scoped.** A workout is
every key result under one objective, not rows scattered through everything.
`okr/record_screen.dart` is the picker — area headings and one `AppCard` per
objective, `getAreasWithRollup` order throughout, so it reads as the same outline
as the tree and honours the same Reorder choices. Each states how much it holds
as `N KR`, abbreviated because it sits beside a title that deserves the width.
`okr/record_objective.dart` is the fill page: that objective's key results in one
ruled card, each the tree's own two-line row with a value field beside it, and one
`Log N` bar (or the keyboard's done key) writing every filled field through
`logKrValue`. Text lives in a `Map<String, TextEditingController>` keyed by id,
for the visit only.

A row is **two lines that end on one right edge**: the title over the bar it
measures, the value over the field that changes it.

```
Bench press                 3x10 / 3x12 reps
▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░              [      ]
```

Two rows, not two columns, because the value and the field want different
widths. The value needs `_kValueWidth` for a number carrying both a target and a
unit — scaled down to fit, it stops being readable, which is the one thing a page
for reading numbers can't do to them — while what gets *typed* is short, so the
field takes `_kFieldWidth` and the difference goes to the bar. Sizing the two
together forces one of them wrong. `test/record_multi_test.dart` pins the shared
right edge, that the value is the wider of the two, and that the bar outweighs
the field.

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
  carries no unit and no hint of its own: `80 / 90 kg` sits directly above it, so
  repeating either only cost width, and its `kField` fill is what says it takes
  input. `KrValueCell(dense: true)` keeps the number a step down from the tree's,
  so the field below stays the tappable half of the column.
- **A `COUNT` keeps its one-tap `+1` and gets no field.** `aggregateValues` counts
  *rows*, so a "3" typed into a COUNT would write one row worth 3 and score as 1.
  A tally's unit of record is one occurrence. The `+1` is a filled button the same
  width as the field it stands in for, so the column keeps one right edge, and its
  label is *text* — as a round `IconButton` with a `+1` tooltip, the only thing
  naming it was invisible to a touch screen and misread by a screen reader.
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
can't. An objective can be archived from its long-press sheet, and an archived
one reopened from the same place.

**Closing a period is one guided flow, not twelve separate acts.**
`okr/close_period.dart` runs off the OKR tab's overflow menu and walks three
steps — **score**, **carry**, **close** — with the step named in the app bar
rather than numbered, and `Score · Carry · Close` stated above it. Grading and
renewing used to live on each objective's long-press sheet, which meant nothing
recorded that the quarter itself was over and a half-finished close was
invisible.

One **objective** per card, not one key result. The objective is the level that
carries both a decision and a grade of its own, a full tree is a dozen of them
against three dozen key results, and it is the grain Record already fills at.
The score step asks 1–10 on every key result and on the objective — not a second
completeness number, which the bar beside it already gives, but how well the
thing was *run*. The carry step offers exactly three answers: carry, carry with
adjusted targets, or don't. `DBHelper.renewObjective` takes `dropKeyResults` and
`newTargets` for the middle one; with neither it is the plain renewal it always
was. A target field cleared to blank drops that key result, and clearing all of
them says so instead of cloning an empty shell.

**Every tap writes.** A grade upserts the moment it is set, a carry decision runs
the moment its button is pressed. That is what makes resuming free: re-entering
finds its grades in `reviews` and a carry queue holding only objectives still
active, with no draft stored anywhere. It is also why the flow has *no* discard
guard, unlike `RecordObjectiveScreen` — the sole exception is the adjust-targets
panel, which holds typed text until its button commits and so reuses
`confirmDiscard`. Scoring is re-runnable, from "Score again" on a period's
report; **carrying is not**, because a second pass would clone every objective
again. `test/close_period_test.dart` walks all three steps and pins every one
of these.

`okr/period_report.dart` is the way back: `PastPeriodsScreen` lists the closed
quarters, `PeriodReportScreen` shows one as the same outline the tab has. An
objective's period comes from its `start_date`, so `getPeriodTree` reconstructs
a finished quarter from columns that already exist and a renewal's clone lands
in the next period rather than this one — **no lineage column, and don't add
one for this.** Unlike `getAreasWithRollup`, archived objectives *do* count
towards a period's rollup: there, being archived is the normal end state, and
excluding them would score a finished quarter at nothing.

`reviews` has no foreign key, deliberately: a grade has to outlive the objective
`renewObjective` archives. That means nothing reclaims a grade when its subject is
genuinely deleted, so `_deleteReviewsUnder` does, running before the parent delete
while the subtree is still there to find. Add a level to the hierarchy and it
needs a branch there.

**Nothing exports.** There is no backup, no import, and no share — with no
account and no backend, the database on the phone is the only copy. A clipboard
JSON dump (`exportAll` / `exportedTables`) existed and was removed as more menu
than it earned. The OKR tab's overflow menu holds "Close ⟨quarter⟩" and "Past
periods" above a divider, then the archived toggle and "Reorder areas". The
first two are withheld when there is nothing to close and nothing closed, so an
app that has never finished a quarter shows the menu it always did.

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
  `DBHelper()` (a singleton) and refreshes after a push. Both tab roots
  name theirs `reload()`, public, because `RootNav` calls it on the tab being
  entered — the `IndexedStack` keeps sibling tabs alive across writes, so tab
  entry is what reloads them (`test/tab_reload_test.dart` pins this). UI-only
  state (which Record row is open, whether archived objectives show) lives in
  `setState` and is never persisted — except which objectives are collapsed,
  which is `objectives.collapsed` so the tree reopens the way it was left.
- Spacing, colour, radius, type and motion all come from `ui/tokens.dart`
  (`kGapXs`=4 … `kGapXl`=24). Never use a spacing const as a radius — there is a
  radius ladder (`kRadiusCard`/`Sheet`/`Field`/`Chip`), and `circular(kGapMd)` is
  what it replaced. Reuse `showActionSheet`, `confirmDelete`, `promptText`,
  `pickEmoji`, `EmojiWell`, `InlineAddField`, `ScoreBar`, `EmptyState`,
  `SectionHeader`. A row carrying both an emoji and a name edits them in one
  action: `promptNameAndEmoji` is `promptText` with an `EmojiWell` beside the
  field, which is what an area's "Edit" opens, writing both in one `updateArea`
  call. Two menu entries for one edit is what it replaced.
- `ScoreBar` is always `kAccent` and takes no direction — see above. It is pure
  colour, so pass it a `label`: that plus its percentage is all a screen reader
  gets. `GradeBar` likewise carries its own `Semantics`.
- A 1–10 grade has **two widgets, deliberately**: `GradeBar` reads one back in
  ten 8dp segments, `GradeInput` sets one. They can't be one widget with an
  `onChanged`, because a readout that small is nowhere near a tap target —
  `GradeInput` is a single `kTapTarget`-high bar where the x you press picks the
  grade, so there is nothing small to miss and no drag to release. Both take
  `kAccent`: a grade is a judgement about progress, not a fifth meaning.
- There is **one heading treatment** (`SectionHeader`, caps at `kTypeAreaLabel`),
  shared by an area, a form section and a quarter, and **one empty state**
  (`EmptyState`: an icon and a line). Each was three. An empty state states the
  state and explains only what can't be seen — the constraint in
  `link_kr_sheet.dart` earns a sentence; "No streaks yet" does not.
- Anything the user waits on must not sit behind a platform channel.
  `WidgetSync.push()` is best-effort — there may be no widget placed, and none
  exists on iOS — so `reload()` fires it without awaiting. `InlineAddField` clears
  its field *before* awaiting the write for the same reason, and the habit tick
  paints its new state from `HabitsScreenState._pending` while the write settles
  behind it.
- **The Android widget is the same app, so it wears the same accent.** Its
  palette is named in `android/app/src/main/res/values/colors.xml` and mirrors
  `ui/tokens.dart` by hand — Dart consts can't reach Android XML, so the two move
  together or not at all. `widget_accent` *is* `kAccent`. The widget's own bar
  follows `ScoreBar`'s rule (flat fill, flat track, no gradient), inverted for a
  dark surface: white on the accent showing through at 25%. Keep white at 90% or
  above for the small label — 80% falls under 4.5:1 against the accent.

## Schema

Version 7, ten tables. `areas → objectives → key_results` is intent;
`executions → measurements` is doing; `reviews` holds quarterly grades.
`executions` and `trackables` exist but have no CRUD yet — leave them.

**No table stores a period.** An objective's quarter is implied by its
`start_date`, a measurement's by its `recorded_at`, and `reviews.period` is the
only period string in the schema. `okr/period.dart` derives the rest, which is
what let the whole close-and-report flow ship without a migration.

`reviews.subject_kind` is an open string, and `'period'` is one: the row saying
a quarter was closed is `('period', '2026-Q3', '2026-Q3')` with a **null
grade** — the user ranks key results and objectives, never the quarter, so what
that row carries is `graded_at`. Because its `subject_id` is a period id rather
than a uuid, `_deleteReviewsUnder` can never match it, which is right: a record
that a quarter happened must outlive the areas it held. `DBHelper.closePeriod`
writes it through the same `saveGrade` upsert as everything else, so closing
twice is one row.
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
baseline from the KR's last entry, so progressive goals need no rebuilding —
and a target raised through the close flow does *not* move it, because where a
quarter starts and what it aims at are two different facts. That whole clone is
one transaction: the close flow calls it once per objective in a row, and a
failure between the clone and the archive would otherwise leave a quarter
half-renewed with no way to tell which half.
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
the archived copy so the link doesn't end up claimed at both ends. Dropping a
linked key result through the close flow therefore leaves the habit linked to
nothing — there is no clone to hand it to — which is correct: the habit and its
streak are untouched, it just stops feeding an objective that no longer exists.

Because the migrations and these cascades are SQLite behaviour rather than pure
rules, they are tested against a real database via `sqflite_common_ffi` and
`DBHelper.openAt` — see `test/renew_carry_test.dart` (carrying with a key result
dropped or a target raised), `test/period_report_test.dart` (a period
reconstructing from `start_date`, and what the overflow menu asks before drawing
itself), `test/habit_okr_link_test.dart` and the
`*_migration_test.dart` files, which declare the pre-migration schema
verbatim because `_onCreate` always builds the current one.

## Keeping this file current

Update it in the same change that makes it stale: a new top-level `lib/`
directory or layering change, a schema/version bump, an SDK upgrade, or a new
command. Treat a wrong statement here as a bug and fix it in passing.
