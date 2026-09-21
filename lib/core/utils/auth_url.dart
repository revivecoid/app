/// URL helpers for the Supabase auth callback.
///
/// The app uses the hash URL strategy (Flutter web's default) because GitHub
/// Pages cannot rewrite unknown paths to index.html. That means an incoming
/// callback looks like `/#/auth/callback?code=...` or `/?code=...#/auth/callback`,
/// depending on how Supabase appends its parameters — so the PKCE code can sit
/// either in the query or inside the fragment after the router path.
library;

/// Extracts the PKCE `code` from an incoming URL, checking the query string
/// first and then the part of the fragment that follows the router path.
///
/// Returns null when no code is present (e.g. a plain page load, or an
/// implicit-flow URL that carries `access_token` instead).
String? readAuthCode(Uri uri) {
  final fromQuery = uri.queryParameters['code'];
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

  // With hash routing the fragment is `#/auth/callback?code=...`, which is not
  // a valid query string on its own — split it off the first '?' (and drop that
  // '?', which Uri.splitQueryString does not expect).
  final fragment = uri.fragment;
  final qIndex = fragment.indexOf('?');
  if (qIndex >= 0) {
    final fromFragment =
        Uri.splitQueryString(fragment.substring(qIndex + 1))['code'];
    if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
  }
  return null;
}
