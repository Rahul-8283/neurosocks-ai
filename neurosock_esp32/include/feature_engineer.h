#ifndef FEATURE_ENGINEER_H
#define FEATURE_ENGINEER_H

#include <Arduino.h>
#include "config.h"
#include "sensors.h"

/* ============================================================
   FEATURE VECTOR STRUCTURE (15 features)
   ============================================================ */

struct FeatureVector {
    // Raw features (11)
    float temp_heel;
    float temp_ball;
    float temp_arch;
    float temp_toe;
    
    float press_heel;
    float press_ball;
    float press_arch;
    float press_toe;
    
    float spo2;
    float heart_rate;
    float step_count;
    
    // Engineered features (4)
    float max_pressure;
    float pressure_variance;
    float max_temp;
    float temp_variance;
    
    /**
     * Convert struct to flat array for ML inference
     * Returns: pointer to float array[15]
     */
    float* to_array() {
        static float arr[15];
        arr[0] = temp_heel;
        arr[1] = temp_ball;
        arr[2] = temp_arch;
        arr[3] = temp_toe;
        arr[4] = press_heel;
        arr[5] = press_ball;
        arr[6] = press_arch;
        arr[7] = press_toe;
        arr[8] = spo2;
        arr[9] = heart_rate;
        arr[10] = step_count;
        arr[11] = max_pressure;
        arr[12] = pressure_variance;
        arr[13] = max_temp;
        arr[14] = temp_variance;
        return arr;
    }
};

/* ============================================================
   FEATURE ENGINEERING FUNCTIONS
   ============================================================ */

/**
 * Calculate engineered features from raw sensor data
 * Input: Raw sensor readings (11 values)
 * Output: 4 engineered features
 * 
 * Engineered features:
 *   - max_pressure: max(pressures[4])
 *   - pressure_variance: var(pressures[4])
 *   - max_temp: max(temps[4])
 *   - temp_variance: var(temps[4])
 */
void feature_engineer_calculate(const SensorData& raw_data, FeatureVector& features);

/**
 * Normalize features using StandardScaler parameters
 * Formula: (x - mean) / std
 * 
 * Parameters from ML training stored in config.h:
 * FEATURE_MEANS[15] and FEATURE_STDS[15]
 */
void feature_engineer_normalize(FeatureVector& features);

/**
 * Calculate statistics from array (helper for engineering)
 * Returns: maximum value
 */
float feature_calc_max(float* arr, uint8_t size);

/**
 * Calculate statistics from array (helper for engineering)
 * Returns: variance (sum of squared deviations / size)
 */
float feature_calc_variance(float* arr, uint8_t size);

/**
 * Calculate statistics from array (helper for engineering)
 * Returns: mean/average value
 */
float feature_calc_mean(float* arr, uint8_t size);

/**
 * Clamp value between min and max
 */
float feature_clamp(float value, float min_val, float max_val);

/**
 * Validate feature vector for anomalies
 * Returns: true if all features are in valid range, false if anomaly detected
 */
bool feature_validate(const FeatureVector& features);

/**
 * Debug print feature vector to Serial
 */
void feature_debug_print(const FeatureVector& features);

#endif  // FEATURE_ENGINEER_H

