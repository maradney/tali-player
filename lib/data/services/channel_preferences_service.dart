import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/channel.dart';

/// How the Live TV channel list is ordered.
enum ChannelSort { providerDefault, nameAsc, nameDesc }

/// Per-account Live TV channel preferences: which channels are hidden, and
/// how the list is sorted. Same singleton/ChangeNotifier/per-account
/// SharedPreferences shape as FavoritesService/PinLockService. Hidden ids are
/// inherently per-account (stream ids only mean something within one panel);
/// the sort lives here too so it's all wiped together with the account.
class ChannelPreferencesService extends ChangeNotifier {
  ChannelPreferencesService._();
  static final ChannelPreferencesService instance =
      ChannelPreferencesService._();

  static String _prefsKeyFor(String accountKey) => 'channel_prefs_v1_$accountKey';

  Set<String> _hidden = {};
  ChannelSort _sort = ChannelSort.providerDefault;
  String? _loadedAccountKey;

  ChannelSort get sortOrder => _sort;
  bool isHidden(String streamId) => _hidden.contains(streamId);
  int get hiddenCount => _hidden.length;

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyFor(account.key));
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _hidden = Set<String>.from(map['hidden'] as List? ?? []);
        _sort = ChannelSort.values.firstWhere(
          (s) => s.name == map['sort'],
          orElse: () => ChannelSort.providerDefault,
        );
      } catch (_) {
        _hidden = {};
        _sort = ChannelSort.providerDefault;
      }
    } else {
      _hidden = {};
      _sort = ChannelSort.providerDefault;
    }
    _loadedAccountKey = account.key;
    notifyListeners();
  }

  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _hidden = {};
      _sort = ChannelSort.providerDefault;
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  Future<void> setHidden(String streamId, bool hidden) async {
    final changed = hidden ? _hidden.add(streamId) : _hidden.remove(streamId);
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<void> setSortOrder(ChannelSort sort) async {
    if (sort == _sort) return;
    _sort = sort;
    notifyListeners();
    await _persist();
  }

  /// Applies the current hide + sort preferences to [channels], returning a
  /// new list (the input is never mutated). Hidden channels are dropped
  /// unless [includeHidden] is set (used by the "show hidden" view so they
  /// can be un-hidden).
  List<Channel> apply(List<Channel> channels, {bool includeHidden = false}) {
    final list = includeHidden
        ? List<Channel>.of(channels)
        : channels.where((c) => !_hidden.contains(c.streamId)).toList();
    switch (_sort) {
      case ChannelSort.providerDefault:
        break; // keep the panel's original order
      case ChannelSort.nameAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ChannelSort.nameDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }
    return list;
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyFor(accountKey),
      jsonEncode({'sort': _sort.name, 'hidden': _hidden.toList()}),
    );
  }
}
