import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_reading.dart';
import '../models/risk_score.dart';
import '../models/alert.dart';
import '../models/user_profile.dart';

/// Local storage service using Hive and SharedPreferences
/// No internet/Firebase connection needed - everything stored on device
class StorageService {
  // Singleton pattern
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // Hive box names
  static const String _readingsBox = 'sensor_readings';
  static const String _riskScoresBox = 'risk_scores';
  static const String _alertsBox = 'alerts';
  static const String _userProfileBox = 'user_profile';
  static const String _dailySummaryBox = 'daily_summaries';

  // SharedPreferences keys
  static const String _keyLastSync = 'last_sync_time';
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keySelectedTheme = 'selected_theme';
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyDeviceId = 'paired_device_id';
  static const String _keyDeviceName = 'paired_device_name';
  static const String _keyUserPin = 'user_pin'; // PIN for app security

  // Hive boxes
  late Box<Map> _readingsBoxInstance;
  late Box<Map> _riskScoresBoxInstance;
  late Box<Map> _alertsBoxInstance;
  late Box<Map> _userProfileBoxInstance;
  late Box<Map> _dailySummaryBoxInstance;

  // SharedPreferences instance
  SharedPreferences? _prefs;

  bool _isInitialized = false;

  // ============== Initialization ==============

  /// Initialize storage - call this in main.dart before runApp()
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Hive (local database)
      await Hive.initFlutter();

      // Open Hive boxes (like tables)
      _readingsBoxInstance = await Hive.openBox<Map>(_readingsBox);
      _riskScoresBoxInstance = await Hive.openBox<Map>(_riskScoresBox);
      _alertsBoxInstance = await Hive.openBox<Map>(_alertsBox);
      _userProfileBoxInstance = await Hive.openBox<Map>(_userProfileBox);
      _dailySummaryBoxInstance = await Hive.openBox<Map>(_dailySummaryBox);

      // Initialize SharedPreferences (for simple key-value settings)
      _prefs = await SharedPreferences.getInstance();

      _isInitialized = true;
    } catch (e) {
      print('StorageService initialization error: $e');
      rethrow;
    }
  }

  /// Check if storage is initialized
  bool get isInitialized => _isInitialized;

  // ============== Sensor Readings ==============

  /// Save a sensor reading
  Future<void> saveReading(SensorReading reading) async {
    final key = reading.timestamp.millisecondsSinceEpoch.toString();
    await _readingsBoxInstance.put(key, reading.toJson());
  }

  /// Save multiple readings (batch)
  Future<void> saveReadings(List<SensorReading> readings) async {
    final entries = <String, Map<String, dynamic>>{};
    for (final reading in readings) {
      final key = reading.timestamp.millisecondsSinceEpoch.toString();
      entries[key] = reading.toJson();
    }
    await _readingsBoxInstance.putAll(entries);
  }

  /// Get all readings
  List<SensorReading> getAllReadings() {
    return _readingsBoxInstance.values
        .map((json) => SensorReading.fromJson(Map<String, dynamic>.from(json)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
  }

  /// Get readings for a specific date
  List<SensorReading> getReadingsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return getAllReadings()
        .where((r) =>
            r.timestamp.isAfter(startOfDay) && r.timestamp.isBefore(endOfDay))
        .toList();
  }

  /// Get readings from last N hours
  List<SensorReading> getRecentReadings(int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return getAllReadings().where((r) => r.timestamp.isAfter(cutoff)).toList();
  }

  /// Get the latest reading
  SensorReading? getLatestReading() {
    final readings = getAllReadings();
    return readings.isNotEmpty ? readings.first : null;
  }

  /// Delete readings older than specified days
  Future<int> deleteOldReadings(int daysToKeep) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
    final keysToDelete = <String>[];

    for (final key in _readingsBoxInstance.keys) {
      final timestamp = int.tryParse(key.toString());
      if (timestamp != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (date.isBefore(cutoff)) {
          keysToDelete.add(key.toString());
        }
      }
    }

    for (final key in keysToDelete) {
      await _readingsBoxInstance.delete(key);
    }

    return keysToDelete.length;
  }

  /// Get reading count
  int get readingCount => _readingsBoxInstance.length;

  // ============== Risk Scores ==============

  /// Save a risk score
  Future<void> saveRiskScore(RiskScore score) async {
    final key = score.timestamp.millisecondsSinceEpoch.toString();
    await _riskScoresBoxInstance.put(key, score.toJson());
  }

  /// Get all risk scores
  List<RiskScore> getAllRiskScores() {
    return _riskScoresBoxInstance.values
        .map((json) => RiskScore.fromJson(Map<String, dynamic>.from(json)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Get risk scores for date range
  List<RiskScore> getRiskScoresForRange(DateTime start, DateTime end) {
    return getAllRiskScores()
        .where((r) =>
            r.timestamp.isAfter(start) &&
            r.timestamp.isBefore(end.add(const Duration(days: 1))))
        .toList();
  }

  /// Get average risk score for a date
  double? getAverageRiskForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final scores = getAllRiskScores()
        .where((r) =>
            r.timestamp.isAfter(startOfDay) && r.timestamp.isBefore(endOfDay))
        .toList();

    if (scores.isEmpty) return null;

    final sum = scores.fold(0, (sum, s) => sum + s.overallScore);
    return sum / scores.length;
  }

  /// Get latest risk score
  RiskScore? getLatestRiskScore() {
    final scores = getAllRiskScores();
    return scores.isNotEmpty ? scores.first : null;
  }

  // ============== Alerts ==============

  /// Save an alert
  Future<void> saveAlert(Alert alert) async {
    await _alertsBoxInstance.put(alert.id, alert.toJson());
  }

  /// Save multiple alerts
  Future<void> saveAlerts(List<Alert> alerts) async {
    final entries = <String, Map<String, dynamic>>{};
    for (final alert in alerts) {
      entries[alert.id] = alert.toJson();
    }
    await _alertsBoxInstance.putAll(entries);
  }

  /// Get all alerts
  List<Alert> getAllAlerts() {
    return _alertsBoxInstance.values
        .map((json) => Alert.fromJson(Map<String, dynamic>.from(json)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Get unread alerts
  List<Alert> getUnreadAlerts() {
    return getAllAlerts().where((a) => !a.isRead).toList();
  }

  /// Update alert (mark as read)
  Future<void> updateAlert(Alert alert) async {
    await _alertsBoxInstance.put(alert.id, alert.toJson());
  }

  /// Delete an alert
  Future<void> deleteAlert(String alertId) async {
    await _alertsBoxInstance.delete(alertId);
  }

  /// Clear all alerts
  Future<void> clearAllAlerts() async {
    await _alertsBoxInstance.clear();
  }

  // ============== User Profile ==============

  /// Save user profile
  Future<void> saveUserProfile(UserProfile profile) async {
    await _userProfileBoxInstance.put('current_user', profile.toJson());
  }

  /// Get user profile
  UserProfile? getUserProfile() {
    final json = _userProfileBoxInstance.get('current_user');
    if (json == null) return null;
    return UserProfile.fromJson(Map<String, dynamic>.from(json));
  }

  /// Delete user profile
  Future<void> deleteUserProfile() async {
    await _userProfileBoxInstance.delete('current_user');
  }

  // ============== Daily Summaries ==============

  /// Save daily summary
  Future<void> saveDailySummary(DailyRiskSummary summary) async {
    final key = '${summary.date.year}-${summary.date.month}-${summary.date.day}';
    await _dailySummaryBoxInstance.put(key, summary.toJson());
  }

  /// Get daily summary for a date
  DailyRiskSummary? getDailySummary(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    final json = _dailySummaryBoxInstance.get(key);
    if (json == null) return null;
    return DailyRiskSummary.fromJson(Map<String, dynamic>.from(json));
  }

  /// Get summaries for date range
  List<DailyRiskSummary> getSummariesForRange(DateTime start, DateTime end) {
    final summaries = <DailyRiskSummary>[];
    var current = start;

    while (!current.isAfter(end)) {
      final summary = getDailySummary(current);
      if (summary != null) {
        summaries.add(summary);
      }
      current = current.add(const Duration(days: 1));
    }

    return summaries;
  }

  // ============== Settings (SharedPreferences) ==============

  /// Get last sync time
  DateTime? getLastSyncTime() {
    final millis = _prefs?.getInt(_keyLastSync);
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  /// Set last sync time
  Future<void> setLastSyncTime(DateTime time) async {
    await _prefs?.setInt(_keyLastSync, time.millisecondsSinceEpoch);
  }

  /// Check if onboarding is complete
  bool isOnboardingComplete() {
    return _prefs?.getBool(_keyOnboardingComplete) ?? false;
  }

  /// Set onboarding complete
  Future<void> setOnboardingComplete(bool complete) async {
    await _prefs?.setBool(_keyOnboardingComplete, complete);
  }

  /// Get selected theme (light/dark/system)
  String getSelectedTheme() {
    return _prefs?.getString(_keySelectedTheme) ?? 'system';
  }

  /// Set selected theme
  Future<void> setSelectedTheme(String theme) async {
    await _prefs?.setString(_keySelectedTheme, theme);
  }

  /// Check if notifications are enabled
  bool areNotificationsEnabled() {
    return _prefs?.getBool(_keyNotificationsEnabled) ?? true;
  }

  /// Set notifications enabled
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs?.setBool(_keyNotificationsEnabled, enabled);
  }

  /// Get paired device ID
  String? getPairedDeviceId() {
    return _prefs?.getString(_keyDeviceId);
  }

  /// Set paired device
  Future<void> setPairedDevice(String? id, String? name) async {
    if (id != null) {
      await _prefs?.setString(_keyDeviceId, id);
      await _prefs?.setString(_keyDeviceName, name ?? '');
    } else {
      await _prefs?.remove(_keyDeviceId);
      await _prefs?.remove(_keyDeviceName);
    }
  }

  /// Get paired device name
  String? getPairedDeviceName() {
    return _prefs?.getString(_keyDeviceName);
  }

  // ============== PIN Management ==============

  /// Save user PIN to persistent storage
  Future<void> savePIN(String pin) async {
    await _prefs?.setString(_keyUserPin, pin);
  }

  /// Get stored PIN (returns null if not set)
  String? getPIN() {
    return _prefs?.getString(_keyUserPin);
  }

  /// Check if PIN exists
  bool isPinSet() {
    return _prefs?.containsKey(_keyUserPin) ?? false;
  }

  /// Clear PIN (reset authentication)
  Future<void> clearPIN() async {
    await _prefs?.remove(_keyUserPin);
  }

  // ============== Storage Management ==============

  /// Get total storage size (approximate)
  int getStorageSize() {
    int size = 0;
    size += _readingsBoxInstance.length * 500; // ~500 bytes per reading
    size += _riskScoresBoxInstance.length * 300;
    size += _alertsBoxInstance.length * 400;
    return size;
  }

  /// Get storage size in MB
  double getStorageSizeMB() {
    return getStorageSize() / (1024 * 1024);
  }

  /// Clear all data (factory reset)
  Future<void> clearAllData() async {
    await _readingsBoxInstance.clear();
    await _riskScoresBoxInstance.clear();
    await _alertsBoxInstance.clear();
    await _userProfileBoxInstance.clear();
    await _dailySummaryBoxInstance.clear();
    await _prefs?.clear();
  }

  /// Export all data as JSON (for backup)
  Map<String, dynamic> exportData() {
    return {
      'exportDate': DateTime.now().toIso8601String(),
      'readings': getAllReadings().map((r) => r.toJson()).toList(),
      'riskScores': getAllRiskScores().map((r) => r.toJson()).toList(),
      'alerts': getAllAlerts().map((a) => a.toJson()).toList(),
      'userProfile': getUserProfile()?.toJson(),
      'settings': {
        'theme': getSelectedTheme(),
        'notifications': areNotificationsEnabled(),
        'onboardingComplete': isOnboardingComplete(),
      },
    };
  }

  /// Close all boxes (call on app exit)
  Future<void> close() async {
    await _readingsBoxInstance.close();
    await _riskScoresBoxInstance.close();
    await _alertsBoxInstance.close();
    await _userProfileBoxInstance.close();
    await _dailySummaryBoxInstance.close();
  }
}
