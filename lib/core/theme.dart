import 'package:flutter/material.dart';

abstract final class GymTheme {
  static const ink = Color(0xFF08152F);
  static const blue = Color(0xFF397DE5);
  static const sage = blue;
  static const muted = Color(0xFF8590A3);
  static const border = Color(0xFFE5E8EE);
  static const canvas = Color(0xFFF3F5F8);
  static const softBlue = Color(0xFFEBF2FF);
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: Colors.white)
        .copyWith(
            primary: blue,
            onPrimary: Colors.white,
            secondary: blue,
            onSurface: ink,
            onSurfaceVariant: muted,
            outline: border),
    scaffoldBackgroundColor: canvas,
    textTheme: const TextTheme(
        headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            color: ink),
        headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: ink),
        titleLarge:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
        titleMedium:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
        bodyLarge: TextStyle(fontSize: 16, color: ink),
        bodyMedium: TextStyle(fontSize: 14, color: ink),
        bodySmall: TextStyle(fontSize: 12, color: muted)),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        hintStyle: const TextStyle(color: muted),
        prefixIconColor: muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: blue, width: 1.5))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        showDragHandle: true),
    chipTheme: ChipThemeData(
        backgroundColor: softBlue,
        side: BorderSide.none,
        labelStyle: const TextStyle(
            color: blue, fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        height: 72,
        indicatorColor: softBlue,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? blue : muted)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? blue : muted)),
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    listTileTheme: const ListTileThemeData(
        iconColor: muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
    dataTableTheme: const DataTableThemeData(
        headingTextStyle:
            TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13),
        dataTextStyle: TextStyle(color: ink, fontSize: 14),
        dividerThickness: 1,
        headingRowHeight: 48,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 80),
    cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: border))),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );
  static final ThemeData mobile = light.copyWith(
    dialogTheme: light.dialogTheme.copyWith(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24)),
    iconTheme: const IconThemeData(size: 20, color: muted),
    textTheme: light.textTheme.copyWith(
      headlineLarge: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.6),
      headlineSmall: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.5),
      titleLarge: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: ink),
      titleMedium: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: ink),
      bodyLarge: const TextStyle(fontSize: 14, color: ink),
      bodyMedium: const TextStyle(fontSize: 13, color: ink),
    ),
    inputDecorationTheme: light.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      minimumSize: const Size(44, 40),
      iconSize: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 40),
      iconSize: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      minimumSize: const Size(44, 40),
      iconSize: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    )),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
      iconSize: 20,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.all(10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    )),
    chipTheme: light.chipTheme.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: const TextStyle(
          color: blue, fontSize: 11, fontWeight: FontWeight.w500),
    ),
    listTileTheme: light.listTileTheme.copyWith(
      dense: true,
      minLeadingWidth: 32,
      horizontalTitleGap: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    ),
    navigationBarTheme: light.navigationBarTheme.copyWith(
      height: 60,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 20,
          color: states.contains(WidgetState.selected) ? blue : muted)),
      indicatorShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    cardTheme: light.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border))),
  );
}
