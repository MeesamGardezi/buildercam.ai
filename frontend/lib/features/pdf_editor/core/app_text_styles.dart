import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme buildTextTheme() {
    final base = GoogleFonts.soraTextTheme();

    return base.copyWith(
      displayLarge: GoogleFonts.sora(
        fontSize: AppTextScale.displayLarge,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        height: 1.0,
        color: AppColors.body,
      ),
      displayMedium: GoogleFonts.sora(
        fontSize: AppTextScale.displayMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        height: 1.1,
        color: AppColors.body,
      ),
      displaySmall: GoogleFonts.sora(
        fontSize: AppTextScale.displaySmall,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        color: AppColors.body,
      ),
      headlineLarge: GoogleFonts.sora(
        fontSize: AppTextScale.headlineLarge,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.body,
      ),
      titleLarge: GoogleFonts.sora(
        fontSize: AppTextScale.titleLarge,
        fontWeight: FontWeight.w600,
        color: AppColors.body,
      ),
      titleMedium: GoogleFonts.sora(
        fontSize: AppTextScale.titleMedium,
        fontWeight: FontWeight.w700,
        color: AppColors.body,
      ),
      titleSmall: GoogleFonts.sora(
        fontSize: AppTextScale.titleSmall,
        fontWeight: FontWeight.w700,
        color: AppColors.body,
      ),
      bodyLarge: GoogleFonts.sora(
        fontSize: AppTextScale.bodyLarge,
        fontWeight: FontWeight.w400,
        height: 1.7,
        color: AppColors.body,
      ),
      bodyMedium: GoogleFonts.sora(
        fontSize: AppTextScale.bodyMedium,
        fontWeight: FontWeight.w400,
        height: 1.7,
        color: AppColors.body,
      ),
      bodySmall: GoogleFonts.sora(
        fontSize: AppTextScale.bodySmall,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.bodyMuted,
      ),
      labelLarge: GoogleFonts.sora(
        fontSize: AppTextScale.labelLarge,
        fontWeight: FontWeight.w600,
        color: AppColors.body,
      ),
      labelMedium: GoogleFonts.sora(
        fontSize: AppTextScale.labelMedium,
        fontWeight: FontWeight.w600,
        color: AppColors.body,
      ),
      labelSmall: GoogleFonts.sora(
        fontSize: AppTextScale.labelSmall,
        fontWeight: FontWeight.w700,
        color: AppColors.bodyMuted,
      ),
    );
  }
}

class AppTextScale {
  AppTextScale._();

  static const double displayLarge = 60;
  static const double displayMedium = 44;
  static const double displaySmall = 34;
  static const double headlineLarge = 26;
  static const double titleLarge = 20;
  static const double titleMedium = 17;
  static const double titleSmall = 15;
  static const double bodyLarge = 17;
  static const double bodyMedium = 15;
  static const double bodySmall = 13;
  static const double labelLarge = 15;
  static const double labelMedium = 13;
  static const double labelSmall = 11;
}
