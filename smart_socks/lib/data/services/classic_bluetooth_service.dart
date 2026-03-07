// Classic Bluetooth (SPP) Service for ESP32 BluetoothSerial
// Uses native Android platform channel — NO third-party package needed.
// The ESP32 sends 17-byte binary packets every 2 seconds via BluetoothSerial.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/sensor_reading.dart';

/// Lightweight model for a Classic Bluetooth device (name + MAC address)
class ClassicBtDevice {
  final String name;
  final String address;
  ClassicBtDevice({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

/// Service for Classic Bluetooth (SPP) communication with ESP32.
/// Communicates with native Kotlin via MethodChannel + EventChannel.
class ClassicBluetoothService {
  // Singleton
  static final ClassicBluetoothService _instance =
      ClassicBluetoothService._internal();
  factory ClassicBluetoothService() => _instance;
  ClassicBluetoothService._internal();

  // Platform channels — must match MainActivity.kt exactly
  static const _methodChannel = MethodChannel('com.neurosocks.app/classic_bt');
  static const _dataEventChannel =
      EventChannel('com.neurosocks.app/classic_bt_data');
  static const _discoveryEventChannel =
      EventChannel('com.neurosocks.app/classic_bt_discovery');

  // Parsed sensor stream exposed to the provider
  StreamController<SensorReading>? _sensorController;
  StreamSubscription? _rawDataSubscription;

  // State
  bool _isConnected = false;
  bool _isConnecting = false;
  String _deviceName = '';
  int _batteryLevel = 0;

  // Buffer for assembling 17-byte packets
  final List<int> _buffer = [];

  // ============== Getters ==============
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get deviceName => _deviceName;
  int get batteryLevel => _batteryLevel;
  Stream<SensorReading>? get sensorStream => _sensorController?.stream;

  // ============== Bluetooth State ==============

  /// Check if Bluetooth adapter is enabled
  Future<bool> isEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (e) {
      _log('isEnabled error: $e');
      return false;
    }
  }

  /// Check if Location Services (GPS) are enabled.
  /// Classic BT discovery requires this to be ON on Android.
  Future<bool> isLocationEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isLocationEnabled') ?? false;
    } catch (e) {
      _log('isLocationEnabled error: $e');
      return true; // Assume on if check fails
    }
  }

  /// Open system Location Settings
  Future<void> openLocationSettings() async {
    try {
      await _methodChannel.invokeMethod('openLocationSettings');
    } catch (e) {
      _log('openLocationSettings error: $e');
    }
  }

  // ============== Discovery ==============

  /// Get list of paired/bonded devices
  Future<List<ClassicBtDevice>> getBondedDevices() async {
    try {
      final result = await _methodChannel.invokeMethod('getBondedDevices');
      if (result == null) return [];
      final rawList = result as List;
      _log('getBondedDevices raw: ${rawList.length} items');
      return rawList.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return ClassicBtDevice(
          name: m['name']?.toString() ?? '',
          address: m['address']?.toString() ?? '',
        );
      }).toList();
    } catch (e) {
      _log('getBondedDevices error: $e');
      return [];
    }
  }

  // Active discovery stream subscription (so we can cancel before re-listening)
  StreamSubscription? _discoveryRawSub;
  StreamController<ClassicBtDevice>? _discoveryController;

  /// Start scanning for nearby Classic Bluetooth devices.
  /// Returns a broadcast stream of discovered [ClassicBtDevice] objects.
  /// The native EventChannel starts discovery when Dart subscribes (onListen).
  /// If location is off, the stream will emit an error with code 'LOCATION_OFF'.
  Future<Stream<ClassicBtDevice>> startDiscovery() async {
    // Clean up any previous discovery stream properly
    await _cleanupDiscovery();

    _discoveryController = StreamController<ClassicBtDevice>.broadcast();
    _log('Discovery: subscribing to EventChannel...');

    try {
      // Subscribe to the native EventChannel.
      // Native side automatically starts BT discovery in onListen.
      _discoveryRawSub =
          _discoveryEventChannel.receiveBroadcastStream().listen(
        (event) {
          try {
            final m = Map<String, dynamic>.from(event as Map);
            final device = ClassicBtDevice(
              name: m['name']?.toString() ?? '',
              address: m['address']?.toString() ?? '',
            );
            _log('Discovery: found ${device.name} (${device.address})');
            if (_discoveryController != null &&
                !_discoveryController!.isClosed) {
              _discoveryController!.add(device);
            }
          } catch (e) {
            _log('Discovery: error parsing event: $e (raw: $event)');
          }
        },
        onError: (e) {
          _log('Discovery stream error: $e');
          if (_discoveryController != null &&
              !_discoveryController!.isClosed) {
            _discoveryController!.addError(e);
            _discoveryController!.close();
          }
        },
        onDone: () {
          _log('Discovery stream done (native finished)');
          if (_discoveryController != null &&
              !_discoveryController!.isClosed) {
            _discoveryController!.close();
          }
        },
      );
      _log('Discovery: EventChannel subscription active');
    } catch (e) {
      _log('Discovery: FAILED to subscribe to EventChannel: $e');
      if (_discoveryController != null && !_discoveryController!.isClosed) {
        _discoveryController!.addError(e);
        _discoveryController!.close();
      }
      // Don't rethrow — return the stream so the UI can handle it
    }

    return _discoveryController!.stream;
  }

  /// Clean up discovery streams safely
  Future<void> _cleanupDiscovery() async {
    if (_discoveryRawSub != null) {
      await _discoveryRawSub!.cancel();
      _discoveryRawSub = null;
      _log('Discovery: cancelled previous raw subscription');
    }
    if (_discoveryController != null) {
      if (!_discoveryController!.isClosed) {
        _discoveryController!.close();
      }
      _discoveryController = null;
    }
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    await _cleanupDiscovery();
    try {
      await _methodChannel.invokeMethod('stopDiscovery');
      _log('stopDiscovery: native stopped');
    } catch (e) {
      _log('stopDiscovery error: $e');
    }
  }

  // ============== Connection ==============

  /// Connect to an ESP32 Classic BT device by address
  Future<bool> connect(ClassicBtDevice device) async {
    if (_isConnecting || _isConnected) {
      _log('Already connected or connecting');
      return _isConnected;
    }

    _isConnecting = true;
    _deviceName = device.name.isNotEmpty ? device.name : 'ESP32';

    try {
      _log('Connecting to $_deviceName (${device.address})...');

      await _methodChannel.invokeMethod('connect', {'address': device.address});

      _isConnected = true;
      _isConnecting = false;
      _buffer.clear();
      _log('✅ Connected to $_deviceName');
      return true;
    } on PlatformException catch (e) {
      _log('❌ Connection failed: ${e.message}');
      _isConnected = false;
      _isConnecting = false;
      rethrow;
    } catch (e) {
      _log('❌ Connection failed: $e');
      _isConnected = false;
      _isConnecting = false;
      rethrow;
    }
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    try {
      _log('Disconnecting...');
      await stopListening();
      await _methodChannel.invokeMethod('disconnect');
    } catch (e) {
      _log('⚠️ Disconnect error: $e');
    }

    _isConnected = false;
    _deviceName = '';
    _buffer.clear();
    _log('✅ Disconnected');
  }

  // ============== Data Listening ==============

  /// Start listening for 17-byte sensor packets from ESP32.
  /// Raw bytes arrive via EventChannel, get buffered and parsed here.
  Future<void> startListening() async {
    if (!_isConnected) {
      throw Exception('Not connected to any device');
    }

    // Create fresh sensor stream
    _sensorController?.close();
    _sensorController = StreamController<SensorReading>.broadcast();
    _buffer.clear();

    _log('📡 Listening for sensor data...');

    _rawDataSubscription =
        _dataEventChannel.receiveBroadcastStream().listen(
      (event) {
        // Native sends List<int> (bytes)
        final bytes = (event as List).cast<int>();
        _onDataReceived(bytes);
      },
      onError: (error) {
        _log('❌ Data stream error: $error');
        _isConnected = false;
        _sensorController?.addError(error);
      },
      onDone: () {
        _log('⚠️ Data stream ended (device disconnected?)');
        _isConnected = false;
      },
    );
  }

  /// Stop listening for data
  Future<void> stopListening() async {
    await _rawDataSubscription?.cancel();
    _rawDataSubscription = null;
    await _sensorController?.close();
    _sensorController = null;
    _buffer.clear();
  }

  // ============== Data Processing ==============

  /// Accumulate bytes and parse complete 17-byte packets
  void _onDataReceived(List<int> data) {
    _buffer.addAll(data);

    _log(
      '📥 +${data.length} bytes (buffer: ${_buffer.length}) '
      'raw: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );

    // Process all complete 17-byte packets
    while (_buffer.length >= 17) {
      final packet = _buffer.sublist(0, 17);
      _buffer.removeRange(0, 17);

      final reading = _parsePayload(packet);
      if (reading != null) {
        _log('🎉 Parsed reading → emitting');
        _sensorController?.add(reading);
      }
    }
  }

  // ============== 17-Byte Payload Parsing ==============
  //
  // ESP32 SensorRiskPacket layout (matches bluetooth_service.h):
  //
  // Byte  0-3  : Temperature zones (Heel, Ball, Arch, Toe)
  //              Encoding: int8 = (temp - 25.0) * 2
  //              Decoding: temp = 25.0 + signed_byte / 2.0
  //
  // Byte  4-7  : Pressure zones (Heel, Ball, Arch, Toe)
  //              Encoding: uint8 = pressure / 0.3
  //              Decoding: pressure = byte * 0.3
  //
  // Byte  8    : SpO2 (uint8, direct %)
  //
  // Byte  9    : Heart Rate (uint8, BPM)
  //
  // Byte 10-11 : Step Count (uint16 big-endian)
  //
  // Byte 12    : Risk Probability (uint8, 0-100%)
  //
  // Byte 13    : Risk Level (uint8, 0=low, 1=moderate, 2=high, 3=critical)
  //
  // Byte 14    : Battery Level (0-100%)
  //
  // Byte 15-16 : Timestamp (uint16 big-endian, seconds since boot)

  SensorReading? _parsePayload(List<int> packet) {
    try {
      if (packet.length != 17) return null;

      // ---- Temperatures (Bytes 0-3) ----
      // Encoding: int8 = (temp - 25.0) * 2
      // Decoding: temp = 25.0 + signed_byte / 2.0
      final temperatures = <double>[];
      for (int i = 0; i < 4; i++) {
        final raw = packet[i];
        // Convert uint8 to signed int8
        final signed = raw > 127 ? raw - 256 : raw;
        var temp = 25.0 + signed / 2.0;
        // Valid range: -10°C to 50°C. Outside means sensor error → show 0
        if (temp < -10.0 || temp > 50.0) temp = 0.0;
        temperatures.add(temp);
      }
      _log('🌡️  Temps: ${temperatures.map((t) => t.toStringAsFixed(1)).join(', ')}°C');

      // ---- Pressures (Bytes 4-7) ----
      final pressures = <double>[];
      for (int i = 0; i < 4; i++) {
        final raw = packet[4 + i];
        final pressure = raw * 0.3;
        pressures.add(pressure);
      }
      _log('📊 Pressures: ${pressures.map((p) => p.toStringAsFixed(1)).join(', ')} kPa');

      // ---- SpO2 (Byte 8) ----
      double spO2 = packet[8].toDouble();
      if (spO2 > 100.0) spO2 = 100.0;
      if (spO2 < 0.0) spO2 = 0.0;
      _log('❤️  SpO2: ${spO2.toStringAsFixed(1)}%');

      // ---- Heart Rate (Byte 9) ----
      int heartRate = packet[9];
      if (heartRate > 250) heartRate = 250;
      _log('💓 HR: $heartRate BPM');

      // ---- Step Count (Bytes 10-11) ----
      final stepCount = (packet[10] << 8) | packet[11];
      _log('👟 Steps: $stepCount');

      // ---- Risk Probability (Byte 12) ----
      final riskProbability = packet[12].clamp(0, 100).toDouble();
      _log('🧠 Risk Prob: $riskProbability%');

      // ---- Risk Level (Byte 13) ----
      final riskLevel = packet[13].clamp(0, 3);
      _log('⚠️ Risk Level: $riskLevel');

      // ---- Battery Level (Byte 14) ----
      _batteryLevel = packet[14].clamp(0, 100);

      // ---- Timestamp (Bytes 15-16) ----
      // Seconds since device boot — informational only
      // final deviceTimestamp = (packet[15] << 8) | packet[16];

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

      _log(
        '✅ T=[${temperatures.map((t) => t.toStringAsFixed(1)).join(',')}]°C '
        'P=[${pressures.map((p) => p.toStringAsFixed(1)).join(',')}]kPa '
        'SpO2=${spO2.toStringAsFixed(1)}% HR=$heartRate STP=$stepCount '
        'RISK=${riskProbability.toStringAsFixed(0)}%/$riskLevel BAT=$_batteryLevel%',
      );

      return reading;
    } catch (e) {
      _log('❌ Parse error: $e');
      return null;
    }
  }

  // ============== Logging ==============

  static void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ClassicBT] $msg');
    }
  }
}
