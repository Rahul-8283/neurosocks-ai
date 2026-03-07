#include "sensors.h"
#include <cmath>

/* ============================================================
   GLOBAL STATE VARIABLES
   ============================================================ */

// MAX30102 FIFO buffers
uint32_t ir_buffer[HR_BUFFER_SIZE];
uint32_t red_buffer[HR_BUFFER_SIZE];
int fifo_index = 0;
bool fifo_full = false;

// MPU6050 state
float prev_accel_magnitude = 0;
bool step_high = false;
uint16_t step_counter = 0;
unsigned long last_step_time = 0;
const unsigned long STEP_DEBOUNCE = 300;  // ms

// Last sensor readings
SensorData last_sensor_data = {};

/* ============================================================
   I2C HELPER FUNCTIONS
   ============================================================ */

void i2c_write(uint8_t addr, uint8_t reg, uint8_t val) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

uint8_t i2c_read8(uint8_t addr, uint8_t reg) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(addr, (uint8_t)1);
    return Wire.available() ? Wire.read() : 0;
}

int16_t i2c_read16(uint8_t addr, uint8_t reg) {
    Wire.beginTransmission(addr);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(addr, (uint8_t)2);
    if (Wire.available() == 2) {
        int16_t hi = Wire.read();
        int16_t lo = Wire.read();
        return (hi << 8) | lo;
    }
    return 0;
}

/* ============================================================
   ADC HELPER FUNCTIONS
   ============================================================ */

float adc_read_average(int pin) {
    long sum = 0;
    for (int i = 0; i < ADC_SAMPLES; i++) {
        sum += analogRead(pin);
        delayMicroseconds(ADC_SAMPLE_DELAY);
    }
    return (float)sum / (float)ADC_SAMPLES;
}

float adc_read_thermistor(int pin) {
    float adc_val = adc_read_average(pin);
    
    if (DEBUG_SENSORS) {
        Serial.printf("[NTC] GPIO%d raw ADC: %.1f\n", pin, adc_val);
    }
    
    // Check for open circuit or short
    if (adc_val < 1.0 || adc_val > 4090.0) {
        if (DEBUG_SENSORS) {
            Serial.printf("[NTC] GPIO%d REJECTED (open/short)\n", pin);
        }
        return 0.0;
    }
    
    // Calculate resistance using voltage divider
    // V_out = V_in * ADC_val / 4095
    // V_out = V_in * R_nct / (R_series + R_nct)
    // R_nct = R_series * V_out / (V_in - V_out)
    // R_nct = R_series * ADC_val / (4095 - ADC_val)
    float resistance = NTC_R_SERIES * adc_val / (4095.0 - adc_val);
    
    // Steinhart-Hart equation
    // 1/T = 1/T0 + (1/B) * ln(R/R0)
    float steinhart = log(resistance / NTC_R_NOMINAL) / NTC_B_COEFF;
    steinhart += 1.0 / (NTC_T_NOMINAL + 273.15);
    float temp_c = 1.0 / steinhart - 273.15;
    
    // Reject invalid readings
    if (temp_c < MIN_TEMP_VALUE || temp_c > MAX_TEMP_VALUE) {
        return 0.0;
    }
    
    return temp_c;
}

float adc_read_pressure(int pin) {
    float adc_val = adc_read_average(pin);
    return adc_val * PRESSURE_SCALE / 4095.0;
}

/* ============================================================
   TEMPERATURE FUNCTIONS
   ============================================================ */

float sensors_read_temperature_heel() {
    if (!HAS_TEMP_SENSORS) {
        return TEMP_BASELINE;
    }
    return adc_read_thermistor(TEMP_PIN);
}

void sensors_read_temperatures(float* temps) {
    if (!HAS_TEMP_SENSORS) {
        temps[0] = temps[1] = temps[2] = temps[3] = TEMP_BASELINE;
        return;
    }
    
    float heel = adc_read_thermistor(TEMP_PIN);
    temps[0] = heel;
    temps[1] = heel + TEMP_BALL_OFFSET;
    temps[2] = heel + TEMP_ARCH_OFFSET;
    temps[3] = heel + TEMP_TOE_OFFSET;
    
    if (DEBUG_SENSORS) {
        Serial.printf("[TEMPS] H:%.1f B:%.1f A:%.1f T:%.1f\n", 
                      temps[0], temps[1], temps[2], temps[3]);
    }
}

/* ============================================================
   PRESSURE FUNCTIONS
   ============================================================ */

void sensors_read_pressures(float* pressures) {
    pressures[0] = adc_read_pressure(PRESSURE_HEEL_PIN);
    pressures[1] = adc_read_pressure(PRESSURE_BALL_PIN);
    pressures[2] = adc_read_pressure(PRESSURE_ARCH_PIN);
    pressures[3] = adc_read_pressure(PRESSURE_TOE_PIN);
    
    if (DEBUG_SENSORS) {
        Serial.printf("[PRESS] H:%.1f B:%.1f A:%.1f T:%.1f\n",
                      pressures[0], pressures[1], pressures[2], pressures[3]);
    }
}

/* ============================================================
   MAX30102 FUNCTIONS (SpO2/HR)
   ============================================================ */

void max30102_init() {
    Serial.println("\n=== MAX30102 INITIALIZATION ===");
    delay(100);
    
    // Verify I2C
    Serial.print("[1] Checking I2C connection to 0x57... ");
    Wire.beginTransmission(MAX30102_ADDR);
    int error = Wire.endTransmission();
    if (error == 0) {
        Serial.println("✅ ACK");
    } else {
        Serial.printf("❌ Error: %d\n", error);
        return;
    }
    
    // Read Part ID
    Serial.print("[2] Reading Part ID... ");
    uint8_t id = i2c_read8(MAX30102_ADDR, 0xFF);
    Serial.printf("ID: 0x%02X\n", id);
    if (id != 0x15) {
        Serial.printf("❌ Wrong ID! Expected 0x15\n");
        return;
    }
    Serial.println("✅ Correct MAX30102");
    
    // Reset
    Serial.print("[3] Sending RESET... ");
    i2c_write(MAX30102_ADDR, 0x09, 0x40);
    delay(100);
    Serial.println("✅");
    
    // Configure FIFO
    Serial.print("[4] Configuring FIFO... ");
    i2c_write(MAX30102_ADDR, 0x08, 0x50);  // Sample avg=4, rollover=ON
    Serial.println("✅");
    
    // Set Mode to SpO2
    Serial.print("[5] Setting SpO2 mode... ");
    i2c_write(MAX30102_ADDR, 0x09, 0x03);
    Serial.println("✅");
    
    // Configure SpO2
    Serial.print("[6] Configuring SpO2... ");
    i2c_write(MAX30102_ADDR, 0x0A, 0x27);
    Serial.println("✅");
    
    // Set LED current (24mA for foot)
    Serial.print("[7] Setting LED current to 24mA... ");
    i2c_write(MAX30102_ADDR, 0x0C, 0x60);   // RED 24mA
    i2c_write(MAX30102_ADDR, 0x0D, 0x60);   // IR 24mA
    Serial.println("✅");
    
    // Clear FIFO
    Serial.print("[8] Clearing FIFO... ");
    i2c_write(MAX30102_ADDR, 0x04, 0x00);
    i2c_write(MAX30102_ADDR, 0x05, 0x00);
    i2c_write(MAX30102_ADDR, 0x06, 0x00);
    Serial.println("✅");
    
    // Verify FIFO
    Serial.print("[9] Checking FIFO... ");
    uint8_t status = i2c_read8(MAX30102_ADDR, 0x00);
    Serial.printf("Status: 0x%02X\n", status);
    
    Serial.println("✅ MAX30102 READY!\n");
}

bool max_read_fifo(uint32_t &red, uint32_t &ir) {
    Wire.beginTransmission(MAX30102_ADDR);
    Wire.write(0x07);  // FIFO_DATA
    Wire.endTransmission(false);
    Wire.requestFrom(MAX30102_ADDR, (uint8_t)6);
    
    if (Wire.available() < 6) return false;
    
    // RED (3 bytes, 18-bit)
    red = Wire.read();
    red <<= 8;
    red |= Wire.read();
    red <<= 8;
    red |= Wire.read();
    red &= 0x3FFFF;
    
    // IR (3 bytes, 18-bit)
    ir = Wire.read();
    ir <<= 8;
    ir |= Wire.read();
    ir <<= 8;
    ir |= Wire.read();
    ir &= 0x3FFFF;
    
    return true;
}

void max30102_collect_samples() {
    static unsigned long last_read = 0;
    if (millis() - last_read < 5) return;  // Max 5ms between reads
    last_read = millis();
    
    uint8_t wr_ptr = i2c_read8(MAX30102_ADDR, 0x04) & 0x1F;
    uint8_t rd_ptr = i2c_read8(MAX30102_ADDR, 0x06) & 0x1F;
    int num_samples = (wr_ptr >= rd_ptr) ? (wr_ptr - rd_ptr) : (32 + wr_ptr - rd_ptr);
    
    if (num_samples == 0) return;
    if (num_samples > 16) num_samples = 16;
    
    for (int i = 0; i < num_samples; i++) {
        uint32_t r, ir;
        if (!max_read_fifo(r, ir)) break;
        
        red_buffer[fifo_index] = r;
        ir_buffer[fifo_index] = ir;
        fifo_index++;
        if (fifo_index >= HR_BUFFER_SIZE) {
            fifo_index = 0;
            fifo_full = true;
        }
    }
}

void max30102_compute(float &spo2, uint8_t &hr) {
    max30102_collect_samples();
    
    int count = fifo_full ? HR_BUFFER_SIZE : fifo_index;
    
    if (count < 30) {
        spo2 = 0;
        hr = 0;
        return;
    }
    
    // Calculate DC and AC
    uint32_t ir_sum = 0, red_sum = 0;
    uint32_t ir_min = 0xFFFFFFFF, ir_max = 0;
    uint32_t red_min = 0xFFFFFFFF, red_max = 0;
    
    for (int i = 0; i < count; i++) {
        ir_sum += ir_buffer[i];
        red_sum += red_buffer[i];
        if (ir_buffer[i] < ir_min) ir_min = ir_buffer[i];
        if (ir_buffer[i] > ir_max) ir_max = ir_buffer[i];
        if (red_buffer[i] < red_min) red_min = red_buffer[i];
        if (red_buffer[i] > red_max) red_max = red_buffer[i];
    }
    
    float ir_dc = (float)ir_sum / count;
    float red_dc = (float)red_sum / count;
    float ir_ac = (float)(ir_max - ir_min);
    float red_ac = (float)(red_max - red_min);
    
    // Check signal validity
    if (ir_ac < 200 || ir_dc < 800) {
        spo2 = 0;
        hr = 0;
        return;
    }
    
    float ratio = red_dc / ir_dc;
    if (ratio < 0.3 || ratio > 1.5) {
        spo2 = 0;
        hr = 0;
        return;
    }
    
    // Calculate SpO2
    if (ir_dc > 0 && red_dc > 0 && ir_ac > 0 && red_ac > 0) {
        float R = (red_ac / red_dc) / (ir_ac / ir_dc);
        spo2 = 105.0 - 20.0 * R;  // Foot-optimized formula
        spo2 = constrain(spo2, 70.0, 100.0);
    } else {
        spo2 = 0;
    }
    
    // Calculate HR
    int peaks = 0;
    bool above = false;
    float threshold = ir_dc + ir_ac * 0.2;  // Lowered for foot
    
    for (int i = 0; i < count; i++) {
        if (!above && ir_buffer[i] > threshold) {
            above = true;
            peaks++;
        } else if (above && ir_buffer[i] < ir_dc) {
            above = false;
        }
    }
    
    float seconds = (float)count / 25.0;  // 25Hz effective after 4x averaging
    if (seconds > 0 && peaks > 0) {
        hr = (uint8_t)((float)peaks / seconds * 60.0);
        if (hr < 40 || hr > 200) {
            hr = 0;
        }
    } else {
        hr = 0;
    }
    
    if (DEBUG_SENSORS) {
        Serial.printf("[MAX] SpO2:%.1f%% HR:%d\n", spo2, hr);
    }
}

float sensors_read_spo2() {
    float spo2 = 0;
    uint8_t hr = 0;
    max30102_compute(spo2, hr);
    return spo2;
}

uint8_t sensors_read_heart_rate() {
    float spo2 = 0;
    uint8_t hr = 0;
    max30102_compute(spo2, hr);
    return hr;
}

/* ============================================================
   MPU6050 FUNCTIONS (Step detection)
   ============================================================ */

void mpu6050_init() {
    Serial.println("\n=== MPU6050 INITIALIZATION ===");
    
    // Verify I2C
    Serial.print("[1] Checking I2C to 0x68... ");
    Wire.beginTransmission(MPU6050_ADDR);
    if (Wire.endTransmission() != 0) {
        Serial.println("❌ Failed");
        return;
    }
    Serial.println("✅");
    
    // Wake up and configure
    Serial.print("[2] Configuring MPU6050... ");
    i2c_write(MPU6050_ADDR, 0x6B, 0x00);  // Wake up
    i2c_write(MPU6050_ADDR, 0x1A, 0x06);  // Low-pass filter
    i2c_write(MPU6050_ADDR, 0x1B, 0x08);  // Gyro ±500°/s
    i2c_write(MPU6050_ADDR, 0x1C, 0x10);  // Accel ±8g
    Serial.println("✅");
    
    Serial.println("✅ MPU6050 READY!\n");
}

void mpu6050_read() {
    // Read accel X, Y, Z
    int16_t ax = i2c_read16(MPU6050_ADDR, 0x3B);
    int16_t ay = i2c_read16(MPU6050_ADDR, 0x3D);
    int16_t az = i2c_read16(MPU6050_ADDR, 0x3F);
    
    // Calculate magnitude
    float ax_g = ax / 4096.0f;
    float ay_g = ay / 4096.0f;
    float az_g = az / 4096.0f;
    float mag = sqrt(ax_g*ax_g + ay_g*ay_g + az_g*az_g);
    
    // Simple step detection: threshold crossing
    float threshold = 1.5;  // 1.5g threshold
    
    if (!step_high && mag > threshold) {
        step_high = true;
        unsigned long now = millis();
        if (now - last_step_time >= STEP_DEBOUNCE) {
            step_counter++;
            last_step_time = now;
        }
    } else if (step_high && mag < threshold) {
        step_high = false;
    }
    
    prev_accel_magnitude = mag;
}

uint16_t mpu6050_get_steps() {
    return step_counter;
}

float mpu6050_get_accel_magnitude() {
    return prev_accel_magnitude;
}

uint16_t sensors_get_step_count() {
    mpu6050_read();
    return mpu6050_get_steps();
}

/* ============================================================
   SENSOR INITIALIZATION
   ============================================================ */

void sensors_init() {
    Serial.println("\n=== SENSORS INITIALIZATION ===\n");
    
    // Initialize I2C
    Serial.print("Initializing I2C on SDA:");
    Serial.print(I2C_SDA_PIN);
    Serial.print(" SCL:");
    Serial.println(I2C_SCL_PIN);
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN, I2C_FREQ);
    delay(100);
    
    // Initialize sensors
    max30102_init();
    mpu6050_init();
    
    Serial.println("✅ ALL SENSORS INITIALIZED\n");
}

/* ============================================================
   COMPLETE SENSOR READING
   ============================================================ */

SensorData sensors_read_all() {
    SensorData data;
    data.timestamp = millis();
    
    // Read temperatures
    float temps[4];
    sensors_read_temperatures(temps);
    data.temp_heel = temps[0];
    data.temp_ball = temps[1];
    data.temp_arch = temps[2];
    data.temp_toe = temps[3];
    
    // Read pressures
    float pressures[4];
    sensors_read_pressures(pressures);
    data.press_heel = pressures[0];
    data.press_ball = pressures[1];
    data.press_arch = pressures[2];
    data.press_toe = pressures[3];
    
    // Read vital signs
    float spo2 = 0;
    uint8_t hr = 0;
    max30102_compute(spo2, hr);
    data.spo2 = spo2;
    data.heart_rate = hr;
    
    // Read step count
    mpu6050_read();
    data.step_count = mpu6050_get_steps();
    
    // Cache for later use
    last_sensor_data = data;
    
    if (DEBUG_SENSORS) {
        Serial.printf("[SENSOR] T:%.1f°C P:%.1fkPa SpO2:%.0f%% HR:%d Steps:%d\n",
                      data.temp_heel, data.press_heel, data.spo2, 
                      data.heart_rate, data.step_count);
    }
    
    return data;
}

