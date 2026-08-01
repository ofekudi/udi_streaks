import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Spacing, colour, type, radius and motion tokens come with the kit, so a
/// screen needs one import to build a row.
export 'tokens.dart';

/// The card that holds a group of rows: white paper lifted off the grey page by
/// a hairline and one whisper of shadow.
///
/// Containment is how the app shows hierarchy — nothing is ever indented — so
/// the card is shared rather than rebuilt per screen: the tree's objectives, the
/// Record pages and the habits list must not drift apart.
class AppCard extends StatelessWidget {
  final Widget child;

  /// Sits a tone deeper and loses its shadow, so the card reads as shelved
  /// rather than dressed differently.
  final bool deeper;

  const AppCard({super.key, required this.child, this.deeper = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: kGapSm),
      decoration: BoxDecoration(
        color: deeper ? kCardDeep : kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        boxShadow: deeper
            ? null
            : const [
                BoxShadow(
                    color: Color(0x0A15171C),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
              ],
      ),
      // The hairline goes in *front* of the child, not in the decoration behind
      // it: a border in `decoration` insets its child by its width, and that
      // pixel would push an objective's title off the edge its area heading and
      // its key results share.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kHairline),
      ),
      // Keeps a row's ink ripple inside the rounded corners.
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A hairline inside an [AppCard], inset to the card's own text column. It says
/// where one row ends — proximity alone couldn't, because a two-line row's title
/// sits closer to its own bar than to the row above it.
///
/// [AppRule.flush] spans the full width instead, for a rule that closes a page
/// section rather than separating two rows of one card.
class AppRule extends StatelessWidget {
  final bool flush;

  const AppRule({super.key}) : flush = false;
  const AppRule.flush({super.key}) : flush = true;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: flush ? 0 : kGapMd,
        endIndent: flush ? 0 : kGapMd,
        color: flush ? kHairline : kRule,
      );
}

/// A consistent, roomy bottom sheet: full width, a title with a close button,
/// and a scrolling body that grows with content up to [heightFactor] of the
/// screen. Tapping outside dismisses it.
///
/// The rounded top, the fill and the drag handle all come from the theme's
/// `bottomSheetTheme`, which is what lets a bare `showModalBottomSheet` (the
/// action and reorder sheets below) look like this one without repeating it.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double heightFactor = 0.9,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    useSafeArea: true,
    builder: (ctx) => AppSheetShell(
      title: title,
      heightFactor: heightFactor,
      child: Builder(builder: builder),
    ),
  );
}

class AppSheetShell extends StatelessWidget {
  final String title;
  final double heightFactor;
  final Widget child;
  const AppSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.heightFactor = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Size the sheet to the space *above* the keyboard, and lift the whole
    // sheet up by the keyboard height so its content is never hidden behind it.
    final maxH = (media.size.height - keyboard) * heightFactor;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGapLg, 0, kGapXs, kGapSm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kTypeAppBar),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const AppRule.flush(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    kGapLg, kGapLg, kGapLg, kGapXl),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in a long-press context menu.
class SheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// A long-press context menu shown as a small bottom sheet (no text fields, so
/// no keyboard concerns). Each action pops the sheet, then runs.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  required List<SheetAction> actions,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle(title),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.destructive ? kDanger : kInkSoft),
              title: Text(a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: a.destructive
                      ? kTypeKr.copyWith(color: kDanger)
                      : kTypeKr),
              onTap: () {
                Navigator.pop(context);
                a.onTap();
              },
            ),
          const SizedBox(height: kGapSm),
        ],
      ),
    ),
  );
}

/// The heading of a sheet that names what is being acted on. Shares
/// [SectionHeader]'s treatment, so the app has one heading idiom.
class _SheetTitle extends StatelessWidget {
  final String title;
  const _SheetTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGapLg, 0, kGapLg, kGapSm),
        child: Text(title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kTypeAreaLabel),
      );
}

/// One sibling level as a drag list: each `(id, label)` entry is a row with a
/// drag handle. Dismissing the sheet returns the ids in their new order, or
/// null when nothing moved — there is no confirm step, the drag is the edit.
Future<List<String>?> showReorderSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> entries,
}) async {
  final order = [...entries];
  await showModalBottomSheet(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetTitle(title),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) => setState(() {
                  order.insert(to, order.removeAt(from));
                }),
                children: [
                  for (var i = 0; i < order.length; i++)
                    ListTile(
                      key: ValueKey(order[i].$1),
                      title: Text(order[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kTypeKr),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle, color: kInkFaint),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: kGapSm),
          ],
        ),
      ),
    ),
  );
  final ids = [for (final e in order) e.$1];
  for (var i = 0; i < ids.length; i++) {
    if (ids[i] != entries[i].$1) return ids;
  }
  return null;
}

/// A small heading above a group, with an optional explainer under it. Set in
/// caps at [kTypeAreaLabel] — the app's one heading idiom, shared with an area's
/// name in the tree and a quarter's name in a history.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapXs, kGapXs, kGapXs, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: kTypeAreaLabel),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: kGapXs),
              child: Text(subtitle!, style: kTypeMeta),
            ),
        ],
      ),
    );
  }
}

/// Nothing here yet, stated once. An icon, a line, and no coaching — this app
/// has one user, who put the emptiness there.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState(this.icon, this.message, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            vertical: kGapXl * 2, horizontal: kGapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: kInkFaint),
            const SizedBox(height: kGapMd),
            Text(message, textAlign: TextAlign.center, style: kTypeMeta),
          ],
        ),
      );
}

/// The standard destructive confirmation. Returns true only if the user
/// confirmed; dismissing it counts as "no".
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: kDanger)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Guards leaving a page that holds typed-but-unsaved input. Returns true to
/// discard it; dismissing counts as "keep editing". Title-only — the count in
/// the title is the whole fact.
Future<bool> confirmDiscard(BuildContext context,
    {required String title}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard', style: TextStyle(color: kDanger)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A simple centered rename dialog (the keyboard re-centers it above the
/// field). Returns the trimmed text, or null if dismissed.
Future<String?> promptText(BuildContext context,
    {required String title, required String initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}

/// The same dialog with an emoji beside the field, for a row that carries both.
///
/// One action rather than two: an emoji and a name are one edit, and
/// [DBHelper.updateArea] already takes them in one write. Stateful because
/// [promptText] closes over its controller and so could not repaint a freshly
/// picked emoji.
///
/// Returns null when dismissed *or* when the name is empty, so a caller needs
/// one null check.
Future<({String name, String emoji})?> promptNameAndEmoji(
  BuildContext context, {
  required String title,
  required String initialName,
  required String initialEmoji,
}) {
  return showDialog<({String name, String emoji})>(
    context: context,
    builder: (_) => _NameEmojiDialog(
      title: title,
      initialName: initialName,
      initialEmoji: initialEmoji,
    ),
  );
}

class _NameEmojiDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialEmoji;

  const _NameEmojiDialog({
    required this.title,
    required this.initialName,
    required this.initialEmoji,
  });

  @override
  State<_NameEmojiDialog> createState() => _NameEmojiDialogState();
}

class _NameEmojiDialogState extends State<_NameEmojiDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late String _emoji = widget.initialEmoji;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, emoji: _emoji));
  }

  Future<void> _pick() async {
    final emoji = await pickEmoji(context);
    if (emoji != null) setState(() => _emoji = emoji);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        children: [
          EmojiWell(emoji: _emoji, onTap: _pick),
          const SizedBox(width: kGapSm),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Asks for one value to log, returning the raw text the user typed or null if
/// they backed out. Parsing is the caller's job, so the notation survives.
///
/// A dialog because the caller is already scoped to one key result — the
/// screen states which, so the value is all that's left to ask for.
Future<String?> promptLogValue(BuildContext context,
    {required String title, String? unit}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: LogValueField(
        controller: controller,
        unit: unit,
        autofocus: true,
        onSubmit: () => Navigator.pop(context, controller.text.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Log')),
      ],
    ),
  );
}

/// Copy for deleting a key result — shared by the OKR tree and the Record
/// page, which both offer the same action.
const kDeleteKrTitle = 'Delete key result';
String deleteKrMessage(String title) =>
    'Delete "$title"? Its logged measurements are removed.';

/// The emoji picker as a bottom sheet. Returns the chosen emoji, or null if
/// the sheet was dismissed.
Future<String?> pickEmoji(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (_) => SizedBox(
      height: 340,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) =>
            Navigator.pop(context, emoji.emoji),
        // Without a Config the picker paints its own palette and is the one
        // surface in the app that ignores the theme.
        config: const Config(
          emojiViewConfig: EmojiViewConfig(backgroundColor: kCard),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: kCard,
            iconColor: kInkFaint,
            iconColorSelected: kAccent,
            indicatorColor: kAccent,
            dividerColor: kHairline,
            backspaceColor: kAccent,
          ),
          bottomActionBarConfig: BottomActionBarConfig(enabled: false),
          searchViewConfig: SearchViewConfig(backgroundColor: kCard),
        ),
      ),
    ),
  );
}

/// A tap target showing one emoji, opening [pickEmoji]. Sits beside a name —
/// in the "Add area" field's `leading` slot, and in [promptNameAndEmoji].
class EmojiWell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  /// Shown, faded, when [emoji] is empty — an unset well still has to look like
  /// somewhere to tap.
  final String placeholder;

  const EmojiWell({
    super.key,
    required this.emoji,
    required this.onTap,
    this.placeholder = '',
  });

  @override
  Widget build(BuildContext context) {
    final unset = emoji.isEmpty;
    return InkWell(
      onTap: onTap,
      // Without this the ripple is a square inside a rounded box.
      borderRadius: BorderRadius.circular(kRadiusField),
      child: Container(
        width: kTapTarget,
        height: kTapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kField,
          borderRadius: BorderRadius.circular(kRadiusField),
        ),
        child: Opacity(
          opacity: unset ? 0.4 : 1,
          child: Text(unset ? placeholder : emoji,
              style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

/// Inline "+ Add" that expands into a text field in place. Submitting adds a
/// row and keeps the field open for the next one. Lives inside the page (a
/// normal Scaffold), so the keyboard pushes the page up instead of covering it.
class InlineAddField extends StatefulWidget {
  final String label;
  final String? hint;
  final Future<void> Function(String value) onSubmit;
  final Widget? leading; // e.g. a type toggle
  const InlineAddField({
    super.key,
    required this.label,
    required this.onSubmit,
    this.hint,
    this.leading,
  });

  @override
  State<InlineAddField> createState() => _InlineAddFieldState();
}

class _InlineAddFieldState extends State<InlineAddField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    // Emptied before the write, not after it: the text is already captured, so
    // the field shouldn't wait on a database read to look ready for the next
    // entry.
    _controller.clear();
    setState(() {}); // keep the field open for rapid multi-add
    _focus.requestFocus();
    await widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      // A full-width row closed by a rule above it, so it reads as the end of
      // the list rather than a button that wandered onto the page.
      return InkWell(
        onTap: () {
          setState(() => _editing = true);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _focus.requestFocus());
        },
        borderRadius: BorderRadius.circular(kRadiusField),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: kGapMd),
          child: Row(
            children: [
              const Icon(Icons.add, size: 18, color: kInkFaint),
              const SizedBox(width: kGapSm),
              Text(widget.label,
                  style: kTypeKr.copyWith(
                      color: kInkFaint, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kGapSm),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: kGapSm)
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: widget.hint ?? widget.label),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.check_circle),
            color: kAccent,
          ),
          IconButton(
            onPressed: () {
              _controller.clear();
              FocusScope.of(context).unfocus();
              setState(() => _editing = false);
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// The value-entry field, used everywhere a measurement is logged. Plain text
/// rather than a number pad, because [parseValue] also accepts "3x10" and
/// "10,9,8" — a numeric keypad can't type those.
class LogValueField extends StatelessWidget {
  final TextEditingController controller;
  final String? unit;
  final VoidCallback onSubmit;
  final bool autofocus;

  /// Overrides the notation examples. The objective fill page passes `''`: its
  /// field is a narrow column beside a row that already states the value.
  final String hintText;

  /// Smaller text and tighter padding, for a field that sits in a narrow column
  /// beside the value it changes rather than owning its own line — at the
  /// default size it towered over the row.
  final bool compact;

  const LogValueField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.unit,
    this.autofocus = false,
    this.hintText = 'e.g. 30, 3x10, 10,9,8',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.text,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      style: compact ? kTypeNumber : kTypeKr,
      decoration: InputDecoration(
        hintText: hintText,
        suffixText: unit ?? '',
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: kGapSm, vertical: kGapSm)
            : null,
      ),
    );
  }
}

/// Parses a logged value. Accepts a plain number, "sets × reps" shorthand
/// ("3x10", "3*10", "3×10" → 30), and per-set lists that add up, written with
/// "+" or "," ("8+7+6" or "10,9,8" → 21 / 27). Terms can be combined too.
double? parseValue(String input) {
  final s =
      input.trim().toLowerCase().replaceAll('×', 'x').replaceAll(',', '+');
  if (s.isEmpty) return null;
  double sum = 0;
  for (final term in s.split('+')) {
    final t = term.trim();
    if (t.isEmpty) return null;
    double product = 1;
    for (final f in t.split(RegExp(r'[x*]'))) {
      final n = double.tryParse(f.trim());
      if (n == null) return null;
      product *= n;
    }
    sum += product;
  }
  return sum;
}

/// Formats a double without a trailing ".0" (100.0 -> "100", 97.5 -> "97.5").
String fmtNum(num? v) {
  if (v == null) return '–';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A date as a person would say it, e.g. "14 Jul". The year is dropped: every
/// date the app shows is inside a quarter it has already named.
String fmtDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// A logged day, e.g. "Tue 28 Jul". The weekday is the point — it is what makes
/// a gap in a habit's history legible.
String fmtWeekdayDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${fmtDayMonth(d)}';

/// A neutral 0–1 OKR score, e.g. "0.71".
String fmtScore(double? s) => s == null ? '–' : s.toStringAsFixed(2);

/// A 0–1 fraction as a whole percent, e.g. "71%".
String fmtPct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

/// The move since the previous entry, e.g. `↗ +6`. [kAccent] when it went the
/// way the key result wants, [kCaution] when it went against it, muted when
/// unchanged.
class DeltaText extends StatelessWidget {
  final double delta;
  final bool down;
  const DeltaText(this.delta, {super.key, this.down = false});

  @override
  Widget build(BuildContext context) {
    if (delta == 0) return Text('±0', style: kTypeMetaNum);
    final up = delta > 0;
    final good = down ? !up : up;
    final color = good ? kAccent : kCaution;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // An icon rather than ▲/▼, which Roboto draws as heavy black triangles
        // that outweigh the number beside them.
        Icon(up ? Icons.north_east_rounded : Icons.south_east_rounded,
            size: 12, color: color),
        const SizedBox(width: 2),
        Text('${up ? '+' : '−'}${fmtNum(delta.abs())}',
            style: kTypeMetaNum.copyWith(
                color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// A thin progress bar for a key result's or objective's score.
///
/// **One colour, one direction, always 0..100.** Every bar in the app fills from
/// the left in [kAccent], whichever way the underlying number moves — `scoreFor`
/// has already turned "84kg heading for 78" into a fraction of the distance
/// covered, so the bar has nothing left to express about direction. A bar that
/// changed colour or filled the other way only raised the question of which way
/// to read it.
///
/// [height] is [kBarThick] on an objective and [kBarThin] on its key results —
/// the *length* stays the same at both levels, because length is what lets two
/// scores on one 0..1 scale be compared by eye.
///
/// [label] is what the bar measures — without it the bar is colour alone and
/// announces nothing.
class ScoreBar extends StatelessWidget {
  final double value; // 0..1
  final String? label;
  final double height;

  const ScoreBar(
    this.value, {
    super.key,
    this.label,
    this.height = kBarThin,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      label: label,
      value: fmtPct(v),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: motion(context, kDurSlow),
        curve: kCurve,
        builder: (context, shown, _) => SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration:
                    BoxDecoration(color: kTrack, borderRadius: radius),
              ),
              // centerLeft is load-bearing: FractionallySizedBox centres its
              // child by default, which grows the fill outward from the middle
              // of the track in both directions.
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: shown,
                child: Container(
                  decoration:
                      BoxDecoration(color: kAccent, borderRadius: radius),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dependency-free trend sparkline drawn with CustomPaint. It draws itself in
/// on first build, so the trend arrives as a movement rather than as a shape
/// that was always there.
class Sparkline extends StatelessWidget {
  final List<double> points;
  final double height;
  final Color? color;
  const Sparkline(this.points, {super.key, this.height = 70, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kAccent;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion(context, const Duration(milliseconds: 520)),
        curve: kCurve,
        builder: (context, t, _) =>
            CustomPaint(painter: _SparkPainter(points, c, t)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  /// How much of the line to draw, 0..1.
  final double progress;

  _SparkPainter(this.points, this.color, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minV = points.reduce((a, b) => a < b ? a : b);
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final n = points.length;
    final dx = n == 1 ? 0.0 : size.width / (n - 1);
    Offset at(int i) {
      final x = n == 1 ? size.width / 2 : dx * i;
      final y = size.height - ((points[i] - minV) / range) * size.height;
      return Offset(x, y.clamp(2.0, size.height - 2));
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final p = at(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        fill.moveTo(p.dx, size.height);
        fill.lineTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      }
    }
    fill.lineTo(at(n - 1).dx, size.height);
    fill.close();

    // A gradient fill fades out downward, so the line stays the figure and the
    // area under it stays ground.
    canvas.drawPath(
        fill,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.16),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (progress >= 1) {
      canvas.drawPath(path, stroke);
    } else {
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * progress), stroke);
      }
    }

    // The end point is where the eye lands, so it gets a ring to sit in — a
    // bare dot disappears into the fill behind it.
    final last = at(n - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = kCard);
    canvas.drawCircle(last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points != points || old.color != color || old.progress != progress;
}

/// The 1–10 grade shown as a small segmented bar (read-only display).
class GradeBar extends StatelessWidget {
  final int? grade;
  const GradeBar(this.grade, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = grade ?? 0;
    return Semantics(
      label: 'grade',
      value: grade == null ? 'not graded' : '$g of 10',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(10, (i) {
          return Container(
            width: 8,
            height: 14,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: i < g ? kAccent : kTrack,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Aggregation modes shown to the user in plain language with an example.
class AggregationOption {
  final String value; // SUM | COUNT | LATEST
  final String label;
  final String explainer;
  const AggregationOption(this.value, this.label, this.explainer);
}

const List<AggregationOption> kAggregations = [
  AggregationOption('LATEST', 'Value', 'Your latest value — weight, a time'),
  AggregationOption('COUNT', 'Count', 'How many times — runs, books'),
  AggregationOption('SUM', 'Total', 'Adds up amounts — km, reps, minutes'),
];
