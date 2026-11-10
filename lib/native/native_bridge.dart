import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class NativeException implements Exception {
  NativeException(this.code, this.message);
  final String code;
  final String? message;
  @override
  String toString() => 'NativeException($code${message == null ? '' : ': $message'})';
}

class NativeSms {
  NativeSms({
    required this.eventUid,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.parseStatus,
    required this.hash,
    this.templateId,
    this.bankCode,
    this.errorCode,
    this.partCount = 1,
  });

  final String eventUid;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final String parseStatus;
  final String hash;
  final String? templateId;
  final String? bankCode;
  final String? errorCode;
  final int partCount;

  factory NativeSms.fromJson(Map<String, dynamic> json) => NativeSms(
        eventUid: json['eventUid'] as String,
        sender: (json['sender'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        receivedAt: DateTime.fromMillisecondsSinceEpoch((json['receivedAt'] as num).toInt(), isUtc: true),
        parseStatus: (json['parseStatus'] ?? 'unrecognized') as String,
        hash: (json['hash'] ?? '') as String,
        templateId: json['templateId'] as String?,
        bankCode: json['bankCode'] as String?,
        errorCode: json['errorCode'] as String?,
        partCount: (json['partCount'] as num?)?.toInt() ?? 1,
      );
}

class NativeTx {
  NativeTx({
    required this.txUid,
    required this.smsEventUid,
    required this.smsHash,
    required this.bankCode,
    required this.accountHint,
    required this.direction,
    required this.amountRial,
    required this.occurredAt,
    required this.timeSource,
    required this.label,
    required this.balanceAfterRial,
    required this.suggestionKey,
    this.counterparty,
    this.counterpartySource,
    this.purposeText,
  });

  final String txUid;
  final String smsEventUid;
  final String smsHash;
  final String bankCode;
  final String accountHint;
  final String direction;
  final int amountRial;
  final DateTime occurredAt;
  final String timeSource;
  final String label;
  final int balanceAfterRial;
  final String suggestionKey;
  final String? counterparty;
  final String? counterpartySource;
  final String? purposeText;

  factory NativeTx.fromJson(Map<String, dynamic> json) => NativeTx(
        txUid: json['txUid'] as String,
        smsEventUid: (json['smsEventUid'] ?? '') as String,
        smsHash: (json['smsHash'] ?? '') as String,
        bankCode: (json['bankCode'] ?? '') as String,
        accountHint: (json['accountHint'] ?? '') as String,
        direction: (json['direction'] ?? 'out') as String,
        amountRial: (json['amountRial'] as num).toInt(),
        occurredAt: DateTime.fromMillisecondsSinceEpoch((json['occurredAt'] as num).toInt(), isUtc: true),
        timeSource: (json['timeSource'] ?? 'received') as String,
        label: (json['label'] ?? '') as String,
        balanceAfterRial: (json['balanceAfterRial'] as num).toInt(),
        suggestionKey: (json['suggestionKey'] ?? '') as String,
        counterparty: json['counterparty'] as String?,
        counterpartySource: json['counterpartySource'] as String?,
        purposeText: json['purposeText'] as String?,
      );
}

class NativeResolution {
  NativeResolution({
    required this.eventUid,
    required this.txUid,
    required this.action,
    required this.createdAt,
    this.categoryId,
    this.note,
  });

  final String eventUid;
  final String txUid;
  final String action;
  final DateTime createdAt;
  final String? categoryId;
  final String? note;

  factory NativeResolution.fromJson(Map<String, dynamic> json) => NativeResolution(
        eventUid: json['eventUid'] as String,
        txUid: json['txUid'] as String,
        action: (json['action'] ?? '') as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt(), isUtc: true),
        categoryId: json['categoryId'] as String?,
        note: json['note'] as String?,
      );
}

class NativeOutcome {
  NativeOutcome({
    required this.eventUid,
    required this.occurrenceUid,
    required this.reminderId,
    required this.rev,
    required this.outcome,
    required this.resolvedAt,
    this.snoozedUntil,
  });

  final String eventUid;
  final String occurrenceUid;
  final String reminderId;
  final int rev;
  final String outcome;
  final DateTime resolvedAt;
  final DateTime? snoozedUntil;

  factory NativeOutcome.fromJson(Map<String, dynamic> json) => NativeOutcome(
        eventUid: json['eventUid'] as String,
        occurrenceUid: json['occurrenceUid'] as String,
        reminderId: json['reminderId'] as String,
        rev: (json['rev'] as num).toInt(),
        outcome: (json['outcome'] ?? '') as String,
        resolvedAt: DateTime.fromMillisecondsSinceEpoch((json['resolvedAt'] as num).toInt(), isUtc: true),
        snoozedUntil: json['snoozedUntil'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['snoozedUntil'] as num).toInt(), isUtc: true),
      );
}

class NativeOccurrence {
  NativeOccurrence({
    required this.eventUid,
    required this.occurrenceUid,
    required this.reminderId,
    required this.rev,
    required this.title,
    required this.scheduledFor,
    required this.reason,
  });

  final String eventUid;
  final String occurrenceUid;
  final String reminderId;
  final int rev;
  final String title;
  final DateTime scheduledFor;
  final String reason;

  factory NativeOccurrence.fromJson(Map<String, dynamic> json) => NativeOccurrence(
        eventUid: json['eventUid'] as String,
        occurrenceUid: json['occurrenceUid'] as String,
        reminderId: json['reminderId'] as String,
        rev: (json['rev'] as num).toInt(),
        title: (json['title'] ?? '') as String,
        scheduledFor: DateTime.fromMillisecondsSinceEpoch((json['scheduledFor'] as num).toInt(), isUtc: true),
        reason: (json['reason'] ?? '') as String,
      );
}

class NativeBatch {
  NativeBatch({
    required this.batchId,
    required this.contractVersion,
    required this.sms,
    required this.transactions,
    required this.resolutions,
    required this.outcomes,
    required this.occurrences,
  });

  final String batchId;
  final int contractVersion;
  final List<NativeSms> sms;
  final List<NativeTx> transactions;
  final List<NativeResolution> resolutions;
  final List<NativeOutcome> outcomes;
  final List<NativeOccurrence> occurrences;

  bool get isEmpty =>
      sms.isEmpty && transactions.isEmpty && resolutions.isEmpty && outcomes.isEmpty && occurrences.isEmpty;

  factory NativeBatch.fromJson(Map<String, dynamic> json) => NativeBatch(
        batchId: json['batchId'] as String,
        contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
        sms: ((json['sms'] as List?) ?? const [])
            .map((e) => NativeSms.fromJson(e as Map<String, dynamic>))
            .toList(),
        transactions: ((json['transactions'] as List?) ?? const [])
            .map((e) => NativeTx.fromJson(e as Map<String, dynamic>))
            .toList(),
        resolutions: ((json['resolutions'] as List?) ?? const [])
            .map((e) => NativeResolution.fromJson(e as Map<String, dynamic>))
            .toList(),
        outcomes: ((json['outcomes'] as List?) ?? const [])
            .map((e) => NativeOutcome.fromJson(e as Map<String, dynamic>))
            .toList(),
        occurrences: ((json['occurrences'] as List?) ?? const [])
            .map((e) => NativeOccurrence.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class NativeBridge {
  NativeBridge({MethodChannel? channel, MethodChannel? events})
      : _channel = channel ?? const MethodChannel('com.hamrah.app/native'),
        _events = events ?? const MethodChannel('com.hamrah.app/events');

  static const contractVersion = 1;

  final MethodChannel _channel;
  final MethodChannel _events;

  void onRoute(void Function(String route) handler) {
    _events.setMethodCallHandler((call) async {
      if (call.method == 'route' && call.arguments is String) {
        handler(call.arguments as String);
      }
      return null;
    });
  }

  Future<T> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null) throw NativeException('empty_result', method);
      return result;
    } on PlatformException catch (e) {
      throw NativeException(e.code, e.message);
    } on MissingPluginException {
      throw NativeException('not_android', method);
    }
  }

  Future<String> dbKey() => _invoke<String>('getDbKey');

  Future<void> syncSnapshot(Map<String, dynamic> snapshot) =>
      _invoke<bool>('syncSnapshot', {'json': jsonEncode(snapshot)});

  Future<bool> upsertAlarm(Map<String, dynamic> alarm) async =>
      (await _invoke<bool>('upsertAlarm', {'json': jsonEncode(alarm)})) != false;

  Future<void> cancelAlarm(String occurrenceUid) =>
      _invoke<bool>('cancelAlarm', {'occurrenceUid': occurrenceUid});

  Future<NativeBatch> drainInbox({int limit = 100}) async {
    final raw = await _invoke<String>('drainInbox', {'limit': limit});
    return NativeBatch.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> ackInbox(String batchId) => _invoke<bool>('ackInbox', {'batchId': batchId});

  Future<Map<String, dynamic>> diagnostics() async {
    final raw = await _invoke<String>('getDiagnostics');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> smsPermissionState() => _invoke<String>('smsPermissionState');

  Future<bool> requestSmsPermission() async => (await _invoke<bool>('requestSmsPermission')) != false;

  Future<String> micPermissionState() => _invoke<String>('micPermissionState');

  Future<bool> requestMicPermission() async => (await _invoke<bool>('requestMicPermission')) != false;

  Future<String> notificationPermissionState() => _invoke<String>('notificationPermissionState');

  Future<bool> requestNotificationPermission() async =>
      (await _invoke<bool>('requestNotificationPermission')) != false;

  Future<bool> canScheduleExactAlarms() async => (await _invoke<bool>('canScheduleExactAlarms')) != false;

  Future<void> openExactAlarmSettings() => _invoke<bool>('openExactAlarmSettings');

  Future<void> openAppDetails() => _invoke<bool>('openAppDetails');

  Future<void> openNotificationSettings() => _invoke<bool>('openNotificationSettings');

  Future<void> openBatterySettings() => _invoke<bool>('openBatterySettings');

  Future<String?> consumePendingRoute() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingRoute');
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> restoreAlarms() => _invoke<bool>('restoreAlarms');
}
