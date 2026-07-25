# ESP32 BLE Data Format - Smart Socks (Edge ML)

This document describes the **17-byte SensorRiskPacket** sent from ESP32 to the mobile app via Classic Bluetooth (SPP).
The ESP32 performs on-device ML inference and includes risk predictions in every packet.

---

## Packet Structure

### **Total: 17 Bytes**

```
Byte  Field              Type    Description
----  -----------------  ------  ----------------------------------
 0    Temperature Heel   int8    Encoded: (temp - 25) * 2
 1    Temperature Ball   int8    Encoded: (temp - 25) * 2
 2    Temperature Arch   int8    Encoded: (temp - 25) * 2
 3    Temperature Toe    int8    Encoded: (temp - 25) * 2
 4    Pressure Heel      uint8   Encoded: pressure / 0.3
 5    Pressure Ball      uint8   Encoded: pressure / 0.3
 6    Pressure Arch      uint8   Encoded: pressure / 0.3
 7    Pressure Toe       uint8   Encoded: pressure / 0.3
 8    SpO2               uint8   Direct percentage (0-100%)
 9    Heart Rate         uint8   Direct BPM (0-250)
10    Step Count High    uint8   uint16 big-endian high byte
11    Step Count Low     uint8   uint16 big-endian low byte
12    Risk Probability   uint8   ML prediction (0-100%)
13    Risk Level         uint8   ML risk level (0-3)
14    Battery Level      uint8   Battery percentage (0-100%)
15    Timestamp High     uint8   uint16 big-endian high byte
16    Timestamp Low      uint8   uint16 big-endian low byte
```

---

## Data Conversion

### Temperatures (Bytes 0-3) — int8 encoded

```
Encode (ESP32):  int8_t byte = (temp - 25.0) * 2
Decode (App):    temp = 25.0 + signed_byte / 2.0
```

- Range: -10°C to 50°C (valid), outside = sensor error
- Example: 32.5°C → `(32.5 - 25) * 2 = 15` → decode: `25 + 15/2 = 32.5°C`

### Pressures (Bytes 4-7) — uint8 encoded

```
Encode (ESP32):  uint8_t byte = pressure / 0.3
Decode (App):    pressure = byte * 0.3
```

- Range: 0 to 76.5 kPa
- Example: 45 kPa → `45 / 0.3 = 150` → decode: `150 * 0.3 = 45 kPa`

### SpO2 (Byte 8) — direct uint8

```
Decode: spO2 = byte (0-100%)
```

### Heart Rate (Byte 9) — direct uint8

```
Decode: heartRate = byte (0-250 BPM)
```

### Step Count (Bytes 10-11) — uint16 big-endian

```
Decode: steps = (byte10 << 8) | byte11
```

### Risk Probability (Byte 12) — ESP32 ML prediction

```
Decode: riskProbability = byte (0-100%)
```

- 0 = no risk, 100 = maximum risk
- Computed on ESP32 using TFLite model inference

### Risk Level (Byte 13) — ESP32 ML classification

```
0 = Low
1 = Moderate
2 = High
3 = Critical
```

### Battery Level (Byte 14)

```
Decode: battery = byte (0-100%)
```

### Timestamp (Bytes 15-16) — uint16 big-endian

```
Decode: seconds = (byte15 << 8) | byte16
```

- Seconds since ESP32 boot, informational only
- App uses `DateTime.now()` for actual timestamps

---

## Checklist

- [x] 4 temperature sensors (int8 encoded)
- [x] 4 pressure sensors (uint8 encoded)
- [x] SpO2 (single byte)
- [x] Heart Rate (single byte)
- [x] Step Count (uint16 BE)
- [x] Risk Probability from Edge ML (uint8)
- [x] Risk Level from Edge ML (uint8)
- [x] Battery level (uint8)
- [x] Timestamp (uint16 BE)
- [x] Pack into 17-byte SensorRiskPacket
- [x] Send via BluetoothSerial every 2 seconds
- [ ] Send every 2 seconds (or your preferred interval)

---

## 🔧 BLE Setup on ESP32

### **Service UUID:**
```
Different UUIDs can be used, but ensure they're consistent
Example: 180D (Heart Rate Service - standard)
```

### **Characteristic UUID for Data:**
```
Example: 2A37 (Heart Rate Measurement - standard)
Or custom: 550e8400-e29b-41d4-a716-446655440000
```

---

## 📱 Verification

After implementing on ESP32:
1. **Turn on Mock mode OFF** in mobile app settings
2. Connect to "NeuroSock" device
3. Open app and start streaming
4. Check **browser console** for received data
5. Check **Firestore** for stored readings

You should see in console:
```
📊 Received reading - Temp: [32.5, 33.2, 31.8, 32.9], Pressure: [45.0, 50.0, 20.0, 40.0]
💾 Saving sensor reading...
✅ Sensor reading saved successfully
```

---

## 🎯 Key Points for Your Friend

✅ **16 bytes total** - No more, no less  
✅ **Big Endian** for multi-byte values (temperatures use formula)  
✅ **Send every 2 seconds** - Or adjust period as needed  
✅ **BLE Notify** - Use characteristic notifications  
✅ **Temperature formula** - Don't forget the (x - 128) / 2 conversion!  
✅ **Pressure formula** - Keep the × 0.3 scaling  

Good luck! 🚀
