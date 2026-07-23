import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/playback_progress.dart';
import 'package:iptv_player/data/services/playback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

PlaybackProgress _progress(
  String type,
  String id, {
  Duration position = const Duration(minutes: 5),
  Duration total = const Duration(minutes: 100),
  String? seriesId,
  int? seasonNumber,
  int? episodeNum,
  DateTime? updatedAt,
}) =>
    PlaybackProgress(
      type: type,
      id: id,
      position: position,
      total: total,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      episodeNum: episodeNum,
      updatedAt: updatedAt ?? DateTime.now(),
    );

void main() {
  final service = PlaybackService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('save then progressFor round-trips a position', () async {
    await service.loadFor(accountNamed('pb-save'));
    await service.save(_progress('movie', '120'));
    final p = service.progressFor('movie', '120');
    expect(p, isNotNull);
    expect(p!.position, const Duration(minutes: 5));
  });

  test('progressFraction is position/total, null when nothing tracked', () async {
    await service.loadFor(accountNamed('pb-frac'));
    await service.save(_progress('movie', '1',
        position: const Duration(minutes: 25), total: const Duration(minutes: 100)));
    expect(service.progressFraction('movie', '1'), closeTo(0.25, 1e-9));
    expect(service.progressFraction('movie', 'missing'), isNull);
  });

  test('progressFraction returns null for a zero-duration entry', () async {
    await service.loadFor(accountNamed('pb-zero'));
    await service.save(_progress('movie', '1', total: Duration.zero));
    expect(service.progressFraction('movie', '1'), isNull);
  });

  test('lastEpisodeForSeries returns the most recently updated episode', () async {
    await service.loadFor(accountNamed('pb-series'));
    final older = _progress('episode', '10',
        seriesId: '55', updatedAt: DateTime(2024, 1, 1));
    final newer = _progress('episode', '11',
        seriesId: '55', updatedAt: DateTime(2024, 6, 1));
    await service.save(older);
    await service.save(newer);

    expect(service.lastEpisodeForSeries('55')!.id, '11');
    expect(service.lastEpisodeForSeries('does-not-exist'), isNull);
  });

  test('isInProgress checks episodes for a series id', () async {
    await service.loadFor(accountNamed('pb-inprogress'));
    await service.save(_progress('episode', '11', seriesId: '55'));
    expect(service.isInProgress('series', '55'), isTrue);
    expect(service.isInProgress('series', '999'), isFalse);
    expect(service.isInProgress('movie', '11'), isFalse);
  });

  test('clear removes a tracked item and persists', () async {
    final account = accountNamed('pb-clear');
    await service.loadFor(account);
    await service.save(_progress('movie', '120'));
    await service.clear('movie', '120');
    expect(service.progressFor('movie', '120'), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('playback_v1_${account.key}'), isEmpty);
  });

  test('loadFor reads previously stored progress', () async {
    final account = accountNamed('pb-load');
    SharedPreferences.setMockInitialValues({
      'playback_v1_${account.key}': [
        jsonEncode(_progress('movie', '77').toJson()),
      ],
    });
    await service.loadFor(account);
    expect(service.progressFor('movie', '77'), isNotNull);
  });
}
