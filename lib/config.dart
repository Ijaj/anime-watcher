/// Build-time configuration.
///
/// Override at build/run time with:
///   flutter run --dart-define=MAL_CLIENT_ID=<your client id>
///
/// A client ID or watched threshold set on the Settings page (stored in the
/// `settings` table) takes precedence over these defaults.
class AppConfig {
  static const String malClientId = String.fromEnvironment(
    'MAL_CLIENT_ID',
    defaultValue: '0e349e6cf6aa67da3ad146ec4d58d91d',
  );

  static const String malBaseUrl = 'https://api.myanimelist.net/v2';

  /// An episode counts as watched once this fraction of it has been played.
  static const double watchedThreshold = 0.9;
}
