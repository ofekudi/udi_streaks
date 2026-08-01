import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The app's one theme, built from [tokens].
///
/// Component themes are not decoration here — they are how the app stays
/// consistent without every caller remembering to. A bare
/// `showModalBottomSheet`, `AlertDialog` or `TextField` inherits the same
/// chrome as its dressed-up sibling, so the two can't drift.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent).copyWith(
    // Only the roles the app actually reads. Anything still on a scheme lookup
    // rather than a token therefore lands on the right colour anyway.
    primary: kAccent,
    onPrimary: Colors.white,
    primaryContainer: kAccentDim,
    onPrimaryContainer: kAccent,
    tertiary: kDown,
    error: kDanger,
    surface: kPage,
    onSurface: kInk,
    onSurfaceVariant: kInkSoft,
    surfaceContainerLowest: kCard,
    surfaceContainerLow: kCard,
    surfaceContainer: kCardDeep,
    surfaceContainerHigh: kCardDeep,
    surfaceContainerHighest: kTrack,
    outline: kInkFaint,
    outlineVariant: kHairline,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    textTheme: _tightened(base.textTheme),
    scaffoldBackgroundColor: kPage,

    // Quieter than M3's InkSparkle, which draws attention to the tap rather
    // than to what the tap did.
    splashFactory: InkRipple.splashFactory,

    // The calm M3 push. Android's default ZoomPageTransitions overshoots.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
    }),

    // The bar is the page, closed by a hairline. No tint, no shadow, no lift on
    // scroll — the content is what should move.
    appBarTheme: const AppBarThemeData(
      backgroundColor: kPage,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: kTypeAppBar,
      iconTheme: IconThemeData(color: kInkSoft, size: 22),
      actionsIconTheme: IconThemeData(color: kInkSoft, size: 22),
      shape: Border(bottom: BorderSide(color: kHairline)),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: kAccentDim,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? kTypeMeta.copyWith(
                  fontSize: 11, fontWeight: FontWeight.w700, color: kAccent)
              : kTypeMeta.copyWith(fontSize: 11, color: kInkFaint)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? kAccent : kInkFaint)),
    ),

    // One sheet chrome for the whole app: rounded top, one drag handle, no
    // tint. The handle is Flutter's, so the sheets that hand-rolled one and the
    // sheets that had none now agree.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCard,
      modalBackgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: kHairline,
      dragHandleSize: Size(36, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSheet)),
      titleTextStyle: kTypeObjective.copyWith(fontSize: 17, height: 1.3),
      contentTextStyle: kTypeKr.copyWith(fontWeight: FontWeight.w400),
      actionsPadding: const EdgeInsets.fromLTRB(kGapSm, 0, kGapMd, kGapMd),
    ),

    // A filled field reads as somewhere to type; an outlined box the same
    // colour as the card does not. That is most of what made the Record page's
    // value fields invisible.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kField,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: kGapMd, vertical: kGapMd),
      hintStyle: kTypeMeta.copyWith(color: kInkFaint),
      labelStyle: kTypeMeta,
      floatingLabelStyle: kTypeMeta.copyWith(color: kAccent),
      helperStyle: kTypeMeta.copyWith(color: kInkFaint),
      suffixStyle: kTypeUnit,
      border: _fieldBorder(),
      enabledBorder: _fieldBorder(),
      focusedBorder: _fieldBorder(const BorderSide(color: kAccent, width: 1.5)),
      errorBorder: _fieldBorder(const BorderSide(color: kDanger)),
      focusedErrorBorder:
          _fieldBorder(const BorderSide(color: kDanger, width: 1.5)),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccent,
      foregroundColor: Colors.white,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.1),
    ),

    // 1px of a light colour, rather than 0.5px of a darker one — a half-pixel
    // line renders differently on every device.
    dividerTheme: const DividerThemeData(color: kRule, thickness: 1, space: 1),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kTrack,
        disabledForegroundColor: kInkFaint,
        minimumSize: const Size(0, kTapTarget),
        textStyle: kTypeKr.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusField)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccent,
        minimumSize: const Size(0, kTapTarget),
        side: const BorderSide(color: kHairline),
        textStyle: kTypeKr.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusField)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAccent,
        textStyle: kTypeKr.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusField)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: kInkSoft),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: kInkSoft,
      titleTextStyle: kTypeKr,
      subtitleTextStyle: kTypeMeta,
      minVerticalPadding: kGapSm,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusField)),
    ),

    // The same quantity a GradeBar draws, so grading and reading a grade stop
    // being two colours.
    sliderTheme: const SliderThemeData(
      activeTrackColor: kAccent,
      inactiveTrackColor: kTrack,
      thumbColor: kAccent,
      overlayColor: kAccentDim,
      valueIndicatorColor: kInk,
    ),

    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: kAccent, linearMinHeight: 3),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: kTypeKr.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusField)),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: kInk, borderRadius: BorderRadius.circular(kRadiusChip)),
      textStyle: kTypeMeta.copyWith(color: Colors.white),
    ),
  );
}

OutlineInputBorder _fieldBorder([BorderSide side = BorderSide.none]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusField),
      borderSide: side,
    );

/// M3's Roboto scale carries +0.25 to +0.5 of tracking on its body styles, which
/// reads loose on a screen that is mostly short labels and numbers. This pulls
/// the whole scale toward zero and puts the two ink tones on it, so a widget
/// still reading `textTheme.bodyMedium` lands near the token set.
TextTheme _tightened(TextTheme t) {
  TextStyle? tight(TextStyle? s, double spacing, {Color color = kInk}) =>
      s?.copyWith(letterSpacing: spacing, color: color);
  return t.copyWith(
    displayLarge: tight(t.displayLarge, -1),
    displayMedium: tight(t.displayMedium, -0.8),
    displaySmall: tight(t.displaySmall, -0.6),
    headlineLarge: tight(t.headlineLarge, -0.5),
    headlineMedium: tight(t.headlineMedium, -0.4),
    headlineSmall: tight(t.headlineSmall, -0.3),
    titleLarge: tight(t.titleLarge, -0.25),
    titleMedium: tight(t.titleMedium, -0.15),
    titleSmall: tight(t.titleSmall, -0.1),
    bodyLarge: tight(t.bodyLarge, -0.05),
    bodyMedium: tight(t.bodyMedium, -0.05),
    bodySmall: tight(t.bodySmall, 0, color: kInkSoft),
    labelLarge: tight(t.labelLarge, 0),
    labelMedium: tight(t.labelMedium, 0.2, color: kInkSoft),
    labelSmall: tight(t.labelSmall, 0.4, color: kInkSoft),
  );
}
