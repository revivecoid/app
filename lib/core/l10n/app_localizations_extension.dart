import 'package:flutter/widgets.dart';
import 'app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppL get l10n => AppL.of(this) ?? lookupAppL(const Locale('en'));
}
