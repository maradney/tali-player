import '../../data/models/channel.dart';
import '../../data/models/epg_program.dart';

/// Whether [programme] on [channel] can be replayed right now: the channel
/// advertises an archive, the programme has already started (a currently-airing
/// show can be restarted from its beginning), and its start still falls inside
/// the archive window. Pure — [now] is injectable for tests.
bool catchupAvailable(Channel channel, EpgProgram programme, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return channel.tvArchive &&
      programme.start.isBefore(t) &&
      programme.start
          .isAfter(t.subtract(Duration(days: channel.tvArchiveDays)));
}
