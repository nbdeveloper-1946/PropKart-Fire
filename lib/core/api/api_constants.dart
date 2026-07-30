import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String primaryBaseUrl = "https://prop-kart-backend.vercel.app/api/v1";
  static const String backupBaseUrl = "https://nb-listings-backend.vercel.app/api/v1";

  /// Deployed Flutter web uses same-origin `/api/v1` (Vercel rewrite → backend)
  /// so HttpOnly cookies are first-party. Local web / mobile hit the API host directly.
  static String get baseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return '${Uri.base.origin}/api/v1';
      }
    }
    return primaryBaseUrl;
  }

  /// Prefer compile-time defines in CI:
  /// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
  /// Anon key is public-by-design for Supabase; security depends on RLS.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const login = "/auth/login";
  static const register = "/auth/register";
  static const me = "/auth/me";
  static const refresh = "/auth/refresh";
  static const logout = "/auth/logout";
  static const health = "/health";

  static void assertConfig() {
    if (kDebugMode && !hasSupabaseConfig) {
      debugPrint('ApiConstants: Supabase URL/anon key missing — realtime disabled.');
    }
  }
}
