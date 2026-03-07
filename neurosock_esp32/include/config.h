#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

/* ============================================================
   HARDWARE CONFIGURATION
   ============================================================ */

// I2C Configuration
#define I2C_SDA_PIN        21
#define I2C_SCL_PIN        22
#define I2C_FREQ          400000  // 400kHz I2C

// Sensor I2C Addresses
#define MAX30102_ADDR      0x57   // SpO2/HR sensor
#define MPU6050_ADDR       0x68   // Accelerometer/Gyro

// Temperature Sensor (NTC Thermistor)
#define TEMP_PIN           36     // GPIO36 (ADC1_CH0) - Only GPIO36 works with BT

// Pressure Sensors (ADC1 pins - safe with Bluetooth)
#define PRESSURE_HEEL_PIN  32     // ADC1_CH4
#define PRESSURE_BALL_PIN  33     // ADC1_CH5
#define PRESSURE_ARCH_PIN  34     // ADC1_CH6
#define PRESSURE_TOE_PIN   35     // ADC1_CH7

// Bluetooth Configuration
#define BLUETOOTH_NAME     "NeuroSock"
#define BLUETOOTH_BAUD    115200

// Timing
#define SENSOR_CYCLE_MS   2000    // Collect sensors every 2 seconds
#define HAS_TEMP_SENSORS  true    // Enable temperature sensor

/* ============================================================
   NTC THERMISTOR CONFIGURATION
   ============================================================ */

#define NTC_R_SERIES      10000.0   // Series resistor (ohms)
#define NTC_R_NOMINAL     10000.0   // Nominal resistance at 25°C
#define NTC_B_COEFF       3950.0    // B-coefficient (datasheet)
#define NTC_T_NOMINAL     25.0      // Reference temperature (°C)
#define TEMP_BASELINE     0.0       // Fallback if disabled

// Temperature gradients (derived mathematically from heel)
#define TEMP_BALL_OFFSET  -0.3     // Ball cooler than heel
#define TEMP_ARCH_OFFSET  -0.5     // Arch cooler
#define TEMP_TOE_OFFSET   -0.8     // Toe coldest

/* ============================================================
   PRESSURE SENSOR CONFIGURATION
   ============================================================ */

#define PRESSURE_SCALE    77.0     // ADC 0-4095 maps to 0-77 kPa
#define PRESSURE_OFFSET   0.0

// Encoding for BLE packet
#define TEMP_ENCODE_SCALE 2        // (temp - 25) * 2
#define TEMP_ENCODE_OFFSET 25      // Subtract before encoding
#define PRESSURE_ENCODE_SCALE 0.3  // pressure / 0.3

/* ============================================================
   ML INFERENCE CONFIGURATION
   ============================================================ */

#define ML_INPUT_FEATURES      15
#define ML_OUTPUT_SIZE         1
#define ML_INFERENCE_TIMEOUT   100  // ms

// Risk thresholds
#define RISK_LOW_THRESHOLD     0.30f
#define RISK_MODERATE_THRESHOLD 0.60f
#define RISK_HIGH_THRESHOLD    0.80f

// Feature Engineering Constants
#define MAX_TEMP_VALUE     60.0f
#define MIN_TEMP_VALUE     -10.0f
#define MAX_PRESSURE_VALUE 77.0f
#define MIN_PRESSURE_VALUE 0.0f

/* ============================================================
   FEATURE NORMALIZATION (StandardScaler)
   ML Model: Random Forest (15 features)
   From: ML/02_random_forest_model.ipynb scaler.pkl
   
   Feature order:
   0-3:   temp_heel, temp_ball, temp_arch, temp_toe
   4-7:   press_heel, press_ball, press_arch, press_toe
   8:     spo2
   9:     heart_rate
   10:    step_count
   11:    max_pressure
   12:    pressure_variance
   13:    max_temp
   14:    temp_variance
   ============================================================ */

// Placeholder values - EXTRACT FROM ML/02_random_forest_model.ipynb
// Print statement shows: print(f"Feature means ({len(scaler.mean_)} values):")
// and: print(f"Feature scales/stds ({len(scaler.scale_)} values):")

const float FEATURE_MEANS[ML_INPUT_FEATURES] = {
    30.5f,  // temp_heel
    30.2f,  // temp_ball
    30.0f,  // temp_arch
    29.5f,  // temp_toe
    45.0f,  // press_heel
    50.0f,  // press_ball
    42.0f,  // press_arch
    55.0f,  // press_toe
    98.0f,  // spo2
    70.0f,  // heart_rate
    150.0f, // step_count
    55.0f,  // max_pressure (engineered)
    25.0f,  // pressure_variance (engineered)
    30.5f,  // max_temp (engineered)
    15.0f   // temp_variance (engineered)
};

const float FEATURE_STDS[ML_INPUT_FEATURES] = {
    1.2f,   // temp_heel
    1.1f,   // temp_ball
    1.3f,   // temp_arch
    1.0f,   // temp_toe
    8.0f,   // press_heel
    9.0f,   // press_ball
    7.5f,   // press_arch
    10.0f,  // press_toe
    2.0f,   // spo2
    12.0f,  // heart_rate
    400.0f, // step_count
    15.0f,  // max_pressure (engineered)
    40.0f,  // pressure_variance (engineered)
    2.0f,   // max_temp (engineered)
    8.0f    // temp_variance (engineered)
};

/* ============================================================
   ML MODEL CONFIGURATION
   ============================================================ */

#define MODEL_INPUT_SHAPE_BATCH  1
#define MODEL_INPUT_SHAPE_FEATURES 15
#define MODEL_OUTPUT_SHAPE_BATCH 1
#define MODEL_OUTPUT_SHAPE_SIZE  1
#define MODEL_INPUT_TYPE   kTfLiteFloat32
#define MODEL_OUTPUT_TYPE  kTfLiteFloat32

/* ============================================================
   BLUETOOTH PACKET STRUCTURE (17 bytes)
   ============================================================ */

#define BLE_PACKET_SIZE    17

// Packet layout:
// Byte 0-3:   Temperatures (int8 encoded)
// Byte 4-7:   Pressures (uint8 encoded)
// Byte 8:     SpO2 (uint8)
// Byte 9:     Heart Rate (uint8)
// Byte 10-11: Step Count (uint16 big-endian)
// Byte 12:    Risk Probability (uint8 0-100)
// Byte 13:    Risk Level (uint8 0-3)
// Byte 14:    Battery Level (uint8 0-100)
// Byte 15-16: Timestamp (uint16 big-endian)

#define RISK_LEVEL_LOW       0
#define RISK_LEVEL_MODERATE  1
#define RISK_LEVEL_HIGH      2
#define RISK_LEVEL_CRITICAL  3

/* ============================================================
   BUFFER SIZES
   ============================================================ */

#define MAX30102_FIFO_SIZE 32
#define HR_BUFFER_SIZE     60      // ~30s at 2Hz sampling

/* ============================================================
   DEBUG SETTINGS
   ============================================================ */

#define DEBUG_SENSORS      true
#define DEBUG_FEATURES     false
#define DEBUG_INFERENCE    true
#define DEBUG_BLUETOOTH    true
#define DEBUG_TIMING       true

/* ============================================================
   ADC CONFIGURATION
   ============================================================ */

#define ADC_SAMPLES        16      // Averaging samples for noise reduction
#define ADC_SAMPLE_DELAY   200     // microseconds between samples

#endif  // CONFIG_H

