import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> input = [
    BoxShadow(
      color: AppColors.shadowClaySm,
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> inputFocused = [
    BoxShadow(color: AppColors.primary, blurRadius: 0, offset: Offset(0, 1)),
  ];
}

class AppButtons {
  AppButtons._();

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(AppSpacing.radiusSm),
  );

  static ButtonStyle primary() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.bodySubtle,
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s2,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      textStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelMedium,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle outline() {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border, width: 1),
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s2,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      textStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelMedium,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle text({Color color = AppColors.primary}) {
    return TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      textStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelMedium,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle filled() {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.surface,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.bodySubtle,
      elevation: 0,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s2,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      textStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelMedium,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class AppInputs {
  AppInputs._();

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(AppSpacing.radiusSm),
  );

  static InputDecoration standard({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    Color fillColor = AppColors.surface,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: fillColor,
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: 14,
      ),
      border: const OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.primary, width: 1),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.danger, width: 1),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.danger, width: 1),
      ),
      hintStyle: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.bodySubtle,
      ),
      labelStyle: GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.bodyMuted,
      ),
      helperStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelSmall,
        fontWeight: FontWeight.w400,
        color: AppColors.bodyMuted,
      ),
      errorStyle: GoogleFonts.sora(
        fontSize: AppTextScale.labelSmall,
        fontWeight: FontWeight.w600,
        color: AppColors.danger,
      ),
      floatingLabelStyle: GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
      prefixIconColor: AppColors.bodySubtle,
      suffixIconColor: AppColors.bodySubtle,
    );
  }

  static InputDecoration search({String hintText = 'Search leads'}) {
    return standard(
      hintText: hintText,
      fillColor: AppColors.surface,
      prefixIcon: const Icon(Icons.search, size: AppSpacing.iconMd),
    );
  }

  static InputDecoration multiline({
    String? labelText,
    String? hintText,
    Color fillColor = AppColors.surface,
  }) {
    return standard(
      labelText: labelText,
      hintText: hintText,
      fillColor: fillColor,
    );
  }
}

ThemeData buildAppTheme() {
  final textTheme = AppTextStyles.buildTextTheme();
  const colorScheme = ColorScheme.light(
    primary: AppColors.primary,
    secondary: AppColors.blue600,
    surface: AppColors.surface,
    error: AppColors.danger,
    onPrimary: AppColors.surface,
    onSecondary: AppColors.body,
    onSurface: AppColors.body,
    onError: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: GoogleFonts.sora().fontFamily,
    scaffoldBackgroundColor: AppColors.pageBackground,
    canvasColor: AppColors.surface,
    textTheme: textTheme,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.charcoal800,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: AppColors.surface),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.body,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      titleTextStyle: GoogleFonts.sora(
        fontSize: AppTextScale.bodyMedium,
        fontWeight: FontWeight.w700,
        color: AppColors.body,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: AppColors.body),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: AppButtons.primary()),
    filledButtonTheme: FilledButtonThemeData(style: AppButtons.filled()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: AppButtons.outline()),
    textButtonTheme: TextButtonThemeData(style: AppButtons.text()),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: 14,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        borderSide: BorderSide(color: AppColors.primary, width: 1),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        borderSide: BorderSide(color: AppColors.danger, width: 1),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
        borderSide: BorderSide(color: AppColors.danger, width: 1),
      ),
      hintStyle: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.bodySubtle,
      ),
      labelStyle: GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.bodyMuted,
      ),
      helperStyle: textTheme.labelSmall?.copyWith(color: AppColors.bodyMuted),
      errorStyle: textTheme.labelSmall?.copyWith(color: AppColors.danger),
      floatingLabelStyle: GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
      prefixIconColor: AppColors.bodySubtle,
      suffixIconColor: AppColors.bodySubtle,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryLight,
      secondarySelectedColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.border, width: 1),
      labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.body),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: AppColors.bodyMuted,
      collapsedIconColor: AppColors.bodyMuted,
      textColor: AppColors.body,
      collapsedTextColor: AppColors.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: AppColors.border, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.surface;
      }),
      checkColor: WidgetStateProperty.all(AppColors.surface),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.surface;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.blue400;
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: AppSpacing.s4,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearMinHeight: AppSpacing.progressRegular,
    ),
  );
}
