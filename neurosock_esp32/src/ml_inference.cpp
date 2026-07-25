#include "ml_inference.h"
// #include "model.h"  // TFLite model: random_forest_model_tflite[]

/* ============================================================
   GLOBAL ML INFERENCE INSTANCE
   ============================================================ */

MLInference g_ml_inference;

/* ============================================================
   MLINFERENCE CLASS IMPLEMENTATION (STUB - TFLite disabled)
   ============================================================ */

MLInference::MLInference()
    : model(nullptr), interpreter(nullptr), is_loaded(false), 
      is_ready(true), total_inferences(0), total_latency_ms(0) {
}

bool MLInference::initialize() {
    if (DEBUG_INFERENCE) {
        Serial.println("\n[ML] ML inference stubbed (TFLite not available on Arduino ESP32)");
        Serial.println("[ML] ✅ Ready to run with dummy inference");
    }
    
    is_loaded = true;
    is_ready = true;
    return true;
}

MLResult MLInference::infer(const FeatureVector& features) {
    MLResult result;
    result.success = true;
    result.timestamp = millis();
    
    if (!is_ready) {
        result.success = false;
        return result;
    }
    
    unsigned long start_time = micros();
    
    // Dummy inference: return a simple value based on first feature
    // TODO: Replace with actual TFLite inference when ESP-IDF is available
    float prob_dummy = 0.3f + (features.temp_heel * 0.01f);
    if (prob_dummy > 1.0f) prob_dummy = 1.0f;
    if (prob_dummy < 0.0f) prob_dummy = 0.0f;
    
    result.probability = prob_dummy;
    result.risk_level = probability_to_risk_level(result.probability);
    result.latency_ms = (micros() - start_time) / 1000;
    
    if (DEBUG_INFERENCE) {
        Serial.printf("[ML] Dummy inference: prob=%.4f (%u%%), level=%s\n",
                      result.probability,
                      result.get_risk_percent(),
                      result.get_risk_name());
    }
    
    total_inferences++;
    total_latency_ms += result.latency_ms;
    
    return result;
}

uint8_t MLInference::probability_to_risk_level(float prob) {
    if (prob < RISK_LOW_THRESHOLD) {
        return RISK_LEVEL_LOW;
    } else if (prob < RISK_MODERATE_THRESHOLD) {
        return RISK_LEVEL_MODERATE;
    } else if (prob < RISK_HIGH_THRESHOLD) {
        return RISK_LEVEL_HIGH;
    } else {
        return RISK_LEVEL_CRITICAL;
    }
}

void MLInference::shutdown() {
    if (DEBUG_INFERENCE) {
        Serial.println("[ML] Shutting down...");
    }
    
    is_ready = false;
    is_loaded = false;
    interpreter = nullptr;
    model = nullptr;
}

MLInference::~MLInference() {
    shutdown();
}

/* ============================================================
   WRAPPER FUNCTIONS
   ============================================================ */

bool ml_init() {
    return g_ml_inference.initialize();
}

MLResult ml_infer(const FeatureVector& features) {
    return g_ml_inference.infer(features);
}

bool ml_is_ready() {
    return g_ml_inference.get_is_ready();
}

void ml_shutdown() {
    g_ml_inference.shutdown();
}

