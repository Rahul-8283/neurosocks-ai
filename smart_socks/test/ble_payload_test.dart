// Test file to verify ESP32 17-byte SensorRiskPacket decoding
// Run this to ensure the parsing logic matches ESP32 bluetooth_service.h

void main() {
  // Example 17-byte packet from ESP32 SensorRiskPacket:
  // Temps(int8) | Pressures(uint8) | SpO2 | HR | Steps(u16) | RiskProb | RiskLvl | Batt | Timestamp(u16)

  final examplePacket = [
    0x0F, 0x10, 0x0D, 0x10, // Temperatures (int8 encoded: (temp-25)*2)
    0x96, 0xA7, 0x42, 0x85, // Pressures (uint8: pressure/0.3)
    0x62,                   // SpO2 (98%)
    0x48,                   // Heart Rate (72 BPM)
    0x04, 0xE2,             // Step Count (0x04E2 = 1250 steps)
    0x19,                   // Risk Probability (25%)
    0x01,                   // Risk Level (1 = Moderate)
    0x55,                   // Battery Level (85%)
    0x01, 0x2C,             // Timestamp (300 seconds)
  ];

  print('=== NeuroSocks ESP32 17-Byte Packet Decoder Test ===\n');

  // Parse temperatures (int8 encoded)
  print('Temperature Parsing (int8 encoded):');
  for (int i = 0; i < 4; i++) {
    final rawByte = examplePacket[i];
    final signed = rawByte > 127 ? rawByte - 256 : rawByte;
    final temp = 25.0 + signed / 2.0;
    print('  Zone $i (Byte $i = 0x${rawByte.toRadixString(16).toUpperCase().padLeft(2, '0')}, signed=$signed): ${temp.toStringAsFixed(1)}°C');
  }
  print('  Formula: temp = 25.0 + signed_byte / 2.0\n');

  // Parse pressures
  print('Pressure Parsing:');
  for (int i = 0; i < 4; i++) {
    final pressureByte = examplePacket[4 + i];
    final pressure = pressureByte * 0.3;
    print('  Zone $i (Byte ${4 + i} = 0x${pressureByte.toRadixString(16).toUpperCase().padLeft(2, '0')}): ${pressure.toStringAsFixed(1)} kPa');
  }
  print('  Formula: pressure = byte * 0.3\n');

  // Parse SpO2
  print('SpO2 Parsing:');
  final spO2 = examplePacket[8];
  print('  Byte 8: $spO2%');
  print('  Direct uint8 value\n');

  // Parse Heart Rate
  print('Heart Rate Parsing:');
  final heartRate = examplePacket[9];
  print('  Byte 9: $heartRate BPM');
  print('  Direct uint8 value\n');

  // Parse Step Count
  print('Step Count Parsing:');
  final stepCount = (examplePacket[10] << 8) | examplePacket[11];
  print('  Bytes 10-11: 0x${examplePacket[10].toRadixString(16).toUpperCase().padLeft(2, '0')} 0x${examplePacket[11].toRadixString(16).toUpperCase().padLeft(2, '0')}');
  print('  Decoded: $stepCount steps\n');

  // Parse Risk Probability
  print('Risk Probability (ESP32 Edge ML):');
  final riskProb = examplePacket[12];
  print('  Byte 12: $riskProb%');
  print('  0-100% from TFLite inference on ESP32\n');

  // Parse Risk Level
  print('Risk Level (ESP32 Edge ML):');
  final riskLevel = examplePacket[13];
  final riskNames = ['Low', 'Moderate', 'High', 'Critical'];
  print('  Byte 13: $riskLevel = ${riskNames[riskLevel.clamp(0, 3)]}');
  print('  0=Low, 1=Moderate, 2=High, 3=Critical\n');

  // Parse Battery
  print('Battery Level:');
  final battery = examplePacket[14];
  print('  Byte 14: $battery%\n');

  // Parse Timestamp
  print('Timestamp:');
  final timestamp = (examplePacket[15] << 8) | examplePacket[16];
  print('  Bytes 15-16: $timestamp seconds since boot\n');

  print('=== Test Complete ===');
  print('Total packet size: ${examplePacket.length} bytes');
}
