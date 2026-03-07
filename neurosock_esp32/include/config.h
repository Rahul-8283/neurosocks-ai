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

// Extracted from ML/02_random_forest_model.ipynb StandardScaler during training
// Source: scaler.mean_ and scaler.scale_ from RF model trained on 8000 synthetic samples
// Accuracy: 92.45% | ROC-AUC: 97.98%

const float FEATURE_MEANS[ML_INPUT_FEATURES] = {
    34.377127267113607f,  // temp_heel
    34.376776436691941f,  // temp_ball
    34.384331094983494f,  // temp_arch
    34.404600260634702f,  // temp_toe
    44.134212921268379f,  // press_heel
    43.937746057938966f,  // press_ball
    43.832688437183343f,  // press_arch
    44.349988690344688f,  // press_toe
    92.488721981641774f,  // spo2
    94.265249999999995f,  // heartRate
    59.760500000000000f,  // stepCount
    64.597849484194811f,  // max_pressure (engineered)
    358.746560145869012f, // pressure_variance (engineered)
    36.387833158608558f,  // max_temp (engineered)
    3.330151855516803f    // temp_variance (engineered)
};

const float FEATURE_STDS[ML_INPUT_FEATURES] = {
    0.565352534871213f,   // temp_heel
    0.560907760479280f,   // temp_ball
    0.569056385618529f,   // temp_arch
    0.547891185470064f,   // temp_toe
    0.054544126291903f,   // press_heel
    0.054640308757458f,   // press_ball
    0.054551972382659f,   // press_arch
    0.052693993830820f,   // press_toe
    0.231752998642186f,   // spo2
    0.049385116193493f,   // heartRate
    0.029076658782992f,   // stepCount
    0.046230085918394f,   // max_pressure (engineered)
    0.002327744445261f,   // pressure_variance (engineered)
    0.499504192726976f,   // max_temp (engineered)
    0.274311583009886f    // temp_variance (engineered)
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

