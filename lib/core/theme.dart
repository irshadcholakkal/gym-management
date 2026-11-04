import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reference-inspired graphite surfaces, electric lime and rounded geometry.
abstract final class GymTheme {
  static const ink = Color(0xFF171C22);
  static const blue = Color(0xFF527900);
  static const sage = blue;
  static const lime = Color(0xFFB6FF24);
  static const muted = Color(0xFF78818C);
  static const border = Color(0xFFE0E4DC);
  static const canvas = Color(0xFFF1F3ED);
  static const softBlue = Color(0xFFE7F2D4);
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
  static final mobile = compact(light);

  static ThemeData compact(ThemeData theme) => theme.copyWith(
        visualDensity: VisualDensity.compact,
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
    final surface = dark ? const Color(0xFF20262F) : Colors.white;
    final background = dark ? const Color(0xFF131920) : canvas;
    final text = dark ? const Color(0xFFF3F5EF) : ink;
    final secondary = dark ? const Color(0xFFA6AFBA) : const Color(0xFF667060);
    final line = dark ? const Color(0xFF363E47) : border;
    final primary = dark ? lime : blue;
    final subtle = dark ? const Color(0xFF303C25) : softBlue;
    final scheme =
        ColorScheme.fromSeed(seedColor: lime, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: dark ? ink : Colors.white,
      primaryContainer: lime,
      onPrimaryContainer: ink,
      secondary: primary,
      secondaryContainer: subtle,
      onSecondaryContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      surfaceContainerHighest:
          dark ? const Color(0xFF2A323C) : const Color(0xFFF0F3EB),
      outline: secondary,
      outlineVariant: line,
    );
    final base = ThemeData(
        useMaterial3: true, colorScheme: scheme, fontFamily: 'Manrope');
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28), side: BorderSide(color: line));
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w500,
                letterSpacing: -1.4,
                color: text),
            headlineSmall: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
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
          elevation: 0,
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
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: secondary),
        prefixIconColor: secondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: lime,
              foregroundColor: ink,
              minimumSize: const Size(44, 46),
              elevation: 0,
              textStyle: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: const StadiumBorder())),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: text,
              minimumSize: const Size(44, 46),
              side: BorderSide(color: line),
              shape: const StadiumBorder())),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(44, 44), shape: const StadiumBorder())),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              foregroundColor: secondary, minimumSize: const Size(44, 44))),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      chipTheme: ChipThemeData(
          backgroundColor: subtle,
          selectedColor: lime,
          side: BorderSide.none,
          labelStyle: TextStyle(
              color: primary, fontSize: 11, fontWeight: FontWeight.w600),
          shape: const StadiumBorder()),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: lime,
          indicatorShape: const StadiumBorder(),
          height: 74,
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? ink : secondary)),
          labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontFamily: 'Manrope', color: text, fontSize: 11))),
      listTileTheme: ListTileThemeData(
          iconColor: secondary,
          selectedColor: ink,
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
