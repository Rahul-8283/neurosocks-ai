#include "feature_engineer.h"
#include <cmath>

/* ============================================================
   HELPER FUNCTIONS FOR FEATURE CALCULATION
   ============================================================ */

float feature_calc_max(float* arr, uint8_t size) {
    float max_val = arr[0];
    for (uint8_t i = 1; i < size; i++) {
        if (arr[i] > max_val) {
            max_val = arr[i];
        }
    }
    return max_val;
}

float feature_calc_mean(float* arr, uint8_t size) {
    float sum = 0.0f;
    for (uint8_t i = 0; i < size; i++) {
        sum += arr[i];
    }
    return sum / (float)size;
}

float feature_calc_variance(float* arr, uint8_t size) {
    float mean = feature_calc_mean(arr, size);
    float sum_sq_diff = 0.0f;
    
    for (uint8_t i = 0; i < size; i++) {
        float diff = arr[i] - mean;
        sum_sq_diff += diff * diff;
    }
    
    return sum_sq_diff / (float)size;
}

float feature_clamp(float value, float min_val, float max_val) {
    if (value < min_val) return min_val;
    if (value > max_val) return max_val;
    return value;
}

/* ============================================================
   FEATURE ENGINEERING
   ============================================================ */

void feature_engineer_calculate(const SensorData& raw_data, FeatureVector& features) {
    // Copy raw features directly
    features.temp_heel = raw_data.temp_heel;
    features.temp_ball = raw_data.temp_ball;
    features.temp_arch = raw_data.temp_arch;
    features.temp_toe = raw_data.temp_toe;
    
    features.press_heel = raw_data.press_heel;
    features.press_ball = raw_data.press_ball;
    features.press_arch = raw_data.press_arch;
    features.press_toe = raw_data.press_toe;
    
    features.spo2 = raw_data.spo2;
    features.heart_rate = (float)raw_data.heart_rate;
    features.step_count = (float)raw_data.step_count;
    
    // Calculate engineered features
    // 1. max_pressure: maximum of 4 pressure values
    float pressures[4] = {
        raw_data.press_heel,
        raw_data.press_ball,
        raw_data.press_arch,
        raw_data.press_toe
    };
    features.max_pressure = feature_calc_max(pressures, 4);
    
    // 2. pressure_variance: variance of 4 pressure values
    features.pressure_variance = feature_calc_variance(pressures, 4);
    
    // 3. max_temp: maximum of 4 temperature values
    float temps[4] = {
        raw_data.temp_heel,
        raw_data.temp_ball,
        raw_data.temp_arch,
        raw_data.temp_toe
    };
    features.max_temp = feature_calc_max(temps, 4);
    
    // 4. temp_variance: variance of 4 temperature values
    features.temp_variance = feature_calc_variance(temps, 4);
    
    if (DEBUG_FEATURES) {
        Serial.printf("[FEATURES] MaxP:%.1f VarP:%.1f MaxT:%.1f VarT:%.1f\n",
                      features.max_pressure,
                      features.pressure_variance,
                      features.max_temp,
                      features.temp_variance);
    }
}

/* ============================================================
   FEATURE NORMALIZATION (StandardScaler)
   ============================================================ */

void feature_engineer_normalize(FeatureVector& features) {
    float* arr = features.to_array();
    
    for (int i = 0; i < ML_INPUT_FEATURES; i++) {
        // Normalization formula: (x - mean) / std
        float normalized = (arr[i] - FEATURE_MEANS[i]) / FEATURE_STDS[i];
        arr[i] = normalized;
        
        if (DEBUG_FEATURES) {
            Serial.printf("[NORM] Feature %d: raw=%.2f mean=%.2f std=%.2f normalized=%.4f\n",
                          i, arr[i], FEATURE_MEANS[i], FEATURE_STDS[i], normalized);
        }
    }
}

/* ============================================================
   FEATURE VALIDATION
   ============================================================ */

bool feature_validate(const FeatureVector& features) {
    // Check for NaN or infinity
    if (isnan(features.temp_heel) || isinf(features.temp_heel)) return false;
    if (isnan(features.temp_ball) || isinf(features.temp_ball)) return false;
    if (isnan(features.temp_arch) || isinf(features.temp_arch)) return false;
    if (isnan(features.temp_toe) || isinf(features.temp_toe)) return false;
    
    if (isnan(features.press_heel) || isinf(features.press_heel)) return false;
    if (isnan(features.press_ball) || isinf(features.press_ball)) return false;
    if (isnan(features.press_arch) || isinf(features.press_arch)) return false;
    if (isnan(features.press_toe) || isinf(features.press_toe)) return false;
    
    if (isnan(features.spo2) || isinf(features.spo2)) return false;
    if (isnan(features.heart_rate) || isinf(features.heart_rate)) return false;
    if (isnan(features.step_count) || isinf(features.step_count)) return false;
    
    if (isnan(features.max_pressure) || isinf(features.max_pressure)) return false;
    if (isnan(features.pressure_variance) || isinf(features.pressure_variance)) return false;
    if (isnan(features.max_temp) || isinf(features.max_temp)) return false;
    if (isnan(features.temp_variance) || isinf(features.temp_variance)) return false;
    
    // Check value ranges
    if (features.spo2 < 70.0f || features.spo2 > 100.0f) {
        if (DEBUG_FEATURES) Serial.println("[WARN] SpO2 out of range");
        // Don't fail, just warn - could be sensor error
    }
    
    if (features.heart_rate < 30.0f || features.heart_rate > 200.0f) {
        if (DEBUG_FEATURES) Serial.println("[WARN] HR out of range");
    }
    
    return true;
}

/* ============================================================
   DEBUG FUNCTIONS
   ============================================================ */

void feature_debug_print(const FeatureVector& features) {
    Serial.println("\n[FEATURE VECTOR]");
    Serial.printf("  Temps:     H:%.2f B:%.2f A:%.2f T:%.2f\n",
                  features.temp_heel, features.temp_ball,
                  features.temp_arch, features.temp_toe);
    Serial.printf("  Pressures: H:%.2f B:%.2f A:%.2f T:%.2f\n",
                  features.press_heel, features.press_ball,
                  features.press_arch, features.press_toe);
    Serial.printf("  Vitals:    SpO2:%.2f HR:%.2f Steps:%.0f\n",
                  features.spo2, features.heart_rate, features.step_count);
    Serial.printf("  Engineered: MaxP:%.2f VarP:%.2f MaxT:%.2f VarT:%.2f\n",
                  features.max_pressure, features.pressure_variance,
                  features.max_temp, features.temp_variance);
    Serial.println();
}

