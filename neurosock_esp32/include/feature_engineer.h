#ifndef FEATURE_ENGINEER_H
#define FEATURE_ENGINEER_H

#include <Arduino.h>

// Feature Engineering module
// Transforms 11 raw sensor values into 15-feature vector
// - Raw features: temperatures, pressures, spo2, heart_rate, step_count
// - Engineered features: max_pressure, pressure_variance, max_temp, temp_variance
// - Normalization: applies StandardScaler (mean/std) from training

#endif  // FEATURE_ENGINEER_H
