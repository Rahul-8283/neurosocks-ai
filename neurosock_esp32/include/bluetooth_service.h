#ifndef BLUETOOTH_SERVICE_H
#define BLUETOOTH_SERVICE_H

#include <Arduino.h>
#include <BluetoothSerial.h>
#include "config.h"
#include "sensors.h"
#include "ml_inference.h"

/* ============================================================
   17-BYTE BLE PACKET STRUCTURE
   ============================================================ */

#pragma pack(1)  // Force byte-aligned structure
struct SensorRiskPacket {
    // Byte 0-3: Temperatures (int8 encoded)
    int8_t temp_heel_enc;      // Byte 0
    int8_t temp_ball_enc;      // Byte 1
    int8_t temp_arch_enc;      // Byte 2
    int8_t temp_toe_enc;       // Byte 3
    
    // Byte 4-7: Pressures (uint8 encoded)
    uint8_t press_heel_enc;    // Byte 4
    uint8_t press_ball_enc;    // Byte 5
    uint8_t press_arch_enc;    // Byte 6
    uint8_t press_toe_enc;     // Byte 7
    
    // Byte 8: SpO2
    uint8_t spo2;              // Byte 8
    
    // Byte 9: Heart Rate
    uint8_t heart_rate;        // Byte 9
    
    // Byte 10-11: Step Count (big-endian uint16)
    uint8_t step_count_h;      // Byte 10 (high)
    uint8_t step_count_l;      // Byte 11 (low)
    
    // ML PREDICTIONS
    // Byte 12: Risk Probability (0-100)
    uint8_t risk_probability;  // Byte 12
    
    // Byte 13: Risk Level (0-3)
    uint8_t risk_level;        // Byte 13
    
    // Byte 14: Battery Level (0-100)
    uint8_t battery_level;     // Byte 14
    
    // Byte 15-16: Timestamp (big-endian uint16, seconds)
    uint8_t timestamp_h;       // Byte 15 (high)
    uint8_t timestamp_l;       // Byte 16 (low)
};
#pragma pack()  // End byte-aligned structure

/* ============================================================
   ENCODING/DECODING FUNCTIONS
   ============================================================ */

/**
 * Encode temperature for BLE packet
 * Formula: (temp - 25) * 2
 * Example: 30°C → (30-25)*2 = 10
 */
static inline int8_t encode_temperature(float temp) {
    return (int8_t)((temp - TEMP_ENCODE_OFFSET) * TEMP_ENCODE_SCALE);
}

/**
 * Encode pressure for BLE packet
 * Formula: pressure / 0.3
 * Example: 50 kPa → 50/0.3 = 166
 */
static inline uint8_t encode_pressure(float pressure) {
    return (uint8_t)(pressure / PRESSURE_ENCODE_SCALE);
}

/**
 * Encode uint16 as big-endian bytes
 */
static inline void encode_uint16_be(uint16_t value, uint8_t& high, uint8_t& low) {
    high = (value >> 8) & 0xFF;
    low = value & 0xFF;
}

/**
 * Decode uint16 from big-endian bytes
 */
static inline uint16_t decode_uint16_be(uint8_t high, uint8_t low) {
    return ((uint16_t)high << 8) | (uint16_t)low;
}

/* ============================================================
   BLUETOOTH SERVICE CLASS
   ============================================================ */

class BluetoothService {
private:
    BluetoothSerial SerialBT;
    bool is_initialized;
    uint32_t packets_sent;
    uint32_t start_time_ms;
    
    /**
     * Build 17-byte packet from sensor and ML data
     */
    void build_packet(
        const SensorData& sensor_data,
        const MLResult& ml_result,
        uint8_t battery_level,
        SensorRiskPacket& packet
    );
    
public:
    /**
     * Constructor
     */
    BluetoothService();
    
    /**
     * Initialize Bluetooth Serial
     * Device name: "NeuroSock"
     * Baud rate: 115200
     * Returns: true if successful
     */
    bool initialize();
    
    /**
     * Send sensor reading + ML prediction
     * Builds 17-byte packet and sends via BLE
     * Returns: true if sent successfully
     */
    bool send_reading(
        const SensorData& sensor_data,
        const MLResult& ml_result,
        uint8_t battery_level
    );
    
    /**
     * Send raw packet
     * For debugging/testing
     */
    bool send_packet(const uint8_t* data, uint8_t length);
    
    /**
     * Check if Bluetooth is connected
     */
    bool is_connected() const;
    
    /**
     * Get number of packets sent since startup
     */
    uint32_t get_packets_sent() const { return packets_sent; }
    
    /**
     * Check if data is available on BLE (for commands)
     */
    int available();
    
    /**
     * Read data from BLE
     */
    int read();
    
    /**
     * Write data to BLE
     */
    void write(uint8_t data);
    
    /**
     * Shutdown Bluetooth
     */
    void shutdown();
    
    /**
     * Destructor
     */
    ~BluetoothService();
};

/* ============================================================
   GLOBAL BLUETOOTH SERVICE INSTANCE
   ============================================================ */

extern BluetoothService g_bluetooth_service;

/**
 * Initialize Bluetooth (wrapper function)
 */
bool bt_init();

/**
 * Send reading via Bluetooth (wrapper function)
 */
bool bt_send_reading(
    const SensorData& sensor_data,
    const MLResult& ml_result,
    uint8_t battery_level
);

/**
 * Check Bluetooth connection status (wrapper function)
 */
bool bt_is_connected();

/**
 * Shutdown Bluetooth (wrapper function)
 */
void bt_shutdown();

#endif  // BLUETOOTH_SERVICE_H

