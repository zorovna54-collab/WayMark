import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Scoped to map experiences; authentication and other screens keep their theme.
bool _fontLicenseRegistered = false;

Widget mapUiTheme(BuildContext context, Widget child) {
  if (!_fontLicenseRegistered) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Inter',
      ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    });
    _fontLicenseRegistered = true;
  }
  return Theme(
    data: Theme.of(context).copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.card,
      ),
      textTheme: Theme.of(context).textTheme
          .apply(fontFamily: 'Inter', bodyColor: AppColors.foreground),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    child: child,
  );
}
