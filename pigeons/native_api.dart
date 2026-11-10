// Typed contract definition for Flutter <-> native. Kept in the repository so the Pigeon channel
// can be generated later:
//
//   dart run pigeon --input pigeons/native_api.dart --dart_out lib/native/native_api.g.dart \
//        --kotlin_out android/app/src/main/kotlin/com/hamrah/app/NativeApi.g.kt
//
// The shipping implementation uses two MethodChannels with the exact same method names and JSON
// payloads (see NativeBridge.kt / native_bridge.dart), so no code generation is required to build.

import 'package:pigeon/pigeon.dart';

class AlarmPayload {
  String? occurrenceUid;
  String? reminderId;
  int? rev;
  String? title;
  int? scheduledFor;
  int? followupCount;
  int? followupIntervalMin;
  int? priority;
}

@HostApi()
abstract class HamrahNativeApi {
  int getContractVersion();

  @async
  String getDbKey();

  @async
  bool syncSnapshot(String snapshotJson);

  @async
  bool upsertAlarm(String alarmJson);

  @async
  bool cancelAlarm(String occurrenceUid);

  @async
  String drainInbox(int limit);

  @async
  bool ackInbox(String batchId);

  @async
  String getDiagnostics();

  @async
  String smsPermissionState();

  @async
  bool requestSmsPermission();

  @async
  String micPermissionState();

  @async
  bool requestMicPermission();

  @async
  String notificationPermissionState();

  @async
  bool requestNotificationPermission();

  @async
  bool canScheduleExactAlarms();

  @async
  void openExactAlarmSettings();

  @async
  void openAppDetails();

  @async
  void openNotificationSettings();

  @async
  void openBatterySettings();

  @async
  String? consumePendingRoute();

  @async
  bool restoreAlarms();
}
