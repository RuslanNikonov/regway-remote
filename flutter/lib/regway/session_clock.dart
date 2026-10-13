/// Session timer independent of toolbar collapse/dispose (C1).
class RwSessionClock {
  RwSessionClock._();
  static final _started = <String, DateTime>{};

  static DateTime markStart(String id) {
    return _started.putIfAbsent(id, DateTime.now);
  }

  static DateTime? startedAt(String id) => _started[id];

  static Duration? elapsed(String id) {
    final s = _started[id];
    if (s == null) return null;
    return DateTime.now().difference(s);
  }

  static Duration? end(String id) {
    final s = _started.remove(id);
    if (s == null) return null;
    return DateTime.now().difference(s);
  }

  static String format(Duration d) {
    two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
}
