import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Soft surfaces with Emirates red accents in both appearances.
abstract final class GymTheme {
  static const ink = Color(0xFF222222);
  static const emiratesRed = Color(0xFFD71920);
  static const blue = emiratesRed;
  static const sage = blue;
  static const lime = Color(0xFFB6FF24);
  static const muted = Color(0xFF78818C);
  static const border = Color(0xFFEBEBEB);
  static const canvas = Color(0xFFFAFAFA);
  static const softBlue = Color(0xFFFFEEEE);
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
  static final mobile = compact(light);

  static ThemeData compact(ThemeData theme) => theme.copyWith(
        visualDensity: VisualDensity.standard,
        textTheme: theme.textTheme.copyWith(
          headlineLarge: theme.textTheme.headlineLarge?.copyWith(fontSize: 26),
          headlineSmall: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
        ),
        dialogTheme: theme.dialogTheme.copyWith(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24)),
        navigationBarTheme: theme.navigationBarTheme.copyWith(height: 68),
      );

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF242225) : Colors.white;
    final background = dark ? const Color(0xFF181719) : canvas;
    final text = dark ? const Color(0xFFF7F5F6) : ink;
    final secondary = dark ? const Color(0xFFB8B2B6) : const Color(0xFF717171);
    final line = dark ? const Color(0xFF3D383C) : border;
    final primary = dark ? const Color(0xFFFF9094) : emiratesRed;
    const accent = emiratesRed;
    const onAccent = Colors.white;
    final subtle = dark ? const Color(0xFF3C2628) : softBlue;
    final scheme =
        ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
            .copyWith(
      primary: primary,
      onPrimary: dark ? ink : Colors.white,
      primaryContainer: accent,
      onPrimaryContainer: onAccent,
      secondary: primary,
      secondaryContainer: subtle,
      onSecondaryContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      surfaceContainerHighest:
          dark ? const Color(0xFF302C30) : const Color(0xFFF7F7F7),
      outline: secondary,
      outlineVariant: line,
    );
    final base = ThemeData(
        useMaterial3: true, colorScheme: scheme, fontFamily: 'Manrope');
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), side: BorderSide(color: line));
    return base.copyWith(
      scaffoldBackgroundColor: background,
      iconTheme: IconThemeData(color: secondary, size: 22),
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
                color: text),
            headlineSmall: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                color: text),
            titleLarge: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
                color: text),
            titleMedium: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: text),
            bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: text),
            bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: text),
            bodySmall: TextStyle(fontSize: 12, height: 1.4, color: secondary),
          )
          .apply(fontFamily: 'Manrope'),
      cardTheme: CardThemeData(
          color: surface,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: dark ? .12 : .05),
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: shape),
      appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: text,
          elevation: 0,
          surfaceTintColor: Colors.transparent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: secondary, fontSize: 14),
        floatingLabelStyle:
            TextStyle(color: primary, fontWeight: FontWeight.w600),
        errorMaxLines: 3,
        hintStyle: TextStyle(color: secondary),
        prefixIconColor: secondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              minimumSize: const Size(44, 48),
              elevation: 0,
              textStyle: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: text,
              minimumSize: const Size(44, 48),
              side: BorderSide(color: line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(44, 44), shape: const StadiumBorder())),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
      dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: .16),
          titleTextStyle: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: text),
          contentTextStyle: TextStyle(
              fontFamily: 'Manrope', fontSize: 14, height: 1.5, color: text),
          shape: shape),
      popupMenuTheme: PopupMenuThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: .12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: line)),
          textStyle:
              TextStyle(fontFamily: 'Manrope', fontSize: 13, color: text)),
      dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(surface),
              surfaceTintColor:
                  const WidgetStatePropertyAll(Colors.transparent),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))))),
      datePickerTheme: DatePickerThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: subtle,
          headerForegroundColor: text,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          dayShape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      timePickerTheme: TimePickerThemeData(
          backgroundColor: surface,
          dialBackgroundColor: scheme.surfaceContainerHighest,
          dialHandColor: primary,
          hourMinuteColor: subtle,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? onAccent : secondary),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? primary : line)),
      checkboxTheme: CheckboxThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          side: BorderSide(color: secondary, width: 1.5)),
      tabBarTheme: TabBarThemeData(
          labelColor: primary,
          unselectedLabelColor: secondary,
          indicatorColor: primary,
          dividerColor: line),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      chipTheme: ChipThemeData(
          backgroundColor: subtle,
          selectedColor: accent,
          side: BorderSide.none,
          labelStyle: TextStyle(
              fontFamily: 'Manrope',
              color: primary,
              fontSize: 11,
              fontWeight: FontWeight.w600),
          secondaryLabelStyle: TextStyle(
              fontFamily: 'Manrope',
              color: onAccent,
              fontSize: 11,
              fontWeight: FontWeight.w600),
          shape: const StadiumBorder()),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: subtle,
          indicatorShape: const StadiumBorder(),
          height: 74,
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? primary : secondary)),
          labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontFamily: 'Manrope', color: text, fontSize: 11))),
      listTileTheme: ListTileThemeData(
          iconColor: secondary,
          selectedColor: primary,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          shape: const StadiumBorder()),
      dataTableTheme: DataTableThemeData(
          headingTextStyle: TextStyle(
              fontFamily: 'Manrope',
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
          dataTextStyle:
              TextStyle(fontFamily: 'Manrope', color: text, fontSize: 13),
          dividerThickness: .5,
          headingRowHeight: 48,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 80),
      dividerTheme: DividerThemeData(color: line, thickness: .7),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: primary, linearTrackColor: subtle),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
              color: text, borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(color: surface, fontSize: 12)),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: text,
          contentTextStyle: TextStyle(color: surface, fontFamily: 'Manrope'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

class ThemePreference extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  bool _changed = false;
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('gympro.theme');
      if (!_changed) {
        mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
            ThemeMode.system;
        notifyListeners();
      }
    } catch (_) {
      /* Platform defaults remain available if storage is unavailable. */
    }
  }

  Future<void> select(ThemeMode value) async {
    _changed = true;
    mode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gympro.theme', value.name);
    } catch (_) {/* Selection still applies for this session. */}
  }
}

class ThemeScope extends InheritedNotifier<ThemePreference> {
  const ThemeScope(
      {super.key, required ThemePreference preference, required super.child})
      : super(notifier: preference);
}

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});
  @override
  Widget build(BuildContext context) {
    final preference =
        context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      initialValue: preference?.mode ?? ThemeMode.system,
      icon: Icon(Theme.of(context).brightness == Brightness.dark
          ? Icons.dark_mode_outlined
          : Icons.light_mode_outlined),
      onSelected: (value) => preference?.select(value),
      itemBuilder: (_) => [
        for (final mode in ThemeMode.values)
          CheckedPopupMenuItem(
              value: mode,
              checked: preference?.mode == mode,
              child: Text(switch (mode) {
                ThemeMode.system => 'Use device theme',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark'
              })),
      ],
    );
  }
}

/// A restrained entrance animation that respects the device motion preference.
class PageEntrance extends StatelessWidget {
  const PageEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (_, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)), child: child)),
        child: child,
      );
}
