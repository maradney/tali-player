import 'package:flutter/foundation.dart';

/// One line in the in-memory session log.
class DiagnosticsEntry {
  final DateTime time;
  final String message;
  const DiagnosticsEntry(this.time, this.message);
}

/// A tiny in-memory, on-device ring buffer of notable events (API retries and
/// failures, connectivity checks) for the Diagnostics screen. Deliberately
/// NOT persisted and NOT sent anywhere — it's a debugging aid that lives only
/// for the session, in keeping with the project's zero-telemetry stance.
///
/// Callers must pass already-sanitized messages: never log a raw request URL,
/// since Xtream URLs carry the username/password as query params (use
/// [XtreamApiService.sanitizeErrorMessage] or log status/endpoint only).
class DiagnosticsLog extends ChangeNotifier {
  DiagnosticsLog._();
  static final DiagnosticsLog instance = DiagnosticsLog._();

  static const _maxEntries = 200;
  final List<DiagnosticsEntry> _entries = [];

  /// Oldest-first. The Diagnostics view shows them reversed (newest on top).
  List<DiagnosticsEntry> get entries => List.unmodifiable(_entries);

  void add(String message) {
    _entries.add(DiagnosticsEntry(DateTime.now(), message));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// The whole log as copy-pasteable text, oldest-first.
  String asText() => _entries
      .map((e) => '${e.time.toIso8601String()}  ${e.message}')
      .join('\n');
}
