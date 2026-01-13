// 	User profile, settings, theme, notifications, device pairing

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter/material.dart' as material show ThemeMode;
import '../data/models/user_profile.dart';
import '../data/services/storage_service.dart';

/// Provider for managing user profile and app settings
class UserProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  // User profile
  UserProfile? _userProfile;
  bool _isLoggedIn = false;
  bool _isLoading = false;

  // App settings
  material.ThemeMode _themeMode = material.ThemeMode.system;
  bool _notificationsEnabled = true;
  bool _onboardingComplete = false;
  bool _isPinSet = false; // Track if user has set a PIN

  // Device pairing
  String? _pairedDeviceId;
  String? _pairedDeviceName;

  // ============== Constructor ==============

  UserProvider() {
    _loadUserData();
  }

  // ============== Getters ==============

  UserProfile? get userProfile => _userProfile;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  material.ThemeMode get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get onboardingComplete => _onboardingComplete;
  bool get isPinSet => _isPinSet; // Check if PIN is set
  String? get pairedDeviceId => _pairedDeviceId;
  String? get pairedDeviceName => _pairedDeviceName;
  bool get hasDevicePaired => _pairedDeviceId != null;

  // User info shortcuts
  String get userName => _userProfile?.name ?? 'User';
  String get userEmail => _userProfile?.email ?? '';
  int? get userAge => _userProfile?.age;
  DiabetesType? get diabetesType => _userProfile?.diabetesType;
  HealthInfo? get healthInfo => _userProfile?.healthInfo;
  UserSettings? get userSettings => _userProfile?.settings;

  // ============== Initialization ==============

  /// Load user data from storage
  Future<void> _loadUserData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load user profile
      _userProfile = _storageService.getUserProfile();
      _isLoggedIn = _userProfile != null;

      // Load settings
      _onboardingComplete = _storageService.isOnboardingComplete();
      _notificationsEnabled = _storageService.areNotificationsEnabled();
      
      // Load theme
      final themeStr = _storageService.getSelectedTheme();
      _themeMode = _parseThemeMode(themeStr);

      // Load paired device
      _pairedDeviceId = _storageService.getPairedDeviceId();
      _pairedDeviceName = _storageService.getPairedDeviceName();

      // Load PIN status
      _isPinSet = _storageService.isPinSet();

    } catch (e) {
      debugPrint('Error loading user data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Parse theme string to ThemeMode
  material.ThemeMode _parseThemeMode(String theme) {
    switch (theme) {
      case 'light':
        return material.ThemeMode.light;
      case 'dark':
        return material.ThemeMode.dark;
      default:
        return material.ThemeMode.system;
    }
  }

  // ============== Profile Management ==============

  /// Create or update user profile
  Future<void> saveProfile(UserProfile profile) async {
    _userProfile = profile;
    _isLoggedIn = true;
    await _storageService.saveUserProfile(profile);
    notifyListeners();
  }

  /// Update specific profile fields
  Future<void> updateProfile({
    String? name,
    int? age,
    DiabetesType? diabetesType,
    HealthInfo? healthInfo,
    UserSettings? settings,
  }) async {
    if (_userProfile == null) return;

    _userProfile = _userProfile!.copyWith(
      name: name,
      age: age,
      diabetesType: diabetesType,
      healthInfo: healthInfo,
      settings: settings,
    );

    await _storageService.saveUserProfile(_userProfile!);
    notifyListeners();
  }

  /// Create new user profile (for signup/onboarding)
  Future<UserProfile> createProfile({
    required String email,
    required String name,
    int? age,
    DiabetesType? diabetesType,
  }) async {
    final profile = UserProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: email,
      name: name,
      age: age,
      diabetesType: diabetesType,
      createdAt: DateTime.now(),
      settings: const UserSettings(),
    );

    await saveProfile(profile);
    return profile;
  }

  /// Delete user profile (logout)
  Future<void> deleteProfile() async {
    await _storageService.deleteUserProfile();
    _userProfile = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // ============== Health Info ==============

  /// Update health information
  Future<void> updateHealthInfo(HealthInfo healthInfo) async {
    if (_userProfile == null) return;

    _userProfile = _userProfile!.copyWith(healthInfo: healthInfo);
    await _storageService.saveUserProfile(_userProfile!);
    notifyListeners();
  }

  /// Quick update for common health flags
  Future<void> setHealthFlag({
    bool? hasNeuropathy,
    bool? hasPAD,
    bool? hasPreviousUlcer,
  }) async {
    final current = _userProfile?.healthInfo ?? const HealthInfo();

    final updated = current.copyWith(
      hasNeuropathy: hasNeuropathy,
      hasPAD: hasPAD,
      hasPreviousUlcer: hasPreviousUlcer,
    );

    await updateHealthInfo(updated);
  }

  // ============== Settings ==============

  /// Update user settings
  Future<void> updateSettings(UserSettings settings) async {
    if (_userProfile == null) return;

    _userProfile = _userProfile!.copyWith(settings: settings);
    await _storageService.saveUserProfile(_userProfile!);
    notifyListeners();
  }

  /// Set theme mode
  Future<void> setThemeMode(material.ThemeMode mode) async {
    _themeMode = mode;
    
    String themeStr;
    switch (mode) {
      case material.ThemeMode.light:
        themeStr = 'light';
        break;
      case material.ThemeMode.dark:
        themeStr = 'dark';
        break;
      default:
        themeStr = 'system';
    }

    await _storageService.setSelectedTheme(themeStr);

    // Also update in profile if exists
    if (_userProfile != null) {
      final profileThemeMode = ThemeMode.fromString(themeStr);
      final updatedSettings = _userProfile!.settings.copyWith(
        themeMode: profileThemeMode,
      );
      await updateSettings(updatedSettings);
    }

    notifyListeners();
  }

  /// Toggle dark mode (convenience method)
  Future<void> toggleDarkMode() async {
    if (_themeMode == material.ThemeMode.dark) {
      await setThemeMode(material.ThemeMode.light);
    } else {
      await setThemeMode(material.ThemeMode.dark);
    }
  }

  /// Set notifications enabled
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    await _storageService.setNotificationsEnabled(enabled);

    // Also update in profile if exists
    if (_userProfile != null) {
      final updatedSettings = _userProfile!.settings.copyWith(
        notificationsEnabled: enabled,
      );
      await updateSettings(updatedSettings);
    }

    notifyListeners();
  }

  /// Set onboarding complete
  Future<void> setOnboardingComplete(bool complete) async {
    _onboardingComplete = complete;
    await _storageService.setOnboardingComplete(complete);
    notifyListeners();
  }

  // ============== Device Pairing ==============

  /// Set paired device
  Future<void> setPairedDevice(String id, String name) async {
    _pairedDeviceId = id;
    _pairedDeviceName = name;
    await _storageService.setPairedDevice(id, name);
    notifyListeners();
  }

  /// Clear paired device
  Future<void> clearPairedDevice() async {
    _pairedDeviceId = null;
    _pairedDeviceName = null;
    await _storageService.setPairedDevice(null, null);
    notifyListeners();
  }

  // ============== Unit Preferences ==============

  /// Get temperature unit preference
  TemperatureUnit get temperatureUnit =>
      _userProfile?.settings.temperatureUnit ?? TemperatureUnit.celsius;

  /// Set temperature unit
  Future<void> setTemperatureUnit(TemperatureUnit unit) async {
    if (_userProfile == null) return;

    final updatedSettings = _userProfile!.settings.copyWith(
      temperatureUnit: unit,
    );
    await updateSettings(updatedSettings);
  }

  // ============== Risk Factor Calculation ==============

  /// Get user's base risk multiplier based on health conditions
  double get baseRiskMultiplier {
    double multiplier = 1.0;
    final health = _userProfile?.healthInfo;

    if (health == null) return multiplier;

    // Higher risk for certain conditions
    if (health.hasNeuropathy) multiplier += 0.3;
    if (health.hasPAD) multiplier += 0.3;
    if (health.hasPreviousUlcer) multiplier += 0.4;

    // Diabetes type affects risk
    if (_userProfile?.diabetesType == DiabetesType.type1) {
      multiplier += 0.1;
    }

    // Years with diabetes (from UserProfile, not HealthInfo)
    final diabetesYears = _userProfile?.diabetesYears;
    if (diabetesYears != null) {
      if (diabetesYears > 10) multiplier += 0.2;
      if (diabetesYears > 20) multiplier += 0.1;
    }

    return multiplier.clamp(1.0, 2.5);
  }

  /// Check if user has high-risk profile
  bool get isHighRiskProfile {
    final health = _userProfile?.healthInfo;
    if (health == null) return false;

    return health.hasNeuropathy ||
        health.hasPAD ||
        health.hasPreviousUlcer;
  }

  // ============== Data Management ==============

  /// Export user data
  Map<String, dynamic> exportUserData() {
    return {
      'profile': _userProfile?.toJson(),
      'settings': {
        'theme': _themeMode.toString(),
        'notifications': _notificationsEnabled,
        'onboarding': _onboardingComplete,
      },
      'device': {
        'id': _pairedDeviceId,
        'name': _pairedDeviceName,
      },
      'exportDate': DateTime.now().toIso8601String(),
    };
  }

  /// Clear all user data
  Future<void> clearAllData() async {
    await _storageService.clearAllData();
    _userProfile = null;
    _isLoggedIn = false;
    _themeMode = material.ThemeMode.system;
    _notificationsEnabled = true;
    _onboardingComplete = false;
    _pairedDeviceId = null;
    _pairedDeviceName = null;
    notifyListeners();
  }

  /// Refresh data from storage
  Future<void> refresh() async {
    await _loadUserData();
  }
}
