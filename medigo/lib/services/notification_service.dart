import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'dart:async';

/// Handles local notifications for drug box expirations
class NotificationService {
  NotificationService._();

  static const _prefsKeyEnabled = 'notif_expiry_enabled';
  static const _channelId = 'expiry_channel';
  static const _channelName = 'Péremption médicaments';
  static const _channelDesc = 'Alerte quand une boîte arrive à péremption';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static final StreamController<String> _payloadController =
      StreamController<String>.broadcast();
  static String? _initialPayload;

  /// Stream that emits payload strings when the user taps a notification.
  static Stream<String> get onTapPayload => _payloadController.stream;

  /// Retrieve and clear any payload used to launch the app from a notification.
  static String? takeInitialPayload() {
    final p = _initialPayload;
    _initialPayload = null;
    return p;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (kIsWeb) {
        _initialized = true;
        return;
      }
      // Timezone init (guard for web/testing)
      try {
        tzdata.initializeTimeZones();
      } catch (e) {
        debugPrint('tz init failed: $e');
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      final initSettings =
          const InitializationSettings(android: androidInit, iOS: iosInit);
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          try {
            final p = response.payload;
            if (p != null && p.isNotEmpty) {
              _payloadController.add(p);
            }
          } catch (e) {
            debugPrint('Notif tap handling failed: $e');
          }
        },
        // Background handler could be added if needed; foreground is sufficient for our use.
      );

      // Capture app launch details (when launched from a notification tap)
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        if (details?.didNotificationLaunchApp == true) {
          final p = details?.notificationResponse?.payload;
          if (p != null && p.isNotEmpty) {
            _initialPayload = p;
          }
        }
      } catch (e) {
        debugPrint('Read launch details failed: $e');
      }

      // Create the Android channel proactively
      const androidDetails = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        showBadge: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidDetails);

      // Ensure pref exists
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefsKeyEnabled)) {
        await prefs.setBool(_prefsKeyEnabled, true);
      }
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.initialize failed: $e');
    }
  }

  static Future<bool> isEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_prefsKeyEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyEnabled, enabled);
      if (enabled) {
        await requestPermissions();
      } else {
        await cancelAll();
      }
    } catch (e) {
      debugPrint('NotificationService.setEnabled failed: $e');
    }
  }

  static Future<void> requestPermissions() async {
    try {
      if (kIsWeb) return;
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // iOS
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        // macOS
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('NotificationService.requestPermissions failed: $e');
    }
  }

  /// Compute schedule time: 1st day of the expiry month at 09:00 local time
  static tz.TZDateTime _monthStartAtNineLocal(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final first = DateTime(local.year, local.month, 1, 9, 0, 0);
    return tz.TZDateTime.from(first, tz.local);
  }

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
  static int yyyymm(DateTime d) => d.year * 100 + d.month;
  static bool isExpiredMonth(DateTime expiry, DateTime now) {
    final e = yyyymm(expiry.toLocal());
    final n = yyyymm(now.toLocal());
    return e < n;
  }

  /// Schedule a unique notification per drug (cip13) and month
  static Future<void> scheduleMonthNotification(
      {required String cip13,
      required DateTime expiresAt,
      String? drugLabel}) async {
    try {
      if (kIsWeb) return;
      if (!await isEnabled()) return;
      final when = _monthStartAtNineLocal(expiresAt);
      if (when.isBefore(tz.TZDateTime.from(DateTime.now(), tz.local)))
        return; // don't schedule past

      final id = _buildId(cip13, expiresAt);
      final android = AndroidNotificationDetails(_channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high);
      const ios =
          DarwinNotificationDetails(presentAlert: true, presentSound: true);
      final details = NotificationDetails(android: android, iOS: ios);
      final mm = expiresAt.month.toString().padLeft(2, '0');
      final title = 'Péremption: $mm/${expiresAt.year}';
      final body = drugLabel != null
          ? 'Une boîte "$drugLabel" arrive à péremption.'
          : 'Une boîte arrive à péremption.';

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'cip13=$cip13&exp=${yyyymm(expiresAt)}',
      );
    } catch (e) {
      debugPrint('NotificationService.scheduleMonthNotification failed: $e');
    }
  }

  /// Notify immediately if the expiry is in the current month
  static Future<void> notifyIfCurrentMonth(
      {required String cip13,
      required DateTime expiresAt,
      String? drugLabel}) async {
    try {
      if (kIsWeb) return;
      if (!await isEnabled()) return;
      final now = DateTime.now();
      if (!isSameMonth(now, expiresAt)) return;
      final id = _buildId(cip13, expiresAt) +
          1; // small drift to avoid conflicting with scheduled id
      final android = AndroidNotificationDetails(_channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high);
      const ios =
          DarwinNotificationDetails(presentAlert: true, presentSound: true);
      final details = NotificationDetails(android: android, iOS: ios);
      final mm = expiresAt.month.toString().padLeft(2, '0');
      final title = 'Boîte à péremption $mm/${expiresAt.year}';
      final body = drugLabel != null
          ? 'Nouvel ajout: "$drugLabel" périt ce mois-ci.'
          : 'Nouvel ajout périt ce mois-ci.';
      await _plugin.show(id, title, body, details,
          payload: 'cip13=$cip13&exp=${yyyymm(expiresAt)}');
    } catch (e) {
      debugPrint('NotificationService.notifyIfCurrentMonth failed: $e');
    }
  }

  /// Cancel any scheduled notification for this drug-month.
  static Future<void> cancelFor(
      {required String cip13, required DateTime expiresAt}) async {
    try {
      if (kIsWeb) return;
      await _plugin.cancel(_buildId(cip13, expiresAt));
    } catch (e) {
      debugPrint('NotificationService.cancelFor failed: $e');
    }
  }

  static Future<void> cancelAll() async {
    try {
      if (kIsWeb) return;
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('NotificationService.cancelAll failed: $e');
    }
  }

  static int _buildId(String cip13, DateTime expiresAt) {
    final key = '${cip13}_${yyyymm(expiresAt)}';
    return key.hashCode & 0x7fffffff;
  }
}
