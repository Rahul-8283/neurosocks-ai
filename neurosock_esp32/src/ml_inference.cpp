#include "ml_inference.h"
#include "model.h"  // TFLite model: random_forest_model_tflite[]

/* ============================================================
   GLOBAL ML INFERENCE INSTANCE
   ============================================================ */

MLInference g_ml_inference;

/* ============================================================
   MLINFERENCE CLASS IMPLEMENTATION
   ============================================================ */

MLInference::MLInference()
    : model(nullptr), interpreter(nullptr), is_loaded(false), 
      is_ready(false), total_inferences(0), total_latency_ms(0) {
}

bool MLInference::initialize() {
    if (DEBUG_INFERENCE) {
        Serial.println("\n[ML] Initializing TFLite model...");
    }
    
    // Load model from PROGMEM (stored in model.h)
    model = tflite::GetModel(random_forest_model_tflite);
    
    if (model->version() != TFLITE_SCHEMA_VERSION) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Model schema version mismatch!");
        }
        return false;
    }
    
    if (DEBUG_INFERENCE) {
        Serial.println("[ML] ✅ Model loaded from PROGMEM");
    }
    
    // Create interpreter
    static tflite::AllOpsResolver resolver;
    static tflite::micro::MicroInterpreter static_interpreter(
        model, resolver, tensor_arena, TENSOR_ARENA_SIZE, &micro_error_reporter);
    interpreter = &static_interpreter;
    
    // Allocate tensors
    TfLiteStatus alloc_status = interpreter->AllocateTensors();
    if (alloc_status != kTfLiteOk) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Failed to allocate tensors!");
        }
        return false;
    }
    
    if (DEBUG_INFERENCE) {
        Serial.println("[ML] ✅ Tensors allocated");
    }
    
    // Verify input tensor
    TfLiteTensor* input = interpreter->input(0);
    if (input->type != kTfLiteFloat32) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Input tensor type mismatch!");
        }
        return false;
    }
    
    if (DEBUG_INFERENCE) {
        Serial.printf("[ML] Input shape: [%d, %d]\n", 
                      input->dims->data[0], input->dims->data[1]);
    }
    
    // Verify output tensor
    TfLiteTensor* output = interpreter->output(0);
    if (output->type != kTfLiteFloat32) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Output tensor type mismatch!");
        }
        return false;
    }
    
    if (DEBUG_INFERENCE) {
        Serial.printf("[ML] Output shape: [%d]\n", output->dims->data[0]);
        Serial.println("[ML] ✅ TFLite model ready!\n");
    }
    
    is_loaded = true;
    is_ready = true;
    return true;
}

MLResult MLInference::infer(const FeatureVector& features) {
    MLResult result;
    result.success = false;
    result.probability = 0.0f;
    result.risk_level = 0;
    result.timestamp = millis();
    
    if (!is_ready || !interpreter) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Model not ready");
        }
        return result;
    }
    
    // Start timer for latency measurement
    unsigned long start_time = micros();
    
    // Get input tensor
    TfLiteTensor* input = interpreter->input(0);
    if (!input) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Failed to get input tensor");
        }
        return result;
    }
    
    // Get feature array and copy to input tensor
    float* feature_array = (float*)features.to_array();
    
    // Verify feature count
    const int num_features = input->dims->data[1];
    if (num_features != 15) {
        if (DEBUG_INFERENCE) {
            Serial.printf("[ML] ❌ Feature count mismatch! Expected %d, got 15\n", 
                          num_features);
        }
        return result;
    }
    
    // Copy features to input tensor
    float* input_data = input->data.f;
    for (int i = 0; i < 15; i++) {
        input_data[i] = feature_array[i];
    }
    
    if (DEBUG_INFERENCE) {
        Serial.println("[ML] Features loaded into input tensor");
    }
    
    // Run inference
    TfLiteStatus invoke_status = interpreter->Invoke();
    unsigned long end_time = micros();
    uint32_t latency = (end_time - start_time) / 1000;  // Convert to ms
    result.latency_ms = latency;
    
    if (invoke_status != kTfLiteOk) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Inference failed");
        }
        return result;
    }
    
    if (DEBUG_INFERENCE) {
        Serial.printf("[ML] Inference completed in %lu ms\n", latency);
    }
    
    // Get output tensor
    TfLiteTensor* output = interpreter->output(0);
    if (!output || !output->data.f) {
        if (DEBUG_INFERENCE) {
            Serial.println("[ML] ❌ Failed to get output tensor");
        }
        return result;
    }
    
    // Extract probability (output[0][0])
    result.probability = output->data.f[0];
    
    // Clamp probability to  [0, 1]
    if (result.probability < 0.0f) result.probability = 0.0f;
    if (result.probability > 1.0f) result.probability = 1.0f;
    
    // Classify risk level
    result.risk_level = probability_to_risk_level(result.probability);
    
    result.success = true;
    
    // Update statistics
    total_inferences++;
    total_latency_ms += latency;
    
    if (DEBUG_INFERENCE) {
        Serial.printf("[ML] ✅ Result: probability=%.4f (%u%%), level=%s\n",
                      result.probability,
                      result.get_risk_percent(),
                      result.get_risk_name());
    }
    
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

