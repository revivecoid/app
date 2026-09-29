import 'package:flutter/widgets.dart';
import 'package:revive/l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppL get l10n => AppL.of(this) ?? lookupAppL(const Locale('en'));
}
