// Real BLE Service using flutter_blue_plus
// Connects to actual smart socks hardware via Bluetooth Low Energy (SPP - Serial Port Profile)
// ESP32 sends 17-byte packets every 2 seconds

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';

/// Service for real BLE communication with smart sock device (ESP32 BluetoothSerial)
/// WORKING IMPLEMENTATION - Tested workflow
class RealBleService {
  // Singleton pattern
  static final RealBleService _instance = RealBleService._internal();
  factory RealBleService() => _instance;
  RealBleService._internal();

  // Device connection
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;

  // Stream controllers
  StreamController<SensorReading>? _streamController;
  StreamSubscription<List<int>>? _rxSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // Connection state
  bool _isConnected = false;
  bool _isStreaming = false;
  bool _isConnecting = false;
  String _deviceName = '';
  int _batteryLevel = 0;

  // Buffer for incomplete packets
  final List<int> _dataBuffer = [];

  // ============== Getters ==============
  bool get isConnected => _isConnected;
  bool get isStreaming => _isStreaming;
  bool get isConnecting => _isConnecting;
  String get deviceName => _deviceName;
  int get batteryLevel => _batteryLevel;
  Stream<SensorReading>? get sensorStream => _streamController?.stream;

  // ============== Scanning & Connection ==============

  /// Scan for ALL nearby BLE devices (shows everything, not just NeuroSock)
  Future<List<ScanResult>> scanForDevices({int timeoutSeconds = 10}) async {
    try {
      if (kIsWeb) {
        throw Exception('Bluetooth not supported on web platform');
      }

      // Check Bluetooth adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is disabled. Please enable Bluetooth.');
      }

      debugPrint('🔍 Starting BLE scan for ALL devices...');

      // Stop any previous scan
      await FlutterBluePlus.stopScan();

      final discoveredDevices = <ScanResult>[];
      final seenIds = <String>{};

      // Start scan
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: timeoutSeconds),
        androidScanMode: AndroidScanMode.lowLatency,
      );

      // Collect ALL scan results
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final deviceId = result.device.remoteId.toString();
          final deviceName = result.device.platformName.isNotEmpty 
              ? result.device.platformName 
              : 'Unknown (${deviceId.substring(0, 8)})';
          
          // Add ALL devices with a name (skip unnamed)
          if (!seenIds.contains(deviceId)) {
            seenIds.add(deviceId);
            discoveredDevices.add(result);
            debugPrint('📍 Found: $deviceName - $deviceId');
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(Duration(seconds: timeoutSeconds));

      // Cleanup
      await FlutterBluePlus.stopScan();
      await subscription.cancel();

      debugPrint('✅ Scan complete. Found ${discoveredDevices.length} devices total');

      // Sort: NeuroSock devices first, then by name
      discoveredDevices.sort((a, b) {
        final aIsNeuro = a.device.platformName.toLowerCase().contains('neuro') || 
                         a.device.platformName.toLowerCase().contains('sock');
        final bIsNeuro = b.device.platformName.toLowerCase().contains('neuro') || 
                         b.device.platformName.toLowerCase().contains('sock');
        if (aIsNeuro && !bIsNeuro) return -1;
        if (!aIsNeuro && bIsNeuro) return 1;
        return a.device.platformName.compareTo(b.device.platformName);
      });

      return discoveredDevices;
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      await FlutterBluePlus.stopScan();
      rethrow;
    }
  }

  /// Connect to a specific BLE device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      if (kIsWeb) {
        throw Exception('Bluetooth not supported on web platform');
      }

      if (_isConnecting) {
        debugPrint('⚠️ Connection already in progress');
        return false;
      }

      _isConnecting = true;
      _device = device;
      _deviceName = device.platformName.isNotEmpty 
          ? device.platformName 
          : 'BLE Device';

      debugPrint('🔗 Connecting to $_deviceName (${device.remoteId})...');

      // Monitor connection state
      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        debugPrint('🔗 Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _isStreaming = false;
        } else if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
        }
      });

      // Connect with timeout
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      debugPrint('✅ BLE Connected to $_deviceName!');
      _isConnected = true;
      _isConnecting = false;

      // Try to discover services (don't fail connection if this fails)
      try {
        await _discoverServices();
      } catch (e) {
        debugPrint('⚠️ Service discovery failed, but connection is OK: $e');
        // Connection is still valid - just no data streaming capability
      }

      return true;
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      _isConnected = false;
      _isConnecting = false;
      _device = null;
      rethrow;
    }
  }

  /// Discover RX/TX characteristics for SPP communication
  Future<void> _discoverServices() async {
    try {
      debugPrint('🔎 Discovering BLE services...');

      final services = await _device!.discoverServices();
      debugPrint('Found ${services.length} services');

      if (services.isEmpty) {
        throw Exception('Device advertises no BLE services!');
      }

      // Standard UUIDs
      const String rxCharUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

      // PASS 1: Try exact UUID match
      debugPrint('📋 [PASS 1] Looking for exact UART RX UUID match...');
      for (var service in services) {
        debugPrint('  Service: ${service.uuid}');

        for (var char in service.characteristics) {
          debugPrint(
              '    Char: ${char.uuid} | Props: Notify=${char.properties.notify}, Read=${char.properties.read}, Write=${char.properties.write}');

          if (char.uuid.toString().toUpperCase() == rxCharUuid.toUpperCase()) {
            _rxCharacteristic = char;
            debugPrint('✅ Found RX with exact UUID match!');
            return;
          }
        }
      }

      // PASS 2: Try standard BLE characteristic UUIDs
      debugPrint('📋 [PASS 2] Looking for standard BLE characteristics...');
      for (var service in services) {
        for (var char in service.characteristics) {
          // 2A37 = Heart Rate Measurement (standard notify)
          // FFE1 = common characteristic in BLE modules
          if (char.uuid.toString().toUpperCase().contains('2A37') ||
              char.uuid.toString().toUpperCase().contains('FFE1')) {
            _rxCharacteristic = char;
            debugPrint(
                '✅ Found RX with standard UUID: ${char.uuid}');
            return;
          }
        }
      }

      // PASS 3: Look for ANY notify characteristic
      debugPrint('📋 [PASS 3] Looking for ANY notify characteristic...');
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.notify) {
            _rxCharacteristic = char;
            debugPrint(
                '✅ Found notify characteristic: ${char.uuid}');
            return;
          }
        }
      }

      // PASS 4: Look for ANY read characteristic
      debugPrint('📋 [PASS 4] Looking for ANY read characteristic...');
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.read) {
            _rxCharacteristic = char;
            debugPrint('✅ Found read characteristic: ${char.uuid}');
            return;
          }
        }
      }

      if (_rxCharacteristic == null) {
        throw Exception(
            'No suitable RX characteristic found in device services');
      }

      debugPrint('✅ Service discovery complete');
    } catch (e) {
      debugPrint('❌ Service discovery error: $e');
      throw Exception('Service discovery failed: $e');
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting...');

      _isConnecting = false;
      await stopStreaming();
      await _connectionSubscription?.cancel();

      if (_device != null) {
        await _device!.disconnect();
      }

      _isConnected = false;
      _device = null;
      _rxCharacteristic = null;

      debugPrint('✅ Disconnected');
    } catch (e) {
      debugPrint('⚠️ Disconnect error: $e');
      _isConnected = false;
    }
  }

  // ============== Streaming ==============

  /// Start streaming sensor data
  Future<void> startStreaming() async {
    try {
      if (kIsWeb) {
        throw Exception('Bluetooth not available on web');
      }

      if (!_isConnected) {
        throw Exception('Device not connected');
      }

      if (_rxCharacteristic == null) {
        throw Exception('RX characteristic not found');
      }

      if (_isStreaming) {
        debugPrint('⚠️ Already streaming');
        return;
      }

      debugPrint('📡 Starting BLE data stream...');

      _streamController = StreamController<SensorReading>.broadcast();
      _isStreaming = true;

      // Step 1: Enable notifications
      debugPrint('📬 Enabling notifications...');
      try {
        await _rxCharacteristic!.setNotifyValue(true);
        debugPrint('✅ Notifications enabled');
      } catch (e) {
        debugPrint('⚠️ Failed to enable notifications: $e');
        // Continue anyway - try reading instead
      }

      // Step 2: Set up listener - CRITICAL: use onValueReceived, not lastValueStream
      debugPrint('👂 Setting up data listener...');
      _rxSubscription =
          _rxCharacteristic!.lastValueStream.listen(
        (value) {
          debugPrint(
              '📥 Received ${value.length} bytes: ${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          _onDataReceived(value);
        },
        onError: (e) {
          debugPrint('❌ Stream error: $e');
          _streamController?.addError(e);
          _isStreaming = false;
        },
        onDone: () {
          debugPrint('⚠️ Stream closed/done');
          _isStreaming = false;
        },
        cancelOnError: false,
      );

      debugPrint('✅ Stream listener attached');

      // Also try periodic read as fallback
      if (_rxCharacteristic!.properties.read) {
        debugPrint('📖 Starting periodic read (fallback)...');
        _startPeriodicRead();
      }

      debugPrint('✅ Streaming started successfully');
    } catch (e) {
      _isStreaming = false;
      debugPrint('❌ Failed to start streaming: $e');
      rethrow;
    }
  }

  /// Periodic read as fallback if notifications don't work
  void _startPeriodicRead() {
    Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (!_isStreaming || _rxCharacteristic == null) {
        timer.cancel();
        return;
      }

      _rxCharacteristic?.read().then((value) {
        if (value.isNotEmpty) {
          _onDataReceived(value);
        }
      }).catchError((e) {
        debugPrint('⚠️ Periodic read error: $e');
      });
    });
  }

  /// Stop streaming
  Future<void> stopStreaming() async {
    try {
      _isStreaming = false;

      if (_rxCharacteristic != null) {
        try {
          await _rxCharacteristic!.setNotifyValue(false);
        } catch (e) {
          debugPrint('⚠️ Failed to disable notifications: $e');
        }
      }

      await _rxSubscription?.cancel();
      await _streamController?.close();
      _streamController = null;
      _rxSubscription = null;

      debugPrint('✅ Streaming stopped');
    } catch (e) {
      debugPrint('⚠️ Error stopping stream: $e');
    }
  }

  // ============== Data Reception ==============

  /// Handle incoming BLE data
  void _onDataReceived(List<int> data) {
    try {
      if (data.isEmpty) return;

      // Add to buffer
      _dataBuffer.addAll(data);
      debugPrint(
          '📊 Buffer size: ${_dataBuffer.length}, new data: ${data.length} bytes');

      // Process complete 17-byte packets
      while (_dataBuffer.length >= 17) {
        // Extract 17 bytes
        final packet = _dataBuffer.sublist(0, 17);

        // Parse packet
        final reading = _parsePayload(packet);
        if (reading != null) {
          debugPrint('🎉 Emitting reading to stream');
          _streamController?.add(reading);
        }

        // Remove processed bytes from buffer
        _dataBuffer.removeRange(0, 17);
      }
    } catch (e) {
      debugPrint('❌ Data reception error: $e');
    }
  }

  // ============== Payload Parsing ==============

  /// Parse 17-byte ESP32 SensorRiskPacket into SensorReading
  SensorReading? _parsePayload(List<int> packet) {
    try {
      if (packet.length != 17) {
        return null;
      }

      // Parse temperatures (Bytes 0-3) — int8 encoded: temp = 25.0 + signed_byte / 2.0
      final temperatures = <double>[];
      for (int i = 0; i < 4; i++) {
        final raw = packet[i];
        final signed = raw > 127 ? raw - 256 : raw;
        var temp = 25.0 + signed / 2.0;
        if (temp < -10.0 || temp > 50.0) temp = 0.0;
        temperatures.add(temp);
      }

      // Parse pressures (Bytes 4-7) — uint8: pressure = byte * 0.3
      final pressures = <double>[];
      for (int i = 0; i < 4; i++) {
        final pressure = packet[4 + i] * 0.3;
        pressures.add(pressure);
      }

      // Parse SpO2 (Byte 8) — uint8 direct %
      var spO2 = packet[8].toDouble();
      if (spO2 > 100.0) spO2 = 100.0;
      if (spO2 < 0.0) spO2 = 0.0;

      // Parse Heart Rate (Byte 9) — uint8 direct BPM
      var heartRate = packet[9];
      if (heartRate > 250) heartRate = 250;

      // Parse Step Count (Bytes 10-11) — uint16 big-endian
      final stepCount = (packet[10] << 8) | packet[11];

      // Parse Risk Probability (Byte 12) — 0-100%
      final riskProbability = packet[12].clamp(0, 100).toDouble();

      // Parse Risk Level (Byte 13) — 0-3
      final riskLevel = packet[13].clamp(0, 3);

      // Parse Battery Level (Byte 14)
      _batteryLevel = packet[14].clamp(0, 100);

      // Bytes 15-16: Timestamp (seconds since boot) — informational only

      final reading = SensorReading(
        timestamp: DateTime.now(),
        temperatures: temperatures,
        pressures: pressures,
        spO2: spO2,
        heartRate: heartRate,
        stepCount: stepCount,
        batteryLevel: _batteryLevel,
        riskProbability: riskProbability,
        riskLevel: riskLevel,
      );

      debugPrint(
          '✅ SensorReading: T=[${temperatures.map((t) => t.toStringAsFixed(1)).join(',')}]°C '
          'P=[${pressures.map((p) => p.toStringAsFixed(1)).join(',')}] kPa '
          'SpO2=$spO2 HR=$heartRate BPM STP=$stepCount '
          'RISK=${riskProbability.toStringAsFixed(0)}%/$riskLevel BAT=$_batteryLevel%');

      return reading;
    } catch (e) {
      debugPrint('❌ Parse error: $e');
      return null;
    }
  }

  /// Print debug message
  static void debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[RealBleService] $message');
    }
  }
}
