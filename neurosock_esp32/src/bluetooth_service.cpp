#include "bluetooth_service.h"

/* ============================================================
   GLOBAL BLUETOOTH SERVICE INSTANCE
   ============================================================ */

BluetoothService g_bluetooth_service;

/* ============================================================
   BLUETOOTH SERVICE CLASS IMPLEMENTATION
   ============================================================ */

BluetoothService::BluetoothService()
    : is_initialized(false), packets_sent(0), start_time_ms(0) {
}

bool BluetoothService::initialize() {
    Serial.println("\n[BT] Initializing Bluetooth Serial...");
    
    // Start BluetoothSerial with device name
    if (!SerialBT.begin(BLUETOOTH_NAME)) {
        Serial.println("[BT] ❌ Failed to initialize BluetoothSerial!");
        return false;
    }
    
    Serial.printf("[BT] ✅ BluetoothSerial started with name: %s\n", BLUETOOTH_NAME);
    Serial.println("[BT] Ready to receive connections\n");
    
    is_initialized = true;
    start_time_ms = millis();
    packets_sent = 0;
    
    return true;
}

void BluetoothService::build_packet(
    const SensorData& sensor_data,
    const MLResult& ml_result,
    uint8_t battery_level,
    SensorRiskPacket& packet) {
    
    // Encode temperatures (int8: (temp - 25) * 2)
    packet.temp_heel_enc = encode_temperature(sensor_data.temp_heel);
    packet.temp_ball_enc = encode_temperature(sensor_data.temp_ball);
    packet.temp_arch_enc = encode_temperature(sensor_data.temp_arch);
    packet.temp_toe_enc = encode_temperature(sensor_data.temp_toe);
    
    // Encode pressures (uint8: pressure / 0.3)
    packet.press_heel_enc = encode_pressure(sensor_data.press_heel);
    packet.press_ball_enc = encode_pressure(sensor_data.press_ball);
    packet.press_arch_enc = encode_pressure(sensor_data.press_arch);
    packet.press_toe_enc = encode_pressure(sensor_data.press_toe);
    
    // Direct values (uint8)
    packet.spo2 = (uint8_t)sensor_data.spo2;
    packet.heart_rate = sensor_data.heart_rate;
    
    // Encode step count (big-endian)
    encode_uint16_be(sensor_data.step_count, packet.step_count_h, packet.step_count_l);
    
    // ML Predictions
    packet.risk_probability = ml_result.get_risk_percent();
    packet.risk_level = ml_result.risk_level;
    packet.battery_level = battery_level;
    
    // Encode timestamp (big-endian)
    uint16_t ts_sec = (millis() - start_time_ms) / 1000;
    encode_uint16_be(ts_sec, packet.timestamp_h, packet.timestamp_l);
    
    if (DEBUG_BLUETOOTH) {
        Serial.printf("[BT] Packet built: T_H=%.1f°C -> %d, P_H=%.1f -> %d, "
                      "SpO2=%d%%, HR=%d, Risk=%d%%/%s\n",
                      sensor_data.temp_heel, packet.temp_heel_enc,
                      sensor_data.press_heel, packet.press_heel_enc,
                      packet.spo2, packet.heart_rate,
                      packet.risk_probability, ml_result.get_risk_name());
    }
}

bool BluetoothService::send_reading(
    const SensorData& sensor_data,
    const MLResult& ml_result,
    uint8_t battery_level) {
    
    if (!is_initialized) {
        if (DEBUG_BLUETOOTH) {
            Serial.println("[BT] ❌ Bluetooth not initialized");
        }
        return false;
    }
    
    // Build packet
    SensorRiskPacket packet;
    build_packet(sensor_data, ml_result, battery_level, packet);
    
    // Send packet
    return send_packet((uint8_t*)&packet, sizeof(SensorRiskPacket));
}

bool BluetoothService::send_packet(const uint8_t* data, uint8_t length) {
    if (!is_initialized || !data || length == 0) {
        return false;
    }
    
    // Send raw data
    size_t bytes_sent = SerialBT.write(data, length);
    
    if (bytes_sent == length) {
        packets_sent++;
        
        if (DEBUG_BLUETOOTH && (packets_sent % 10 == 0)) {
            Serial.printf("[BT] ✅ Packet #%lu sent (%u bytes)\n", 
                          packets_sent, length);
        }
        
        return true;
    } else {
        if (DEBUG_BLUETOOTH) {
            Serial.printf("[BT] ❌ Send failed: sent %d/%u bytes\n", 
                          (int)bytes_sent, length);
        }
        return false;
    }
}

bool BluetoothService::is_connected() const {
    return SerialBT.hasClient();
}

int BluetoothService::available() {
    return SerialBT.available();
}

int BluetoothService::read() {
    if (available() > 0) {
        return SerialBT.read();
    }
    return -1;
}

void BluetoothService::write(uint8_t data) {
    SerialBT.write(data);
}

void BluetoothService::shutdown() {
    if (is_initialized) {
        SerialBT.end();
        is_initialized = false;
        
        if (DEBUG_BLUETOOTH) {
            Serial.printf("[BT] Shutdown. Total packets sent: %lu\n", packets_sent);
        }
    }
}

BluetoothService::~BluetoothService() {
    shutdown();
}

/* ============================================================
   WRAPPER FUNCTIONS
   ============================================================ */

bool bt_init() {
    return g_bluetooth_service.initialize();
}

bool bt_send_reading(
    const SensorData& sensor_data,
    const MLResult& ml_result,
    uint8_t battery_level) {
    return g_bluetooth_service.send_reading(sensor_data, ml_result, battery_level);
}

bool bt_is_connected() {
    return g_bluetooth_service.is_connected();
}

void bt_shutdown() {
    g_bluetooth_service.shutdown();
}

