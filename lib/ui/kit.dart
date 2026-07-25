import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

// Spacing scale — every gap in the OKR module snaps to one of these.
const double kGapXs = 4, kGapSm = 8, kGapMd = 12, kGapLg = 16, kGapXl = 24;

/// Page padding for a list of cards.
const kListPadding = EdgeInsets.all(kGapMd);

/// Page padding for a form or detail page.
const kFormPadding = EdgeInsets.all(kGapLg);

/// Minimum square tap target (Material's 48dp), used by the small square
/// buttons that sit next to a text field.
const double kTapTarget = 48;

/// A consistent, roomy bottom sheet: full width, rounded top, a drag handle,
/// a title with a close button, and a scrolling body that grows with content
/// up to [heightFactor] of the screen. Tapping outside dismisses it.
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
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.destructive ? Colors.red : null),
              title: Text(a.label,
                  style: a.destructive
                      ? const TextStyle(color: Colors.red)
                      : null),
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

/// A small caps-ish heading above a group, with an optional explainer under it.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapXs, kGapXs, kGapXs, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
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
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        decoration: const InputDecoration(border: OutlineInputBorder()),
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
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) =>
            Navigator.pop(context, emoji.emoji),
      ),
    ),
  );
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
    await widget.onSubmit(text);
    _controller.clear();
    if (mounted) {
      setState(() {}); // keep the field open for rapid multi-add
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            setState(() => _editing = true);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _focus.requestFocus());
          },
          icon: const Icon(Icons.add),
          label: Text(widget.label),
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
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hint ?? widget.label,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.check_circle),
            color: Theme.of(context).colorScheme.primary,
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
  const LogValueField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.unit,
    this.autofocus = false,
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
      decoration: InputDecoration(
        isDense: true,
        hintText: 'e.g. 30, 3x10, 10,9,8',
        suffixText: unit ?? '',
        border: const OutlineInputBorder(),
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

/// A neutral 0–1 OKR score, e.g. "0.71".
String fmtScore(double? s) => s == null ? '–' : s.toStringAsFixed(2);

/// The move since the previous entry, e.g. `▲ +6`. Green when it went the way
/// the key result wants, orange when it went against it, muted when unchanged.
class DeltaText extends StatelessWidget {
  final double delta;
  final bool down;
  const DeltaText(this.delta, {super.key, this.down = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall;
    if (delta == 0) {
      return Text('±0',
          style: base?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final up = delta > 0;
    final good = down ? !up : up;
    return Text(
      '${up ? '▲' : '▼'} ${up ? '+' : '−'}${fmtNum(delta.abs())}',
      style: base?.copyWith(
        color: good ? Colors.green.shade700 : Colors.orange.shade800,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A thin progress bar for a KR / objective score.
class ScoreBar extends StatelessWidget {
  final double value; // 0..1
  final bool down;
  const ScoreBar(this.value, {super.key, this.down = false});

  @override
  Widget build(BuildContext context) {
    final color = down ? Colors.orange : Colors.green.shade600;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// A dependency-free trend sparkline drawn with CustomPaint.
class Sparkline extends StatelessWidget {
  final List<double> points;
  final double height;
  final Color? color;
  const Sparkline(this.points, {super.key, this.height = 70, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(points, c)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  _SparkPainter(this.points, this.color);

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
    canvas.drawPath(
        fill,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color);
    final last = at(n - 1);
    canvas.drawCircle(last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points != points || old.color != color;
}

/// The 1–10 grade shown as a small segmented bar (read-only display).
class GradeBar extends StatelessWidget {
  final int? grade;
  const GradeBar(this.grade, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = grade ?? 0;
    const gradeColor = Color(0xFF3D7DD8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(10, (i) {
        return Container(
          width: 9,
          height: 16,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i < g
                ? gradeColor
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
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
