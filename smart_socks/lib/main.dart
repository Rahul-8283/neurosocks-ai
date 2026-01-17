import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/services/storage_service.dart';
import 'app.dart';

/// Main entry point for Smart Socks application
// yet to resolve the authentication errors

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (portrait only for mobile)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // Initialize storage service (Hive boxes and SharedPreferences)
  await StorageService().initialize();

  // Run the app
  runApp(const SmartSocksApp());
}
