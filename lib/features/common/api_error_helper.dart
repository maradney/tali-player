import '../../data/api/xtream_api_service.dart';
import '../../data/models/account.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/sources/m3u_media_source.dart';
import '../../l10n/app_localizations.dart';

/// Turns an API failure into a message for the error banner, localized via
/// the exception's machine-readable kind (the data layer builds its messages
/// without a BuildContext, so the English `message` is only a fallback).
///
/// A 429 that happens while the background catalog sync is running for this
/// account is almost certainly the sync eating the panel's request budget,
/// not a real outage - callers (Live TV/Movies/Series category screens) hit
/// this whenever indexing and browsing compete for the same rate limit.
String describeApiError(Object error, Account account, AppLocalizations l) {
  if (error is XtreamApiException) {
    if (error.isRateLimited &&
        CatalogSyncService.instance.isSyncingAccount(account)) {
      return l.tooManyRequests;
    }
    switch (error.kind) {
      case XtreamApiErrorKind.invalidCredentials:
        return l.errInvalidCredentials;
      case XtreamApiErrorKind.notXtreamPanel:
        return l.errNotXtreamPanel;
      case XtreamApiErrorKind.badResponse:
        return l.errBadResponse;
      case XtreamApiErrorKind.timeout:
        return l.errTimeout;
      case XtreamApiErrorKind.unreachable:
        return l.errUnreachable;
      case XtreamApiErrorKind.rateLimited:
        return l.errRateLimited;
      case XtreamApiErrorKind.unavailable:
        return l.errUnavailable;
      case XtreamApiErrorKind.other:
        return error.message; // carries specific detail worth showing as-is
    }
  }
  if (error is M3uException) return l.errNoChannelsInPlaylist;
  return error.toString();
}
