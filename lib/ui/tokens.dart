import 'package:flutter/material.dart';

/// Design tokens: colour, radius, type and motion.
///
/// Plain top-level consts rather than a `ThemeExtension`, because widget tests
/// pump a bare `MaterialApp` with no theme — an extension lookup would throw
/// there. Literal colours are what the light-only decision buys: there is no
/// second brightness to derive, so a semantic value can just *be* a colour
/// instead of being squeezed into a `ColorScheme` role that nearly fits.

// ── Spacing ─────────────────────────────────────────────────────────────────
// Every gap in the app snaps to one of these.
const double kGapXs = 4, kGapSm = 8, kGapMd = 12, kGapLg = 16, kGapXl = 24;

/// Page padding for a list of cards.
const kListPadding = EdgeInsets.all(kGapMd);

/// Page padding for a form or detail page.
const kFormPadding = EdgeInsets.all(kGapLg);

/// Minimum square tap target (Material's 48dp), used by the small square
/// buttons that sit next to a text field.
const double kTapTarget = 48;

// ── Ink ─────────────────────────────────────────────────────────────────────
const kInk = Color(0xFF15171C); // titles, values
const kInkSoft = Color(0xFF5A606E); // units, dates, secondary lines
const kInkFaint = Color(0xFF8B91A0); // area labels, hints, the pace marker

// ── Paper ───────────────────────────────────────────────────────────────────
const kPage = Color(0xFFF4F5F7); // scaffold, app bar
const kCard = Color(0xFFFFFFFF); // AppCard
const kCardDeep = Color(0xFFEDEEF1); // AppCard(deeper:) — archived
const kField = Color(0xFFF1F2F5); // filled inputs, EmojiWell

// ── Lines ───────────────────────────────────────────────────────────────────
const kHairline = Color(0xFFE2E4E9); // card borders, page-level edges
const kRule = Color(0xFFECEDF1); // rules between rows inside a card
const kTrack = Color(0xFFE6E8ED); // the unfilled part of a bar

// ── Meaning ─────────────────────────────────────────────────────────────────
/// Four colours, four meanings. Progress and "done" share one, because a
/// completed habit and a moving key result are the same news.
const kAccent =
    Color(0xFF0F766E); // progress, done, a delta going the right way
const kAccentDim = Color(0xFFE3F2EF); // nav indicator, streak chip, +1 chip
// Marks the "lower is better" side of the direction toggle, where direction is
// what the control sets. Not a bar colour: a score bar is always [kAccent],
// because `scoreFor` has already folded direction into the fraction.
const kDown = Color(0xFF2B57DE);
const kCaution = Color(0xFFA8520E); // at risk, skipped, a delta going backwards
const kDanger = Color(0xFFB3261E); // destructive actions, a broken streak

// ── Radii ───────────────────────────────────────────────────────────────────
/// Corner radius of a card that holds a group of rows.
const double kRadiusCard = 14;
const double kRadiusSheet = 20;
const double kRadiusField = 10; // inputs, buttons, EmojiWell
const double kRadiusChip = 8; // streak badge, archived badge, +1

/// Bar heights. An objective's bar is thicker than its key results' so a rollup
/// and a leaf metric stop being pixel-identical — but the *length* is unchanged,
/// because length is what makes two scores on one 0..1 scale comparable by eye.
const double kBarThick = 7;
const double kBarThin = 5;

/// Space under the last row of a list so a FAB never covers it.
const double kFabGutter = 88;

// ── Type ────────────────────────────────────────────────────────────────────
/// The system font throughout. Precision comes from weight, size and tracking,
/// plus tabular figures so a value column doesn't shift when a digit changes.
///
/// The ramp is 11 / 15 / 14 across area, objective and key result, with three
/// ink tones. An area label is the smallest and faintest thing in the tree: it
/// marks a section, it isn't the subject of one.
const _tnum = <FontFeature>[FontFeature.tabularFigures()];

const kTypeAppBar = TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: kInk);

const kTypeAreaLabel = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
    color: kInkFaint);

const kTypeObjective = TextStyle(
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    color: kInk);

const kTypeKr = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.05,
    color: kInk);

/// A value the eye lands on. `fontFeatures` is the point: without it the value
/// column reflows every time a digit changes width.
const kTypeNumber = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontFeatures: _tnum,
    color: kInk);

/// What a value is measured against — `/ 90 kg`. Recedes so the value leads.
const kTypeUnit = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    fontFeatures: _tnum,
    color: kInkSoft);

const kTypeMeta = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: kInkSoft);

const kTypeMetaNum = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFeatures: _tnum,
    color: kInkSoft);

// ── Motion ──────────────────────────────────────────────────────────────────
const kDurFast = Duration(milliseconds: 120);
const kDur = Duration(milliseconds: 180);
const kDurSlow = Duration(milliseconds: 260);
const kCurve = Curves.easeOutCubic;

/// Every animation in the app routes its duration through here, so honouring
/// the platform's reduce-motion setting is one call rather than a convention.
Duration motion(BuildContext context, [Duration d = kDur]) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
