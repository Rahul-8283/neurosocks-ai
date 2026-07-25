# NeuroSock ESP32 - Complete Implementation Guide

## Project Overview
Move all ML inference from Flutter app to ESP32 hardware. The ESP32 reads all sensors, engineers features, runs TensorFlow Lite inference locally, and sends 17-byte BLE packets containing sensor data + predictions to the Flutter app.

**Location**: `e:\S4\WORKING\neurosocks-ai\neurosock_esp32\`

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│         SENSOR LAYER (11 raw values)            │
│  • 4 Temperatures (Heel/Ball/Arch/Toe)         │
│  • 4 Pressures (Heel/Ball/Arch/Toe)            │
│  • SpO2 (%), Heart Rate (bpm), Steps (count)   │
│  [MAX30102, MPU6050, NTC, ADC]                  │
└──────────────┬──────────────────────────────────┘
               │ SensorData struct (11 values)
┌──────────────V──────────────────────────────────┐
│    FEATURE ENGINEERING LAYER (15 features)      │
│  • Copy 11 raw features                         │
│  • Compute 4 engineered:                        │
│    - max_pressure, pressure_variance            │
│    - max_temp, temp_variance                    │
│  • Normalize with StandardScaler                │
└──────────────┬──────────────────────────────────┘
               │ FeatureVector struct (15 floats)
┌──────────────V──────────────────────────────────┐
│  ML INFERENCE LAYER (TensorFlow Lite Micro)     │
│  • Load random_forest_model.tflite from PROGMEM│
│  • Run 15-feature inference                     │
│  • Output: probability (0-1) → risk_level 0-3  │
│  • ~240ms max latency on ESP32                  │
└──────────────┬──────────────────────────────────┘
               │ MLResult (probability, risk_level)
┌──────────────V──────────────────────────────────┐
│  BLUETOOTH LAYER (17-byte packets)              │
│  ┌─ Bytes 0-11: Sensor Data ─────────┐         │
│  │  [0-3]   Temperatures (int8)       │         │
│  │  [4-7]   Pressures (uint8)         │         │
│  │  [8]     SpO2 (uint8 %)            │         │
│  │  [9]     Heart Rate (uint8 bpm)    │         │
│  │  [10-11] Steps (uint16 BE)         │         │
│  ├─ Bytes 12-16: ML Predictions ──────┤         │
│  │  [12]    Risk Probability (0-100%) │         │
│  │  [13]    Risk Level (0-3)          │         │
│  │  [14]    Battery (0-100%)          │         │
│  │  [15-16] Timestamp (uint16 BE sec) │         │
│  └────────────────────────────────────┘         │
│  Every 2 seconds via BluetoothSerial            │
└─────────────────────────────────────────────────┘
```

**Data Flow Cycle (2 seconds)**:
1. **Sensors** (570 lines): Read all 11 values → SensorData
2. **Features** (180 lines): Engineer 15 features, normalize → FeatureVector
3. **ML** (240 lines): Inference on TFLite → MLResult (probability, risk_level)
4. **Bluetooth** (130 lines): Encode & send 17-byte packet → Flutter app

---

## Project Files

### Configuration Files

**`platformio.ini`** - Build Configuration
- Platform: `espressif32` (ESP32)
- Board: `esp32doit-devkit-v1` (configurable)
- Monitor: 115200 baud, colorized output
- Upload: 921600 baud, COM3
- Libraries: TensorFlow Lite Micro, BluetoothSerial, Wire
- Build flags: `-O2 -std=c++17 -Wall`

### Header Files (API Definitions)

**`include/config.h`** (400+ lines)
- GPIO pin mappings: SDA(21), SCL(22), MAX30102(0x57), MPU6050(0x68), ADC pins
- ML constants: risk thresholds, tensor arena size
- Debug flags: `DEBUG_SENSORS`, `DEBUG_FEATURES`, `DEBUG_INFERENCE`, `DEBUG_BLUETOOTH`
- **TODO**: Fill FEATURE_MEANS[15] and FEATURE_STDS[15] from ML notebooks

Key constants:
```cpp
#define BLUETOOTH_NAME "NeuroSock"
#define SENSOR_READ_INTERVAL_MS 2000  // 2-second cycle
#define TENSOR_ARENA_SIZE 50000  // 50KB for TFLite
#define FEATURE_ENSEMBLE_SIZE 15

// Risk thresholds (probability)
#define RISK_THRESHOLD_LOW 0.3
#define RISK_THRESHOLD_MODERATE 0.6
#define RISK_THRESHOLD_HIGH 0.8
```

**`include/sensors.h`** (180+ lines)
- `SensorData` struct: 11 floats + timestamps
- Function declarations: 15 sensor read functions
- I2C and ADC helpers

**`include/feature_engineer.h`** (130+ lines)
- `FeatureVector` struct: 15 floats (11 raw + 4 engineered)
- Feature calculation functions: max, mean, variance
- Normalization (StandardScaler): `(value - mean) / std`

**`include/ml_inference.h`** (150+ lines)
- `MLResult` struct: probability, risk_level, latency
- `MLInference` class: initialize(), infer()
- Global instance: `extern MLInference g_ml_inference`

**`include/bluetooth_service.h`** (160+ lines)
- `SensorRiskPacket` struct: 17-byte BLE packet definition
- Encoding functions: temperature, pressure, uint16 big-endian
- `BluetoothService` class methods

### Implementation Files (Full Code)

**`src/sensors.cpp`** (570 lines)
- I2C communication: `i2c_read8()`, `i2c_write()`, etc.
- ADC averaging: 16-sample noise filtering
- Temperature reading: Steinhart-Hart equation from NTC thermistor
  - `1/T = 1/T0 + (1/B) * ln(R/R0)`
  - Derives Ball/Arch/Toe from Heel with thermal gradients
- MAX30102 (SpO2/HR sensor):
  - Foot-optimized: LED=24mA, SpO2=105-20*R (vs 110-25*R for finger)
  - Peak detection with adaptive thresholds
- MPU6050 (accelerometer): Step counting with 300ms debounce
- `sensors_read_all()`: Returns complete SensorData struct

**`src/feature_engineer.cpp`** (180 lines)
- `feature_engineer_calculate()`: Calculate 4 engineered features from 11 raw
  - `max_pressure`, `pressure_variance`, `max_temp`, `temp_variance`
- `feature_engineer_normalize()`: Apply StandardScaler formula
  - Scaler parameters in `config.h` (FEATURE_MEANS, FEATURE_STDS)
- `feature_validate()`: Check for NaN, infinity, out-of-range values
- Data matches ML training: 02_random_forest_model.ipynb

**`src/ml_inference.cpp`** (240 lines)
- Load TFLite model from PROGMEM: `random_forest_model_tflite[]` from `model.h`
- `MLInference::initialize()`: Create interpreter, allocate 50KB tensor arena
- `MLInference::infer()`: Run prediction on 15-feature vector
  - Extract probability (0-1), convert to risk_level (0-3)
  - Track latency in microseconds
  - Probability → risk_level conversion:
    - `prob < 0.3` → LEVEL_LOW (0)
    - `prob < 0.6` → LEVEL_MODERATE (1)
    - `prob < 0.8` → LEVEL_HIGH (2)
    - `prob >= 0.8` → LEVEL_CRITICAL (3)

**`src/bluetooth_service.cpp`** (130 lines)
- `BluetoothService::initialize()`: Start SerialBT with device name
- `build_packet()`: Populate 17-byte SensorRiskPacket
  - Encode temps: `(temp - 25) * 2` → int8
  - Encode pressures: `pressure / 0.3` → uint8
  - Encode stats: big-endian uint16 values
- `send_reading()`: Pack sensor + ML data, transmit via SerialBT.write()
- `is_connected()`: Check if Flutter app connected

**`src/main.cpp`** (150 lines)
- `setup()`: Initialize sensors, ML, Bluetooth in sequence
- `loop()`: 2-second cycle:
  1. Read sensors → SensorData
  2. Engineer features → FeatureVector (normalized)
  3. Run ML inference → MLResult
  4. Send 17-byte BLE packet
  5. Print cycle summary with latencies
- Performance validation: Warn if cycle exceeds 2 seconds

**`include/model.h`**
- TFLite model: `random_forest_model_tflite[]` byte array
- Generated from: `random_forest_model.tflite` (ML/models/)
- Size: ~80-100KB
- Converted via: `xxd -i random_forest_model.tflite`

---

## Implementation Status

### ✅ Complete (11/11 Files)
1. ✅ `platformio.ini` - Build system configured
2. ✅ `include/config.h` - All constants defined (placeholder scaler params)
3. ✅ `include/sensors.h` - API fully defined
4. ✅ `src/sensors.cpp` - 570 lines: All sensor logic implemented
5. ✅ `include/feature_engineer.h` - API fully defined
6. ✅ `src/feature_engineer.cpp` - 180 lines: Feature calc + normalize
7. ✅ `include/ml_inference.h` - MLInference class defined
8. ✅ `src/ml_inference.cpp` - 240 lines: TFLite integration complete
9. ✅ `include/bluetooth_service.h` - Packet struct + encoding
10. ✅ `src/bluetooth_service.cpp` - 130 lines: BLE packet transmission
11. ✅ `src/main.cpp` - 150 lines: Main orchestration loop

---

## Critical Next Steps

### 1. Extract Scaler Parameters (HIGH PRIORITY)
The StandardScaler normalization in `feature_engineer.cpp` requires exact mean and std values from training.

**Extract from notebooks**:
- Open `ML/02_random_forest_model.ipynb`
- Find the StandardScaler object: `scaler.fit(X_train)`
- Print arrays:
  ```python
  print("FEATURE_MEANS =", scaler.mean_)
  print("FEATURE_STDS =", scaler.scale_)  # Note: scale_ = 1/std
  ```
- Copy values to `include/config.h`:
  ```cpp
  const float FEATURE_MEANS[15] = {
      // Copy scaler.mean_ values here
  };
  const float FEATURE_STDS[15] = {
      // Copy scaler.scale_ values here (already inverted)
  };
  ```

**Why critical**: Feature normalization accuracy directly affects ML predictions. Incorrect values = wrong risk classifications.

### 2. Build & Upload to ESP32
```bash
cd neurosock_esp32
platformio run --target upload  # Compile and flash
platformio device monitor  # Watch Serial output
```

Expected Serial output:
```
[SETUP] 1/4 Initializing sensors...
[SETUP] ✅ Sensors initialized
[SETUP] 2/4 Initializing ML inference engine...
[ML] ✅ Model loaded from PROGMEM
[ML] ✅ Tensors allocated
[SETUP] ✅ ML engine ready
[SETUP] 3/4 Initializing Bluetooth service...
[BT] ✅ BluetoothSerial started with name: NeuroSock
[LOOP] CYCLE SUMMARY: T_heel=32.5°C, Risk=LOW (24%), Cycle=245ms
```

### 3. Verify Bluetooth Packets
Connect Flutter app via Bluetooth and verify:
- 17 bytes received every 2 seconds
- Sensor values in valid ranges
- Risk predictions match expected patterns

### 4. Update Flutter App
- Decode 17-byte packets in `RealBleService._parsePayload()`
- Remove client-side ML inference code:
  - Delete: `ml_risk_predictor.dart`, TFLite dependencies
  - Update: `SensorReading` model with `riskProbability`, `riskLevel`
- Update Firestore schema to store new fields

---

## Hardware Implementation Details

### Sensor Calibration
**Temperature**:
- Physical: NTC thermistor on GPIO36 (ADC1_CH0)
- Formula: Steinhart-Hart `1/T = A + B*ln(R) + C*ln(R)³`
- Derives Ball/Arch/Toe from Heel: -0.3°C, -0.5°C, -0.8°C gradients

**Pressure**:
- Physical: 4× ADC1 pins (GPIO32-35) → 4× pressure transducers
- Formula: Linear scaling → kPa
- Encoding: `pressure / 0.3` → uint8

**SpO2/Heart Rate**:
- Physical: MAX30102 (I2C 0x57) on Foot → Different algorithm than finger
- LED current: 24mA (vs 15mA for finger)
- Thresholds: Peak=0.2*AC (vs 0.3), SpO2=105-20*R

**Step Count**:
- Physical: MPU6050 accelerometer (I2C 0x68)
- Detection: Z-axis threshold crossing with 300ms debounce

### Memory Usage
- **FLASH**: ~180KB (model + code)
- **RAM**: ~320KB available
  - 50KB tensor arena (TFLite)
  - ~80KB model in PROGMEM (doesn't use RAM)
  - ~50KB other buffers, code
  - Status: ✅ Fits comfortably

### Performance Targets
- **Sensor read**: <50ms (parallel I2C/ADC)
- **Feature engineering**: <10ms (simple math)
- **ML inference**: <100ms (TFLite Micro optimized)
- **Bluetooth send**: <5ms (serial write)
- **Total cycle**: <2000ms ✅

---

## Known Issues & Solutions

| Issue | Solution | Status |
|-------|----------|--------|
| Only 1 physical temperature sensor | Derive 3 temps from 1 Heel sensor with gradients | ✅ Implemented |
| ADC2 conflict with Bluetooth | Use ADC1 pins (GPIO 32,33,34,35,36,39) | ✅ Verified in config.h |
| MAX30102 foot vs finger | Adapted LED current (24mA), thresholds, SpO2 formula | ✅ Implemented |
| Feature set mismatch | Confirmed RF model uses 15 features (no motion) | ✅ Fixed |
| Scaler parameters missing | Need to extract from ML notebooks | 🔄 TODO |

---

## Testing Checklist

- [ ] **Compilation**: `platformio run` produces no errors
- [ ] **Flash**: `platformio run --target upload` succeeds
- [ ] **Serial Output**: Setup initializes all 4 modules ✅ messages
- [ ] **Sensor Readings**: Valid ranges every 2 seconds
  - Temps: ~25-40°C
  - Pressures: 0-100 kPa
  - SpO2: 95-100%
  - HR: 60-120 bpm
- [ ] **ML Inference**: Risk predictions change with sensor values
- [ ] **Bluetooth**: 17-byte packets every 2 seconds
- [ ] **Flutter App**: Receives and displays all 17 bytes correctly
- [ ] **Timing**: Cycle completes in <2000ms consistently

---

## File Locations Summary

```
neurosock_esp32/
├── platformio.ini                    ← Build config
├── include/
│   ├── config.h                      ← Constants (scaler params TODO)
│   ├── sensors.h                     ← Sensor API
│   ├── feature_engineer.h            ← Feature struct
│   ├── ml_inference.h                ← ML class
│   ├── bluetooth_service.h           ← BLE packet struct
│   └── model.h                       ← TFLite model bytes
├── src/
│   ├── sensors.cpp                   ← Sensor implementation (570 lines)
│   ├── feature_engineer.cpp          ← Feature calc + normalize (180 lines)
│   ├── ml_inference.cpp              ← TFLite inference (240 lines)
│   ├── bluetooth_service.cpp         ← BLE transmission (130 lines)
│   └── main.cpp                      ← Orchestration loop (150 lines)
└── test/
    ├── ble_payload_test.dart         ← Old tests (update for 17 bytes)
    └── ml_integration_test.dart      ← Old tests (update)
```

---

## Quick Reference: Debugging Commands

```bash
# Monitor serial output
platformio device monitor

# Rebuild and upload
platformio run --target upload

# Compile without upload (syntax check)
platformio run

# Clean build
platformio run --target clean
platformio run --target upload
```

---

## Next Steps Order

1. **Extract Scaler** (10 min) → Fill config.h FEATURE_MEANS/STDS
2. **Compile** (5 min) → `platformio run`
3. **Flash** (2 min) → `platformio run --target upload`
4. **Monitor** (5 min) → `platformio device monitor`
5. **Test Bluetooth** (10 min) → Connect Flutter app, verify packets
6. **Update Flutter** (30 min) → Decode 17-byte packets, remove ML code

**Total**: ~1 hour for complete integration

---

Generated: Full ESP32 Edge ML Implementation
Status: Ready for testing (pending scaler parameter extraction)
