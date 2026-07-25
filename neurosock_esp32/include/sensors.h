#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>
#include <Wire.h>
#include "config.h"

/* ============================================================
   SENSOR DATA STRUCTURE (11 raw values)
   ============================================================ */

struct SensorData {
    // Temperature (4 values)
    float temp_heel;
    float temp_ball;
    float temp_arch;
    float temp_toe;
    
    // Pressure (4 values)
    float press_heel;
    float press_ball;
    float press_arch;
    float press_toe;
    
    // Vital Signs (2 values)
    float spo2;           // Percentage
    uint8_t heart_rate;   // BPM
    
    // Activity
    uint16_t step_count;  // Total steps
    
    // Timestamp
    uint32_t timestamp;   // milliseconds
};

/* ============================================================
   SENSOR INITIALIZATION
   ============================================================ */

/**
 * Initialize all sensors: I2C bus, MAX30102, MPU6050, ADC
 * Must be called in setup()
 * Returns: true if successful, false if error
 */
bool sensors_init();

/* ============================================================
   SENSOR READING FUNCTIONS
   ============================================================ */

/**
 * Read temperature from NTC thermistor on GPIO36
 * Returns: Temperature in Celsius
 * Note: NTC is on GPIO36 (ADC1_CH0), other zones derived mathematically
 */
float sensors_read_temperature_heel();

/**
 * Read all 4 temperature zones
 * Heel: physical NTC reading
 * Ball, Arch, Toe: derived with thermal gradients
 */
void sensors_read_temperatures(float* temps);

/**
 * Read all 4 pressure zones from ADC
 * Returns: Array of 4 pressure values in kPa
 */
void sensors_read_pressures(float* pressures);

/**
 * Read SpO2 percentage from MAX30102
 * Returns: SpO2 value (70-100%), 0 if invalid
 */
float sensors_read_spo2();

/**
 * Read Heart Rate from MAX30102
 * Returns: HR in BPM, 0 if invalid
 */
uint8_t sensors_read_heart_rate();

/**
 * Get current step count from step detector
 * Returns: Total accumulated steps
 */
uint16_t sensors_get_step_count();

/**
 * Read all sensors at once
 * Returns: SensorData struct with all 11 raw values + timestamp
 */
SensorData sensors_read_all();

/* ============================================================
   I2C HELPER FUNCTIONS
   ============================================================ */

/**
 * Write 8-bit register via I2C
 */
void i2c_write(uint8_t addr, uint8_t reg, uint8_t val);

/**
 * Read 8-bit value from I2C register
 */
uint8_t i2c_read8(uint8_t addr, uint8_t reg);

/**
 * Read 16-bit value from I2C register (big-endian)
 */
int16_t i2c_read16(uint8_t addr, uint8_t reg);

/* ============================================================
   MAX30102 (SpO2/HR SENSOR) FUNCTIONS
   ============================================================ */

/**
 * Initialize MAX30102 sensor
 * Sets up LED current for foot placement, enables SpO2 mode
 */
void max30102_init();

/**
 * Collect samples from MAX30102 FIFO
 * Call frequently to keep FIFO from overflowing
 */
void max30102_collect_samples();

/**
 * Calculate SpO2 and Heart Rate from buffered samples
 * Returns: SpO2 percentage and HR in BPM
 */
void max30102_compute(float &spo2, uint8_t &hr);

/* ============================================================
   MPU6050 (ACCELEROMETER/GYRO) FUNCTIONS
   ============================================================ */

/**
 * Initialize MPU6050 sensor
 */
void mpu6050_init();

/**
 * Read accelerometer and gyroscope data
 * Used for step detection algorithm
 */
void mpu6050_read();

/**
 * Get current step count from accumulator
 */
uint16_t mpu6050_get_steps();

/**
 * Get acceleration magnitude (for step detection threshold)
 */
float mpu6050_get_accel_magnitude();

/* ============================================================
   ADC FUNCTIONS (TEMPERATURE/PRESSURE)
   ============================================================ */

/**
 * Read ADC with averaging (16 samples)
 * Noise reduction via hardware averaging
 */
float adc_read_average(int pin);

/**
 * Read NTC thermistor temperature
 * Uses Steinhart-Hart equation
 * Returns: Temperature in Celsius, 0.0 if sensor error
 */
float adc_read_thermistor(int pin);

/**
 * Read pressure sensor ADC value
 * Converts ADC count to pressure in kPa
 */
float adc_read_pressure(int pin);

#endif  // SENSORS_H

