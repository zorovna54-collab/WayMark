import 'dart:collection';

class TrackingDiagnosticEvent {
  const TrackingDiagnosticEvent(
    this.timeUtc,
    this.generation,
    this.event,
    this.reason,
  );
  final DateTime timeUtc;
  final int generation;
  final String event, reason;
  // Only internal codes enter the timeline. Never accept payloads or IDs.
  String get sanitized =>
      '${timeUtc.toIso8601String()} g=$generation $event${reason.isEmpty ? '' : ' reason=$reason'}';
}

class TrackingTimeline {
  static const capacity = 96;
  final _events = ListQueue<TrackingDiagnosticEvent>();
  List<TrackingDiagnosticEvent> get events => List.unmodifiable(_events);
  void add(DateTime utc, int generation, String event, [String reason = '']) {
    if (_events.length == capacity) _events.removeFirst();
    _events.addLast(
      TrackingDiagnosticEvent(utc.toUtc(), generation, event, reason),
    );
  }
}
