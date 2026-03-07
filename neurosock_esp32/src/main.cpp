#include <Arduino.h>
#include "config.h"
#include "sensors.h"
#include "feature_engineer.h"
#include "ml_inference.h"
#include "bluetooth_service.h"

/* ============================================================
   FORWARD DECLARATIONS
   ============================================================ */

void print_cycle_summary(const SensorData& sensor_data,
                         const MLResult& ml_result,
                         uint32_t cycle_duration);

void handle_fatal_error(const char* error_msg);

/* ============================================================
   GLOBAL STATE VARIABLES
   ============================================================ */

uint32_t last_reading_time = 0;
uint32_t reading_count = 0;
uint8_t battery_level = 100;

/* ============================================================
   SETUP: INITIALIZE ALL MODULES
   ============================================================ */

void setup() {
    // Initialize Serial for debug output
    Serial.begin(115200);
    delay(500);
    
    Serial.println("\n\n");
    Serial.println("╔════════════════════════════════════════════════════════╗");
    Serial.println("║      NeuroSock ESP32 - Edge ML Inference System        ║");
    Serial.println("║         Initializing all modules...                    ║");
    Serial.println("╚════════════════════════════════════════════════════════╝\n");
    
    // Initialize sensors
    Serial.println("[SETUP] 1/4 Initializing sensors...");
    if (!sensors_init()) {
        Serial.println("[SETUP] ❌ Sensor initialization failed!");
        while (1) delay(1000);
    }
    Serial.println("[SETUP] ✅ Sensors initialized\n");
    
    // Initialize ML inference
    Serial.println("[SETUP] 2/4 Initializing ML inference engine...");
    if (!ml_init()) {
        Serial.println("[SETUP] ❌ ML initialization failed!");
        while (1) delay(1000);
    }
    Serial.println("[SETUP] ✅ ML engine ready\n");
    
    // Initialize Bluetooth
    Serial.println("[SETUP] 3/4 Initializing Bluetooth service...");
    if (!bt_init()) {
        Serial.println("[SETUP] ❌ Bluetooth initialization failed!");
        while (1) delay(1000);
    }
    Serial.println("[SETUP] ✅ Bluetooth service running\n");
    
    // Initialize timing
    last_reading_time = millis();
    Serial.println("[SETUP] 4/4 System ready!\n");
    
    Serial.println("╔════════════════════════════════════════════════════════╗");
    Serial.println("║  Waiting for Bluetooth connection from Flutter app...  ║");
    Serial.println("║              (starting sensor readings)                ║");
    Serial.println("╚════════════════════════════════════════════════════════╝\n");
}

/* ============================================================
   LOOP: MAIN EXECUTION CYCLE
   ============================================================ */

void loop() {
    uint32_t current_time = millis();
    
    // Check if it's time to take a reading (every 2 seconds)
    if (current_time - last_reading_time >= SENSOR_CYCLE_MS) {
        uint32_t cycle_start = micros();
        
        // ========== STEP 1: READ ALL SENSORS ==========
        SensorData sensor_data = sensors_read_all();
        
        // ========== STEP 2: ENGINEER FEATURES ==========
        FeatureVector features;
        feature_engineer_calculate(sensor_data, features);
        feature_engineer_normalize(features);
        
        // Validate features before ML
        if (!feature_validate(features)) {
            Serial.println("[LOOP] ⚠️  Invalid features, skipping this cycle");
            last_reading_time = current_time;
            return;
        }
        
        // ========== STEP 3: RUN ML INFERENCE ==========
        MLResult ml_result = ml_infer(features);
        
        // ========== STEP 4: SEND VIA BLUETOOTH ==========
        if (!bt_send_reading(sensor_data, ml_result, battery_level)) {
            if (DEBUG_BLUETOOTH) {
                Serial.println("[LOOP] ⚠️  Bluetooth send failed (client may not be connected)");
            }
        }
        
        // ========== STEP 5: PERFORMANCE METRICS ==========
        uint32_t cycle_duration = (micros() - cycle_start) / 1000;  // Convert to ms
        reading_count++;
        last_reading_time = current_time;
        
        // Print cycle summary (every 5 readings)
        if (reading_count % 5 == 0) {
            print_cycle_summary(sensor_data, ml_result, cycle_duration);
        }
        
        // Validate cycle timing
        if (cycle_duration > SENSOR_READ_INTERVAL_MS) {
            Serial.printf("[LOOP] ⚠️  Cycle time exceeded: %ums > %ums\n",
                          cycle_duration, (uint32_t)SENSOR_READ_INTERVAL_MS);
        }
    }
}

/* ============================================================
   HELPER FUNCTIONS
   ============================================================ */

void print_cycle_summary(const SensorData& sensor_data,
                         const MLResult& ml_result,
                         uint32_t cycle_duration) {
    Serial.println("\n╭─ CYCLE SUMMARY ──────────────────────────────────────────");
    
    // Sensor summary
    Serial.printf("│ SENSORS: ");
    Serial.printf("T_heel=%.1f°C, P_heel=%.1f kPa, ", 
                  sensor_data.temp_heel, sensor_data.press_heel);
    Serial.printf("SpO2=%d%%, HR=%d bpm\n", (uint8_t)sensor_data.spo2, sensor_data.heart_rate);
    
    // ML prediction summary
    Serial.printf("│ ML: Risk=%.1f%% [%s], Latency=%ums\n",
                  ml_result.get_risk_percent() * 1.0f,
                  ml_result.get_risk_name(),
                  ml_result.latency_ms);
    
    // Performance metrics
    Serial.printf("│ PERF: Cycle time=%ums, Total readings=%u, BT connected=%s\n",
                  cycle_duration, reading_count,
                  bt_is_connected() ? "✅" : "❌");
    
    Serial.println("╰─────────────────────────────────────────────────────────────\n");
}

/* ============================================================
   ERROR HANDLERS
   ============================================================ */

void handle_fatal_error(const char* error_msg) {
    Serial.printf("\n❌ FATAL ERROR: %s\n", error_msg);
    Serial.println("System halting...");
    while (1) {
        delay(1000);
    }
}