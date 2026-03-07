import 'package:equatable/equatable.dart';

/// Represents a single snapshot of all sensor data from the smart sock
/// This is the primary data structure received from ESP32 via BLE
class SensorReading extends Equatable {
  /// Timestamp when the reading was taken
  final DateTime timestamp;

  /// Temperature readings from 4 zones (in °C)
  /// Index: 0=Heel, 1=Ball, 2=Arch, 3=Toe
  final List<double> temperatures;

  /// Pressure readings from 4 zones (in kPa)
  /// Index: 0=Heel, 1=Ball, 2=Arch, 3=Toe
  final List<double> pressures;

  /// Blood oxygen saturation level (SpO2) in percentage (0-100)
  final double spO2;

  /// Heart rate in beats per minute (BPM)
  final int heartRate;

  /// Accelerometer readings {x, y, z} in m/s²
  final AccelerometerData accelerometer;

  /// Gyroscope readings {x, y, z} in degrees/second
  final GyroscopeData gyroscope;

  /// Cumulative step count
  final int stepCount;

  /// Device battery level (0-100%)
  final int batteryLevel;

  /// Current activity type detected from IMU
  final ActivityType activityType;

  /// Risk probability from ESP32 edge ML (0-100%)
  final double riskProbability;

  /// Risk level from ESP32 edge ML (0=low, 1=moderate, 2=high, 3=critical)
  final int riskLevel;

  const SensorReading({
    required this.timestamp,
    required this.temperatures,
    required this.pressures,
    required this.spO2,
    required this.heartRate,
    AccelerometerData? accelerometer,
    GyroscopeData? gyroscope,
    this.stepCount = 0,
    this.batteryLevel = 100,
    this.activityType = ActivityType.unknown,
    this.riskProbability = 0.0,
    this.riskLevel = 0,
  })  : accelerometer = accelerometer ?? const AccelerometerData(x: 0, y: 0, z: 9.8),
        gyroscope = gyroscope ?? const GyroscopeData(x: 0, y: 0, z: 0);

  /// Create a SensorReading from JSON (BLE packet or Firestore)
  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      timestamp: json['timestamp'] is DateTime
          ? json['timestamp']
          : DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] ?? json['ts'] ?? 0) is int
                  ? (json['timestamp'] ?? json['ts'] ?? 0)
                  : ((json['timestamp'] ?? json['ts'] ?? 0) * 1000).toInt(),
            ),
      temperatures: _parseDoubleList(json['temperatures'] ?? json['temp'], 4),
      pressures: _parseDoubleList(json['pressures'] ?? json['pres'], 4),
      spO2: (json['spO2'] ?? json['spo2'] ?? 98.0).toDouble(),
      heartRate: (json['heartRate'] ?? json['hr'] ?? 72).toInt(),
      accelerometer: AccelerometerData.fromJson(
        json['accelerometer'] ?? json['acc'] ?? {'x': 0, 'y': 0, 'z': 9.8},
      ),
      gyroscope: GyroscopeData.fromJson(
        json['gyroscope'] ?? json['gyr'] ?? {'x': 0, 'y': 0, 'z': 0},
      ),
      stepCount: (json['stepCount'] ?? json['steps'] ?? 0).toInt(),
      batteryLevel: (json['batteryLevel'] ?? json['batt'] ?? 100).toInt(),
      activityType: ActivityType.fromString(
        json['activityType'] ?? json['activity'] ?? 'unknown',
      ),
      riskProbability: (json['riskProbability'] ?? json['riskProb'] ?? 0.0).toDouble(),
      riskLevel: (json['riskLevel'] ?? json['riskLvl'] ?? 0).toInt(),
    );
  }

  /// Convert to JSON for storage/transmission
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'temperatures': temperatures,
      'pressures': pressures,
      'spO2': spO2,
      'heartRate': heartRate,
      'accelerometer': accelerometer.toJson(),
      'gyroscope': gyroscope.toJson(),
      'stepCount': stepCount,
      'batteryLevel': batteryLevel,
      'activityType': activityType.name,
      'riskProbability': riskProbability,
      'riskLevel': riskLevel,
    };
  }

  /// Convert to compact JSON for BLE transmission
  Map<String, dynamic> toCompactJson() {
    return {
      'ts': timestamp.millisecondsSinceEpoch ~/ 1000,
      'temp': temperatures,
      'pres': pressures,
      'spo2': spO2,
      'hr': heartRate,
      'acc': accelerometer.toList(),
      'gyr': gyroscope.toList(),
      'steps': stepCount,
      'batt': batteryLevel,
      'riskProb': riskProbability,
      'riskLvl': riskLevel,
    };
  }

  /// Create a copy with modified fields
  SensorReading copyWith({
    DateTime? timestamp,
    List<double>? temperatures,
    List<double>? pressures,
    double? spO2,
    int? heartRate,
    AccelerometerData? accelerometer,
    GyroscopeData? gyroscope,
    int? stepCount,
    int? batteryLevel,
    ActivityType? activityType,
    double? riskProbability,
    int? riskLevel,
  }) {
    return SensorReading(
      timestamp: timestamp ?? this.timestamp,
      temperatures: temperatures ?? this.temperatures,
      pressures: pressures ?? this.pressures,
      spO2: spO2 ?? this.spO2,
      heartRate: heartRate ?? this.heartRate,
      accelerometer: accelerometer ?? this.accelerometer,
      gyroscope: gyroscope ?? this.gyroscope,
      stepCount: stepCount ?? this.stepCount,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      activityType: activityType ?? this.activityType,
      riskProbability: riskProbability ?? this.riskProbability,
      riskLevel: riskLevel ?? this.riskLevel,
    );
  }

  // ============== Helper Getters ==============

  /// Get temperature for a specific zone (0-3)
  double getTemperature(int zone) {
    if (zone >= 0 && zone < temperatures.length) {
      return temperatures[zone];
    }
    return 0.0;
  }

  /// Get pressure for a specific zone (0-3)
  double getPressure(int zone) {
    if (zone >= 0 && zone < pressures.length) {
      return pressures[zone];
    }
    return 0.0;
  }

  /// Average temperature across all zones
  double get averageTemperature {
    if (temperatures.isEmpty) return 0.0;
    return temperatures.reduce((a, b) => a + b) / temperatures.length;
  }

  /// Average pressure across all zones
  double get averagePressure {
    if (pressures.isEmpty) return 0.0;
    return pressures.reduce((a, b) => a + b) / pressures.length;
  }

  /// Maximum temperature among all zones
  double get maxTemperature {
    if (temperatures.isEmpty) return 0.0;
    return temperatures.reduce((a, b) => a > b ? a : b);
  }

  /// Maximum pressure among all zones
  double get maxPressure {
    if (pressures.isEmpty) return 0.0;
    return pressures.reduce((a, b) => a > b ? a : b);
  }

  /// Temperature difference between max and min zones
  double get temperatureVariance {
    if (temperatures.isEmpty) return 0.0;
    final max = temperatures.reduce((a, b) => a > b ? a : b);
    final min = temperatures.reduce((a, b) => a < b ? a : b);
    return max - min;
  }

  /// Pressure difference between max and min zones
  double get pressureVariance {
    if (pressures.isEmpty) return 0.0;
    final max = pressures.reduce((a, b) => a > b ? a : b);
    final min = pressures.reduce((a, b) => a < b ? a : b);
    return max - min;
  }

  /// Check if battery is low
  bool get isBatteryLow => batteryLevel < 20;

  /// Check if battery is critical
  bool get isBatteryCritical => batteryLevel < 10;

  // ============== Static Helpers ==============

  /// Parse a list of doubles from JSON with fallback
  static List<double> _parseDoubleList(dynamic value, int expectedLength) {
    if (value == null) {
      return List.filled(expectedLength, 0.0);
    }
    if (value is List) {
      return value.map((e) => (e as num).toDouble()).toList();
    }
    return List.filled(expectedLength, 0.0);
  }

  /// Create an empty/default reading
  /// Risk level name from ESP32 prediction
  String get riskLevelName {
    switch (riskLevel) {
      case 0: return 'Low';
      case 1: return 'Moderate';
      case 2: return 'High';
      case 3: return 'Critical';
      default: return 'Unknown';
    }
  }

  factory SensorReading.empty() {
    return SensorReading(
      timestamp: DateTime.now(),
      temperatures: [0.0, 0.0, 0.0, 0.0],
      pressures: [0.0, 0.0, 0.0, 0.0],
      spO2: 0.0,
      heartRate: 0,
    );
  }

  @override
  List<Object?> get props => [
        timestamp,
        temperatures,
        pressures,
        spO2,
        heartRate,
        accelerometer,
        gyroscope,
        stepCount,
        batteryLevel,
        activityType,
        riskProbability,
        riskLevel,
      ];

  @override
  String toString() {
    return 'SensorReading(timestamp: $timestamp, temps: $temperatures, '
        'pressures: $pressures, spO2: $spO2, hr: $heartRate, '
        'steps: $stepCount, battery: $batteryLevel%, '
        'riskProb: $riskProbability%, riskLevel: $riskLevel)';
  }
}

/// Accelerometer data from MPU6050
class AccelerometerData extends Equatable {
  final double x;
  final double y;
  final double z;

  const AccelerometerData({
    required this.x,
    required this.y,
    required this.z,
  });

  factory AccelerometerData.fromJson(dynamic json) {
    if (json is List) {
      return AccelerometerData(
        x: (json[0] as num).toDouble(),
        y: (json[1] as num).toDouble(),
        z: (json[2] as num).toDouble(),
      );
    }
    if (json is Map) {
      return AccelerometerData(
        x: (json['x'] ?? 0).toDouble(),
        y: (json['y'] ?? 0).toDouble(),
        z: (json['z'] ?? 0).toDouble(),
      );
    }
    return AccelerometerData.zero();
  }

  factory AccelerometerData.zero() {
    return const AccelerometerData(x: 0, y: 0, z: 9.8);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  List<double> toList() => [x, y, z];

  /// Magnitude of acceleration vector
  double get magnitude {
    return (x * x + y * y + z * z);
  }

  /// Magnitude of acceleration (square root)
  double get magnitudeSqrt {
    return magnitude;
  }

  // Helper to calculate sqrt
  double calcSqrt() {
    // Using dart:math would be: sqrt(magnitude)
    // Simple approximation for now
    double val = magnitude;
    double guess = val / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + val / guess) / 2;
    }
    return guess;
  }

  @override
  List<Object?> get props => [x, y, z];

  @override
  String toString() => 'Acc(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, z: ${z.toStringAsFixed(2)})';
}

/// Gyroscope data from MPU6050
class GyroscopeData extends Equatable {
  final double x;
  final double y;
  final double z;

  const GyroscopeData({
    required this.x,
    required this.y,
    required this.z,
  });

  factory GyroscopeData.fromJson(dynamic json) {
    if (json is List) {
      return GyroscopeData(
        x: (json[0] as num).toDouble(),
        y: (json[1] as num).toDouble(),
        z: (json[2] as num).toDouble(),
      );
    }
    if (json is Map) {
      return GyroscopeData(
        x: (json['x'] ?? 0).toDouble(),
        y: (json['y'] ?? 0).toDouble(),
        z: (json['z'] ?? 0).toDouble(),
      );
    }
    return GyroscopeData.zero();
  }

  factory GyroscopeData.zero() {
    return const GyroscopeData(x: 0, y: 0, z: 0);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  List<double> toList() => [x, y, z];

  /// Total angular velocity
  double get magnitude => x * x + y * y + z * z;

  @override
  List<Object?> get props => [x, y, z];

  @override
  String toString() => 'Gyro(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, z: ${z.toStringAsFixed(2)})';
}

/// Activity type detected from IMU data
enum ActivityType {
  resting,
  sitting,
  standing,
  walking,
  running,
  unknown;

  /// Create from string value
  static ActivityType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'resting':
        return ActivityType.resting;
      case 'sitting':
        return ActivityType.sitting;
      case 'standing':
        return ActivityType.standing;
      case 'walking':
        return ActivityType.walking;
      case 'running':
        return ActivityType.running;
      default:
        return ActivityType.unknown;
    }
  }

  /// Display name for UI
  String get displayName {
    switch (this) {
      case ActivityType.resting:
        return 'Resting';
      case ActivityType.sitting:
        return 'Sitting';
      case ActivityType.standing:
        return 'Standing';
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.running:
        return 'Running';
      case ActivityType.unknown:
        return 'Unknown';
    }
  }

  /// Icon name for UI (Material Icons)
  String get iconName {
    switch (this) {
      case ActivityType.resting:
        return 'bed';
      case ActivityType.sitting:
        return 'chair';
      case ActivityType.standing:
        return 'person';
      case ActivityType.walking:
        return 'directions_walk';
      case ActivityType.running:
        return 'directions_run';
      case ActivityType.unknown:
        return 'help_outline';
    }
  }
}
