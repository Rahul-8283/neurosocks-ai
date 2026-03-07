// Processes readings → risk scores, manages alerts, daily summaries
// ✅ ESP32 Edge ML: Uses predictions from hardware with threshold fallback
// ✅ Firestore: Alerts & predictions stored user-specific

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/sensor_reading.dart';
import '../data/models/risk_score.dart';
import '../data/models/alert.dart';
import '../data/services/risk_calculator.dart';
import '../data/services/alert_service.dart';
import '../data/services/storage_service.dart';
import '../data/services/firebase/firebase_firestore_service.dart';

/// Provider for managing risk calculations and alerts
class RiskProvider extends ChangeNotifier {
  // Singleton pattern - ensure only one instance exists globally
  static final RiskProvider _instance = RiskProvider._internal();
  
  factory RiskProvider() {
    return _instance;
  }
  
  RiskProvider._internal() {
    // Listen to alert stream
    _alertSubscription = _alertService.alertStream.listen(_onNewAlert);
    
    // Load initial data
    _loadInitialData();
  }
  
  final RiskCalculator _riskCalculator = RiskCalculator();
  final AlertService _alertService = AlertService();
  final StorageService _storageService = StorageService();
  final FirebaseFirestoreService _firestoreService = FirebaseFirestoreService();

  // User context for Firestore
  String? _currentUserId;

  // Current state
  RiskScore? _currentRiskScore;
  RiskLevel _currentRiskLevel = RiskLevel.low;
  List<Alert> _alerts = [];
  int _unreadAlertCount = 0;

  // Historical data
  final List<RiskScore> _riskHistory = [];
  static const int _maxHistorySize = 100;

  // Daily tracking
  DailyRiskSummary? _todaySummary;
  final List<DailyRiskSummary> _weekSummaries = [];

  // Alert stream subscription
  StreamSubscription<Alert>? _alertSubscription;

  // ============== Constructor ==============

  // Removed legacy constructor - now using singleton factory pattern

  // ============== Getters ==============

  RiskScore? get currentRiskScore => _currentRiskScore;
  RiskLevel get currentRiskLevel => _currentRiskLevel;
  int get currentScore => _currentRiskScore?.overallScore ?? 0;
  List<Alert> get alerts => List.unmodifiable(_alerts);
  int get unreadAlertCount => _unreadAlertCount;
  bool get hasUnreadAlerts => _unreadAlertCount > 0;
  bool get hasCriticalAlerts => _alertService.hasCriticalUnread;
  List<RiskScore> get riskHistory => List.unmodifiable(_riskHistory);
  DailyRiskSummary? get todaySummary => _todaySummary;
  List<DailyRiskSummary> get weekSummaries => List.unmodifiable(_weekSummaries);

  // Component scores
  int get temperatureRisk => _currentRiskScore?.temperatureRisk ?? 0;
  int get pressureRisk => _currentRiskScore?.pressureRisk ?? 0;
  int get circulationRisk => _currentRiskScore?.circulationRisk ?? 0;
  int get gaitRisk => _currentRiskScore?.gaitRisk ?? 0;

  // Risk factors and recommendations
  List<String> get riskFactors => _currentRiskScore?.factors ?? [];
  List<String> get recommendations => _currentRiskScore?.recommendations ?? [];

  // Alert stats
  AlertStats get alertStats => _alertService.getStats();

  // ============== User Context ==============

  /// Set the current user ID for Firestore operations
  void setCurrentUser(String userId) {
    _currentUserId = userId;
    // Load alerts from Firestore for this user
    _loadAlertsFromFirestore();
  }

  /// Clear user context on logout
  void clearCurrentUser() {
    _currentUserId = null;
  }

  // ============== Risk Calculation ==============

  /// Process a sensor reading and calculate risk
  void processReading(SensorReading reading) {
    // Calculate risk score
    final riskScore = _riskCalculator.calculate(reading);
    _currentRiskScore = riskScore;
    _currentRiskLevel = riskScore.riskLevel;

    // Add to history
    _riskHistory.insert(0, riskScore);
    if (_riskHistory.length > _maxHistorySize) {
      _riskHistory.removeLast();
    }

    // Save to storage (async)
    _storageService.saveRiskScore(riskScore);

    // Save to Firestore if user is logged in
    if (_currentUserId != null) {
      unawaited(_firestoreService.saveRiskScore(
        userId: _currentUserId!,
        riskScore: riskScore,
      ));
    }

    // Check for alerts
    final newAlerts = _alertService.checkForAlerts(reading);
    
    // Save any new alerts (local + Firestore)
    for (final alert in newAlerts) {
      _storageService.saveAlert(alert);
      _saveAlertToFirestore(alert);
    }

    // Save ML prediction to Firestore
    _savePredictionToFirestore(riskScore, reading);

    // Update today's summary
    _updateTodaySummary(riskScore);

    // Refresh alerts list
    _refreshAlerts();

    notifyListeners();
  }

  /// Update today's daily summary
  void _updateTodaySummary(RiskScore score) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    if (_todaySummary == null || 
        _todaySummary!.date.isBefore(todayStart)) {
      // Start new day
      _todaySummary = DailyRiskSummary(
        date: todayStart,
        averageScore: score.overallScore,
        highestScore: score.overallScore,
        lowestScore: score.overallScore,
        readingCount: 1,
        alertCount: 0,
        dominantRiskLevel: score.riskLevel,
        keyFactors: score.factors,
      );
    } else {
      // Update existing summary
      final currentCount = _todaySummary!.readingCount;
      final newCount = currentCount + 1;
      final newAverage = ((_todaySummary!.averageScore * currentCount) + 
          score.overallScore) / newCount;

      _todaySummary = DailyRiskSummary(
        date: _todaySummary!.date,
        averageScore: newAverage.round(),
        highestScore: score.overallScore > _todaySummary!.highestScore
            ? score.overallScore
            : _todaySummary!.highestScore,
        lowestScore: score.overallScore < _todaySummary!.lowestScore
            ? score.overallScore
            : _todaySummary!.lowestScore,
        readingCount: newCount,
        alertCount: _todaySummary!.alertCount,
        dominantRiskLevel: newAverage > 70
            ? RiskLevel.critical
            : newAverage > 50
                ? RiskLevel.high
                : newAverage > 30
                    ? RiskLevel.moderate
                    : RiskLevel.low,
        keyFactors: _todaySummary!.keyFactors,
      );
    }

    // Save summary
    _storageService.saveDailySummary(_todaySummary!);
  }

  // ============== Alert Management ==============

  /// Handle new alert from stream
  void _onNewAlert(Alert alert) {
    _refreshAlerts();
    notifyListeners();
  }

  /// Refresh alerts from service
  void _refreshAlerts() {
    _alerts = _alertService.alerts;
    _unreadAlertCount = _alertService.unreadCount;
  }

  /// Mark an alert as read
  void markAlertAsRead(String alertId) {
    _alertService.markAsRead(alertId);
    _storageService.updateAlert(
      _alerts.firstWhere((a) => a.id == alertId).markAsRead(),
    );
    _refreshAlerts();
    notifyListeners();
  }

  /// Mark all alerts as read
  void markAllAlertsAsRead() {
    _alertService.markAllAsRead();
    _refreshAlerts();
    notifyListeners();
  }

  /// Remove an alert
  void removeAlert(String alertId) {
    _alertService.removeAlert(alertId);
    _storageService.deleteAlert(alertId);
    _refreshAlerts();
    notifyListeners();
  }

  /// Clear all alerts
  void clearAllAlerts() {
    _alertService.clearAlerts();
    _storageService.clearAllAlerts();
    _refreshAlerts();
    notifyListeners();
  }

  /// Get alerts by type
  List<Alert> getAlertsByType(AlertType type) {
    return _alertService.getAlertsByType(type);
  }

  /// Get alerts by severity
  List<Alert> getAlertsBySeverity(AlertSeverity severity) {
    return _alertService.getAlertsBySeverity(severity);
  }

  /// Get recent alerts
  List<Alert> getRecentAlerts(int hours) {
    return _alertService.getRecentAlerts(hours);
  }

  // ============== Historical Data ==============

  /// Load initial data from storage
  Future<void> _loadInitialData() async {
    // Load today's summary
    final today = DateTime.now();
    _todaySummary = _storageService.getDailySummary(today);

    // Load week summaries
    final weekAgo = today.subtract(const Duration(days: 7));
    _weekSummaries.clear();
    _weekSummaries.addAll(_storageService.getSummariesForRange(weekAgo, today));

    // Load recent risk scores
    final recentScores = _storageService.getAllRiskScores();
    _riskHistory.clear();
    _riskHistory.addAll(recentScores.take(_maxHistorySize));

    // Load alerts
    _alerts = _storageService.getAllAlerts();
    _unreadAlertCount = _alerts.where((a) => !a.isRead).length;

    // Set current risk from most recent
    if (_riskHistory.isNotEmpty) {
      _currentRiskScore = _riskHistory.first;
      _currentRiskLevel = _currentRiskScore!.riskLevel;
    }

    notifyListeners();
  }

  /// Refresh data from storage
  Future<void> refresh() async {
    await _loadInitialData();
  }

  /// Get risk trend data for charts
  List<Map<String, dynamic>> getRiskTrendData({int days = 7}) {
    final now = DateTime.now();
    final data = <Map<String, dynamic>>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final summary = _storageService.getDailySummary(date);

      data.add({
        'date': date,
        'average': summary?.averageScore ?? 0.0,
        'max': summary?.highestScore ?? 0,
        'min': summary?.lowestScore ?? 0,
        'count': summary?.readingCount ?? 0,
      });
    }

    return data;
  }

  /// Get component breakdown for current risk
  Map<String, int> getComponentBreakdown() {
    return {
      'Temperature': temperatureRisk,
      'Pressure': pressureRisk,
      'Circulation': circulationRisk,
      'Gait': gaitRisk,
    };
  }

  /// Get average risk for a specific period
  double getAverageRisk({int hours = 24}) {
    if (_riskHistory.isEmpty) return 0;

    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final relevantScores = _riskHistory
        .where((s) => s.timestamp.isAfter(cutoff))
        .toList();

    if (relevantScores.isEmpty) return 0;

    final sum = relevantScores.fold(0, (sum, s) => sum + s.overallScore);
    return sum / relevantScores.length;
  }

  /// Get max risk in period
  int getMaxRisk({int hours = 24}) {
    if (_riskHistory.isEmpty) return 0;

    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final relevantScores = _riskHistory
        .where((s) => s.timestamp.isAfter(cutoff))
        .toList();

    if (relevantScores.isEmpty) return 0;

    return relevantScores
        .map((s) => s.overallScore)
        .reduce((a, b) => a > b ? a : b);
  }

  // ============== Cleanup ==============

  /// Clear risk history
  void clearHistory() {
    _riskHistory.clear();
    _riskCalculator.clearHistory();
    notifyListeners();
  }

  // ============== Firestore Operations ==============

  /// Save alert to Firestore (user-specific)
  Future<void> _saveAlertToFirestore(Alert alert) async {
    if (_currentUserId == null) return;
    try {
      await _firestoreService.saveAlert(
        userId: _currentUserId!,
        alert: alert,
      );
      debugPrint('💾 Alert saved to Firestore: ${alert.title}');
    } catch (e) {
      debugPrint('❌ Firestore alert save error: $e');
    }
  }

  /// Save ML prediction to Firestore (user-specific)
  Future<void> _savePredictionToFirestore(RiskScore riskScore, SensorReading reading) async {
    if (_currentUserId == null) return;
    try {
      await _firestoreService.savePrediction(
        userId: _currentUserId!,
        predictionData: {
          'timestamp': riskScore.timestamp.toIso8601String(),
          'overallScore': riskScore.overallScore,
          'riskLevel': riskScore.riskLevel.name,
          'temperatureRisk': riskScore.temperatureRisk,
          'pressureRisk': riskScore.pressureRisk,
          'circulationRisk': riskScore.circulationRisk,
          'gaitRisk': riskScore.gaitRisk,
          'factors': riskScore.factors,
          'recommendations': riskScore.recommendations,
          'edgeMlBased': reading.riskProbability > 0 || reading.riskLevel > 0,
          'edgeMlRiskProbability': reading.riskProbability,
          'edgeMlRiskLevel': reading.riskLevel,
          'sensorSnapshot': {
            'temperatures': reading.temperatures,
            'pressures': reading.pressures,
            'spO2': reading.spO2,
            'heartRate': reading.heartRate,
            'stepCount': reading.stepCount,
          },
        },
      );
      debugPrint('💾 Prediction saved to Firestore');
    } catch (e) {
      debugPrint('❌ Firestore prediction save error: $e');
    }
  }

  /// Load alerts from Firestore when user logs in
  Future<void> _loadAlertsFromFirestore() async {
    if (_currentUserId == null) return;
    try {
      final firestoreAlerts = await _firestoreService.getAlerts(
        userId: _currentUserId!,
        limit: 50,
      );

      if (firestoreAlerts.isNotEmpty) {
        // Merge Firestore alerts into AlertService (avoid duplicates by ID)
        final existingIds = _alertService.alerts.map((a) => a.id).toSet();
        for (final alert in firestoreAlerts) {
          if (!existingIds.contains(alert.id)) {
            _alertService.addAlert(alert);
          }
        }
        _refreshAlerts();
        notifyListeners();
        debugPrint('📥 Loaded ${firestoreAlerts.length} alerts from Firestore');
      }
    } catch (e) {
      debugPrint('❌ Firestore alerts load error: $e');
    }
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _alertService.dispose();
    _riskCalculator.dispose();
    super.dispose();
  }
}
