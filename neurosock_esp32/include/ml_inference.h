#ifndef ML_INFERENCE_H
#define ML_INFERENCE_H

#include <Arduino.h>
#include "config.h"
#include "feature_engineer.h"

// TensorFlow Lite headers
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"

/* ============================================================
   ML INFERENCE RESULT STRUCTURE
   ============================================================ */

struct MLResult {
    bool success;
    float probability;      // 0.0 to 1.0
    uint8_t risk_level;    // 0=LOW, 1=MODERATE, 2=HIGH, 3=CRITICAL
    uint32_t latency_ms;   // Inference time in milliseconds
    uint32_t timestamp;    // When inference was run
    
    /**
     * Get risk percentage (0-100)
     */
    uint8_t get_risk_percent() const {
        return (uint8_t)(probability * 100.0f);
    }
    
    /**
     * Get risk level name
     */
    const char* get_risk_name() const {
        switch (risk_level) {
            case 0: return "LOW";
            case 1: return "MODERATE";
            case 2: return "HIGH";
            case 3: return "CRITICAL";
            default: return "UNKNOWN";
        }
    }
};

/* ============================================================
   ML INFERENCE CLASS
   ============================================================ */

class MLInference {
private:
    // TFLite components
    tflite::MicroErrorReporter micro_error_reporter;
    const tflite::Model* model;
    tflite::MicroInterpreter* interpreter;
    
    // Tensor arena (working memory for inference)
    static constexpr size_t TENSOR_ARENA_SIZE = 50 * 1024;  // 50KB
    uint8_t tensor_arena[TENSOR_ARENA_SIZE];
    
    // TensorFlow Lite Micro resolver
    tflite::AllOpsResolver resolver;
    
    // Model status
    bool is_loaded;
    bool is_ready;
    
    // Statistics
    uint32_t total_inferences;
    uint32_t total_latency_ms;
    
public:
    /**
     * Constructor
     */
    MLInference();
    
    /**
     * Initialize and load model from PROGMEM
     * Returns: true if successful, false if error
     */
    bool initialize();
    
    /**
     * Run inference on feature vector
     * Input: FeatureVector (normalized features)
     * Returns: MLResult with probability and risk level
     */
    MLResult infer(const FeatureVector& features);
    
    /**
     * Get model load status
     */
    bool get_is_loaded() const { return is_loaded; }
    bool get_is_ready() const { return is_ready; }
    
    /**
     * Get average inference latency since startup
     */
    float get_average_latency() const {
        if (total_inferences == 0) return 0.0f;
        return (float)total_latency_ms / (float)total_inferences;
    }
    
    /**
     * Get total number of inferences run
     */
    uint32_t get_total_inferences() const { return total_inferences; }
    
    /**
     * Shutdown and release resources
     */
    void shutdown();
    
    /**
     * Destructor
     */
    ~MLInference();
    
private:
    /**
     * Convert probability to risk level
     * 0.0-0.3: LOW (0)
     * 0.3-0.6: MODERATE (1)
     * 0.6-0.8: HIGH (2)
     * 0.8+: CRITICAL (3)
     */
    uint8_t probability_to_risk_level(float prob);
};

/* ============================================================
   GLOBAL ML INFERENCE INSTANCE
   ============================================================ */

extern MLInference g_ml_inference;

/**
 * Initialize ML module (wrapper function)
 */
bool ml_init();

/**
 * Run inference (wrapper function)
 */
MLResult ml_infer(const FeatureVector& features);

/**
 * Get ML ready status (wrapper function)
 */
bool ml_is_ready();

/**
 * Shutdown ML (wrapper function)
 */
void ml_shutdown();

#endif  // ML_INFERENCE_H

