import 'package:flutter/widgets.dart';
import 'package:re_v/l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppL get l10n => AppL.of(this) ?? lookupAppL(const Locale('en'));
}
