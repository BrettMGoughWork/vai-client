import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum StructuredLogLevel { trace, info, warning, error }

extension StructuredLogLevelX on StructuredLogLevel {
  String get wireName {
    switch (this) {
      case StructuredLogLevel.trace:
        return 'trace';
      case StructuredLogLevel.info:
        return 'info';
      case StructuredLogLevel.warning:
        return 'warning';
      case StructuredLogLevel.error:
        return 'error';
    }
  }

  int get developerLevel {
    switch (this) {
      case StructuredLogLevel.trace:
        return 300;
      case StructuredLogLevel.info:
        return 800;
      case StructuredLogLevel.warning:
        return 900;
      case StructuredLogLevel.error:
        return 1000;
    }
  }
}

class StructuredLogEntry {
  const StructuredLogEntry({
    required this.sequence,
    required this.timestamp,
    required this.subsystem,
    required this.event,
    required this.level,
    required this.fields,
  });

  final int sequence;
  final DateTime timestamp;
  final String subsystem;
  final String event;
  final StructuredLogLevel level;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sequence': sequence,
      'ts': timestamp.toUtc().toIso8601String(),
      'subsystem': subsystem,
      'event': event,
      'level': level.wireName,
      'fields': fields,
    };
  }

  String toJsonLine() => jsonEncode(toJson());
}

typedef StructuredLogSink = void Function(StructuredLogEntry entry);

class StructuredLogger {
  StructuredLogger({
    StructuredLogSink? sink,
    DateTime Function()? clock,
  })  : _sink = sink ?? developerStructuredLogSink,
        _clock = clock ?? DateTime.now;

  final StructuredLogSink _sink;
  final DateTime Function() _clock;
  int _sequence = 0;

  void trace(String subsystem, String event, [Map<String, Object?> fields = const <String, Object?>{}]) {
    _write(StructuredLogLevel.trace, subsystem, event, fields);
  }

  void info(String subsystem, String event, [Map<String, Object?> fields = const <String, Object?>{}]) {
    _write(StructuredLogLevel.info, subsystem, event, fields);
  }

  void warning(String subsystem, String event, [Map<String, Object?> fields = const <String, Object?>{}]) {
    _write(StructuredLogLevel.warning, subsystem, event, fields);
  }

  void error(String subsystem, String event, [Map<String, Object?> fields = const <String, Object?>{}]) {
    _write(StructuredLogLevel.error, subsystem, event, fields);
  }

  void _write(
    StructuredLogLevel level,
    String subsystem,
    String event,
    Map<String, Object?> fields,
  ) {
    _sequence += 1;
    _sink(
      StructuredLogEntry(
        sequence: _sequence,
        timestamp: _clock().toUtc(),
        subsystem: subsystem,
        event: event,
        level: level,
        fields: Map<String, Object?>.unmodifiable(fields),
      ),
    );
  }
}

void developerStructuredLogSink(StructuredLogEntry entry) {
  final String line = entry.toJsonLine();
  developer.log(
    line,
    name: 'vai.${entry.subsystem}',
    level: entry.level.developerLevel,
    time: entry.timestamp,
  );
  if (kDebugMode) {
    debugPrint(line);
  }
}

final StructuredLogger defaultStructuredLogger = StructuredLogger();
