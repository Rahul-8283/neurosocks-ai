// Calculates weighted risk scores using ESP32 edge ML predictions (primary) with fallback to threshold-based logic
// Tracks history for trend analysis.

import 'package:flutter/foundation.dart';
import '../models/sensor_reading.dart';
import '../models/risk_score.dart';
import '../../core/constants/sensor_constants.dart';

/// Calculates risk scores from sensor readings
/// Primary: ESP32 edge ML predictions from packet | Fallback: Weighted algorithm (temp 30%, pressure 35%, circulation 20%, gait 15%)
class RiskCalculator {
  // Singleton pattern
  static final RiskCalculator _instance = RiskCalculator._internal();
  factory RiskCalculator() => _instance;
  RiskCalculator._internal();

  // History for trend analysis
  final List<SensorReading> _readingHistory = [];
  static const int _historySize = 30; // Keep last 30 readings for trend analysis

  // ============== Main Calculation ==============

  /// Calculate risk score from a sensor reading
  /// Primary: ESP32 edge ML prediction | Fallback: Threshold-based weighted algorithm
  RiskScore calculate(SensorReading reading) {
    // Add to history for trend analysis
    _addToHistory(reading);

    // Use ESP32's edge ML prediction if available (riskProbability > 0 indicates valid prediction)
    if (reading.riskProbability > 0 || reading.riskLevel > 0) {
      // ESP32 sends 0-100%, pass directly as 0-100 component score
      // fromComponents applies the weights (0.30, 0.35, 0.20, 0.15) to produce overall 0-100
      final score = reading.riskProbability.round().clamp(0, 100);
      final factors = _getEdgeMLRiskFactors(reading);

      if (kDebugMode) {
        debugPrint('🎯 ESP32 Edge ML: ${reading.riskProbability}% (level ${reading.riskLevel})');
      }

      return RiskScore.fromComponents(
        temperatureRisk: score,
        pressureRisk: score,
        circulationRisk: score,
        gaitRisk: score,
        factors: factors,
        timestamp: reading.timestamp,
      );
    }

    // Fallback: Calculate threshold-based risk
    if (kDebugMode) {
      debugPrint('⚠️ No ESP32 ML data — using threshold-based risk calculation');
    }

    final tempRisk = _calculateTemperatureRisk(reading);
    final pressureRisk = _calculatePressureRisk(reading);
    final circRisk = _calculateCirculationRisk(reading);
    final gaitRisk = _calculateGaitRisk(reading);

    final factors = _identifyFactors(
      reading: reading,
      tempRisk: tempRisk,
      pressureRisk: pressureRisk,
      circRisk: circRisk,
      gaitRisk: gaitRisk,
    );

    return RiskScore.fromComponents(
      temperatureRisk: tempRisk,
      pressureRisk: pressureRisk,
      circulationRisk: circRisk,
      gaitRisk: gaitRisk,
      factors: factors,
      timestamp: reading.timestamp,
    );
  }

  /// Get risk factors based on ESP32 edge ML risk level
  List<String> _getEdgeMLRiskFactors(SensorReading reading) {
    final factors = <String>[];
    
    switch (reading.riskLevel) {
      case 0:
        factors.addAll(['Normal readings', 'Low risk detected by Edge ML']);
        break;
      case 1:
        factors.addAll(['Moderate risk (Edge ML)', 'Monitor closely', 'Sensor patterns indicate attention needed']);
        break;
      case 2:
        factors.addAll(['High risk alert (Edge ML)', 'Immediate attention recommended']);
        break;
      case 3:
        factors.addAll(['Critical risk (Edge ML)', 'Immediate attention required', 'Critical sensor anomaly detected']);
        break;
    }
    
    // Add specific sensor factors for context
    if (reading.maxTemperature > SensorConstants.tempWarningHigh) {
      factors.add('Elevated temperature at ${reading.maxTemperature.toStringAsFixed(1)}°C');
    }
    if (reading.maxPressure > SensorConstants.pressureWarning) {
      factors.add('High pressure at ${reading.maxPressure.toStringAsFixed(0)} kPa');
    }
    if (reading.spO2 > 0 && reading.spO2 < SensorConstants.spo2Warning) {
      factors.add('Low blood oxygen (${reading.spO2.toStringAsFixed(1)}%)');
    }
    
    return factors.take(5).toList();
  }

  // ============== Temperature Risk ==============

  /// Calculate temperature-based risk (0-100)
  int _calculateTemperatureRisk(SensorReading reading) {
    double risk = 0;
    final temps = reading.temperatures;

    if (temps.isEmpty) return 0;

    // Check each zone for elevated temperature
    for (int i = 0; i < temps.length; i++) {
      final temp = temps[i];

      if (temp > SensorConstants.tempCriticalHigh) {
        // Critical: very high temperature
        risk += 30;
      } else if (temp > SensorConstants.tempWarningHigh) {
        // Warning: elevated temperature
        risk += 20;
      } else if (temp < SensorConstants.tempCriticalLow) {
        // Critical: very cold (circulation issue)
        risk += 25;
      } else if (temp < SensorConstants.tempWarningLow) {
        // Warning: cold
        risk += 15;
      }
    }

    // Check for temperature asymmetry (difference between zones)
    final maxTemp = temps.reduce((a, b) => a > b ? a : b);
    final minTemp = temps.reduce((a, b) => a < b ? a : b);
    final asymmetry = maxTemp - minTemp;

    if (asymmetry > SensorConstants.tempAsymmetryCritical) {
      risk += 25;
    } else if (asymmetry > SensorConstants.tempAsymmetryWarning) {
      risk += 15;
    }

    // Check for rapid temperature change (trend)
    final rateOfChange = _calculateTempRateOfChange();
    if (rateOfChange > SensorConstants.tempRateOfChangeWarning) {
      risk += 15;
    }

    return risk.round().clamp(0, 100);
  }

  /// Calculate rate of temperature change from history
  double _calculateTempRateOfChange() {
    if (_readingHistory.length < 5) return 0;

    final recent = _readingHistory.sublist(_readingHistory.length - 5);
    final firstAvg = recent.first.averageTemperature;
    final lastAvg = recent.last.averageTemperature;

    // Calculate time difference in hours
    final timeDiff = recent.last.timestamp
        .difference(recent.first.timestamp)
        .inMinutes / 60;

    if (timeDiff == 0) return 0;

    return (lastAvg - firstAvg).abs() / timeDiff;
  }

  // ============== Pressure Risk ==============

  /// Calculate pressure-based risk (0-100)
  int _calculatePressureRisk(SensorReading reading) {
    double risk = 0;
    final pressures = reading.pressures;

    if (pressures.isEmpty) return 0;

    // Check each zone for high pressure
    for (int i = 0; i < pressures.length; i++) {
      final pressure = pressures[i];

      if (pressure > SensorConstants.pressureCritical) {
        // Critical: dangerous pressure
        risk += 35;
      } else if (pressure > SensorConstants.pressureHigh) {
        // High pressure
        risk += 25;
      } else if (pressure > SensorConstants.pressureWarning) {
        // Warning: elevated pressure
        risk += 15;
      }
    }

    // Check for pressure concentration (poor distribution)
    final distributionScore = _calculatePressureDistribution(pressures);
    if (distributionScore < 0.5) {
      risk += 20; // Poor distribution
    } else if (distributionScore < 0.7) {
      risk += 10;
    }

    // Check for sustained high pressure
    final sustainedPressure = _checkSustainedHighPressure();
    if (sustainedPressure) {
      risk += 20;
    }

    // Check for pressure spikes
    final hasSpike = _checkPressureSpike(pressures);
    if (hasSpike) {
      risk += 15;
    }

    return risk.round().clamp(0, 100);
  }

  /// Calculate pressure distribution score (0-1, 1 = even)
  double _calculatePressureDistribution(List<double> pressures) {
    if (pressures.every((p) => p == 0)) return 1.0;

    final avg = pressures.reduce((a, b) => a + b) / pressures.length;
    if (avg == 0) return 1.0;

    double variance = 0;
    for (final p in pressures) {
      variance += (p - avg) * (p - avg);
    }
    variance = variance / pressures.length;

    final normalizedVariance = variance / (avg * avg);
    return (1 - normalizedVariance).clamp(0.0, 1.0);
  }

  /// Check if there's been sustained high pressure
  bool _checkSustainedHighPressure() {
    if (_readingHistory.length < 5) return false;

    final recent = _readingHistory.sublist(_readingHistory.length - 5);
    int highPressureCount = 0;

    for (final reading in recent) {
      if (reading.maxPressure > SensorConstants.pressureWarning) {
        highPressureCount++;
      }
    }

    return highPressureCount >= 4; // 4 out of 5 readings have high pressure
  }

  /// Check for sudden pressure spike
  bool _checkPressureSpike(List<double> currentPressures) {
    if (_readingHistory.length < 2) return false;

    final previous = _readingHistory[_readingHistory.length - 2];

    for (int i = 0; i < currentPressures.length && i < previous.pressures.length; i++) {
      final diff = currentPressures[i] - previous.pressures[i];
      if (diff > SensorConstants.pressureSpikeThreshold) {
        return true;
      }
    }

    return false;
  }

  // ============== Circulation Risk ==============

  /// Calculate circulation-based risk from SpO2 and heart rate (0-100)
  int _calculateCirculationRisk(SensorReading reading) {
    double risk = 0;

    // SpO2 assessment
    final spO2 = reading.spO2;
    if (spO2 < SensorConstants.spo2Critical) {
      risk += 50; // Critical hypoxemia
    } else if (spO2 < SensorConstants.spo2Low) {
      risk += 35; // Moderate hypoxemia
    } else if (spO2 < SensorConstants.spo2Warning) {
      risk += 20; // Mild hypoxemia
    } else if (spO2 < SensorConstants.spo2Normal) {
      risk += 10; // Slightly below normal
    }

    // Heart rate assessment
    final hr = reading.heartRate;
    if (hr < SensorConstants.hrCriticalLow || hr > SensorConstants.hrCriticalHigh) {
      risk += 30; // Critical heart rate
    } else if (hr < SensorConstants.hrWarningLow || hr > SensorConstants.hrWarningHigh) {
      risk += 15; // Abnormal heart rate
    } else if (hr < SensorConstants.hrNormalMin || hr > SensorConstants.hrNormalMax) {
      risk += 5; // Slightly off normal
    }

    // Check for SpO2 drop trend
    final spO2Drop = _checkSpO2Drop();
    if (spO2Drop) {
      risk += 15;
    }

    return risk.round().clamp(0, 100);
  }

  /// Check if SpO2 has been dropping
  bool _checkSpO2Drop() {
    if (_readingHistory.length < 5) return false;

    final recent = _readingHistory.sublist(_readingHistory.length - 5);
    int dropCount = 0;

    for (int i = 1; i < recent.length; i++) {
      if (recent[i].spO2 < recent[i - 1].spO2) {
        dropCount++;
      }
    }

    return dropCount >= 3; // Dropping in 3+ consecutive readings
  }

  // ============== Gait Risk ==============

  /// Calculate gait-based risk from IMU data (0-100)
  int _calculateGaitRisk(SensorReading reading) {
    double risk = 0;

    // Skip gait analysis if resting/sitting
    if (reading.activityType == ActivityType.resting ||
        reading.activityType == ActivityType.sitting) {
      return 0;
    }

    // Calculate stability from accelerometer variance
    final stability = _calculateStability(reading);

    if (stability < SensorConstants.gaitStabilityCritical) {
      risk += 40; // Very unstable
    } else if (stability < SensorConstants.gaitStabilityWarning) {
      risk += 25; // Unstable
    }

    // Check for sudden gait changes
    final gaitChange = _checkGaitChange();
    if (gaitChange) {
      risk += 20;
    }

    // Check step frequency if walking
    if (reading.activityType == ActivityType.walking) {
      final stepFreq = _calculateStepFrequency();
      if (stepFreq > 0) {
        if (stepFreq < SensorConstants.stepFrequencyMin - 20 ||
            stepFreq > SensorConstants.stepFrequencyMax + 20) {
          risk += 15; // Abnormal step frequency
        }
      }
    }

    return risk.round().clamp(0, 100);
  }

  /// Calculate stability score from accelerometer (0-1, 1 = stable)
  double _calculateStability(SensorReading reading) {
    final acc = reading.accelerometer;

    // Calculate deviation from expected gravity vector
    final expectedZ = 9.8;
    final deviationX = acc.x.abs();
    final deviationY = acc.y.abs();
    final deviationZ = (acc.z - expectedZ).abs();

    // Total deviation
    final totalDeviation = deviationX + deviationY + deviationZ;

    // Normalize to 0-1 (higher deviation = lower stability)
    // Max expected deviation during walking ~5, running ~10
    final maxDeviation = reading.activityType == ActivityType.running ? 15.0 : 8.0;

    return (1 - (totalDeviation / maxDeviation)).clamp(0.0, 1.0);
  }

  /// Check for sudden changes in gait pattern
  bool _checkGaitChange() {
    if (_readingHistory.length < 3) return false;

    final recent = _readingHistory.sublist(_readingHistory.length - 3);

    // Check if activity changed suddenly
    if (recent[0].activityType != recent[2].activityType) {
      // Check if the middle reading was different from both
      if (recent[1].activityType != recent[0].activityType &&
          recent[1].activityType != recent[2].activityType) {
        return true;
      }
    }

    return false;
  }

  /// Calculate approximate step frequency (steps per minute)
  double _calculateStepFrequency() {
    if (_readingHistory.length < 10) return 0;

    final recent = _readingHistory.sublist(_readingHistory.length - 10);
    final firstSteps = recent.first.stepCount;
    final lastSteps = recent.last.stepCount;
    final stepsDiff = lastSteps - firstSteps;

    final timeDiff = recent.last.timestamp
        .difference(recent.first.timestamp)
        .inSeconds / 60; // in minutes

    if (timeDiff == 0) return 0;

    return stepsDiff / timeDiff;
  }

  // ============== Factor Identification ==============

  /// Identify factors contributing to the risk score
  List<String> _identifyFactors({
    required SensorReading reading,
    required int tempRisk,
    required int pressureRisk,
    required int circRisk,
    required int gaitRisk,
  }) {
    final factors = <String>[];

    // Temperature factors
    if (tempRisk > 0) {
      final maxTemp = reading.maxTemperature;
      final hotZoneIndex = reading.temperatures.indexOf(maxTemp);
      final zoneName = SensorConstants.getZoneName(hotZoneIndex);

      if (maxTemp > SensorConstants.tempCriticalHigh) {
        factors.add('Critical temperature at $zoneName (${maxTemp.toStringAsFixed(1)}°C)');
      } else if (maxTemp > SensorConstants.tempWarningHigh) {
        factors.add('Elevated temperature at $zoneName (${maxTemp.toStringAsFixed(1)}°C)');
      }

      if (reading.temperatureVariance > SensorConstants.tempAsymmetryWarning) {
        factors.add('Temperature asymmetry detected (${reading.temperatureVariance.toStringAsFixed(1)}°C difference)');
      }
    }

    // Pressure factors
    if (pressureRisk > 0) {
      final maxPressure = reading.maxPressure;
      final highZoneIndex = reading.pressures.indexOf(maxPressure);
      final zoneName = SensorConstants.getZoneName(highZoneIndex);

      if (maxPressure > SensorConstants.pressureCritical) {
        factors.add('Dangerous pressure at $zoneName (${maxPressure.toStringAsFixed(0)} kPa)');
      } else if (maxPressure > SensorConstants.pressureWarning) {
        factors.add('High pressure at $zoneName (${maxPressure.toStringAsFixed(0)} kPa)');
      }

      if (_checkSustainedHighPressure()) {
        factors.add('Sustained high pressure detected');
      }
    }

    // Circulation factors
    if (circRisk > 0) {
      if (reading.spO2 < SensorConstants.spo2Normal) {
        factors.add('Low blood oxygen (${reading.spO2.toStringAsFixed(1)}%)');
      }

      if (reading.heartRate < SensorConstants.hrNormalMin) {
        factors.add('Low heart rate (${reading.heartRate} BPM)');
      } else if (reading.heartRate > SensorConstants.hrNormalMax) {
        factors.add('Elevated heart rate (${reading.heartRate} BPM)');
      }
    }

    // Gait factors
    if (gaitRisk > 0) {
      final stability = _calculateStability(reading);
      if (stability < SensorConstants.gaitStabilityWarning) {
        factors.add('Gait instability detected');
      }
    }

    // Sort by importance (more severe first)
    factors.sort((a, b) {
      if (a.contains('Critical') || a.contains('Dangerous')) return -1;
      if (b.contains('Critical') || b.contains('Dangerous')) return 1;
      return 0;
    });

    return factors.take(5).toList(); // Return top 5 factors
  }

  // ============== History Management ==============

  /// Add reading to history
  void _addToHistory(SensorReading reading) {
    _readingHistory.add(reading);

    // Keep only recent readings
    if (_readingHistory.length > _historySize) {
      _readingHistory.removeAt(0);
    }
  }

  /// Clear reading history
  void clearHistory() {
    _readingHistory.clear();
  }

  /// Get reading history
  List<SensorReading> get history => List.unmodifiable(_readingHistory);

  /// Dispose resources
  void dispose() {
    if (kDebugMode) {
      debugPrint('✅ RiskCalculator disposed');
    }
  }
}
