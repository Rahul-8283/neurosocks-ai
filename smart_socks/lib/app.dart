import 'package:flutter/material.dart' hide ThemeMode;
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'data/models/user_profile.dart';
import 'providers/sensor_provider.dart';
import 'providers/risk_provider.dart';
import 'providers/user_provider.dart';
import 'ui/screens/auth/welcome_screen.dart';
import 'ui/screens/auth/choice_screen.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/profile_setup_screen.dart';
import 'ui/screens/home/dashboard_screen.dart';
import 'ui/screens/home/sensors_screen.dart';
import 'ui/screens/home/alerts_screen.dart';
import 'ui/screens/home/settings_screen.dart';

// Use Flutter's ThemeMode for MaterialApp
import 'package:flutter/material.dart' as flutter show ThemeMode;

/// Main application widget with providers and routing
class SmartSocksApp extends StatelessWidget {
  const SmartSocksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // User provider (manages profile, settings, theme)
        ChangeNotifierProvider(create: (_) => UserProvider()),
        
        // Sensor provider (manages BLE, sensor data)
        ChangeNotifierProvider(create: (_) => SensorProvider()),
        
        // Risk provider (manages risk calculations, alerts)
        ChangeNotifierProvider(create: (_) => RiskProvider()),
      ],
      child: Consumer<UserProvider>(
        builder: (context, userProvider, _) {
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            
            // Theme configuration
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _mapThemeMode(userProvider.userProfile?.settings.themeMode),
            
            // Initial route based on login status
            initialRoute: _getInitialRoute(userProvider),
            
            // Named routes
            routes: {
              '/welcome': (context) => const WelcomeScreen(),
              '/choice': (context) => const ChoiceScreen(),
              '/login': (context) => const LoginScreen(),
              '/profile-setup': (context) => const ProfileSetupScreen(),
              '/dashboard': (context) => const DashboardScreen(),
              '/sensors': (context) => const SensorsScreen(),
              '/alerts': (context) => const AlertsScreen(),
              '/settings': (context) => const SettingsScreen(),
            },
            
            // Handle unknown routes
            onUnknownRoute: (settings) {
              return MaterialPageRoute(
                builder: (context) => const WelcomeScreen(),
              );
            },
          );
        },
      ),
    );
  }

  /// Determine initial route based on user state
  String _getInitialRoute(UserProvider userProvider) {
    // If loading, show welcome (will redirect after load)
    if (userProvider.isLoading) {
      return '/welcome';
    }
    
    // If not logged in (no user profile), show welcome screen (onboarding)
    if (!userProvider.isLoggedIn) {
      return '/welcome';
    }
    
    // If logged in but profile incomplete, go to profile setup
    if (!userProvider.onboardingComplete) {
      return '/profile-setup';
    }
    
    // If logged in and profile complete but no PIN set, go to login screen (PIN setup)
    if (!userProvider.isPinSet) {
      return '/login';
    }
    
    // If logged in, profile complete, and PIN set, go to dashboard
    return '/dashboard';
  }

  /// Map user_profile ThemeMode to Flutter ThemeMode
  flutter.ThemeMode _mapThemeMode(ThemeMode? mode) {
    if (mode == null) return flutter.ThemeMode.system;
    switch (mode) {
      case ThemeMode.light:
        return flutter.ThemeMode.light;
      case ThemeMode.dark:
        return flutter.ThemeMode.dark;
      case ThemeMode.system:
        return flutter.ThemeMode.system;
    }
  }
}

/// Home screen with bottom navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    SensorsScreen(),
    AlertsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: AppStrings.navDashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.sensors_outlined),
            selectedIcon: const Icon(Icons.sensors),
            label: AppStrings.navFootMap,
          ),
          NavigationDestination(
            icon: Consumer<RiskProvider>(
              builder: (context, provider, child) {
                return Badge(
                  isLabelVisible: provider.unreadAlertCount > 0,
                  label: Text('${provider.unreadAlertCount}'),
                  child: const Icon(Icons.notifications_outlined),
                );
              },
            ),
            selectedIcon: Consumer<RiskProvider>(
              builder: (context, provider, child) {
                return Badge(
                  isLabelVisible: provider.unreadAlertCount > 0,
                  label: Text('${provider.unreadAlertCount}'),
                  child: const Icon(Icons.notifications),
                );
              },
            ),
            label: AppStrings.navAlerts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: AppStrings.navSettings,
          ),
        ],
      ),
    );
  }
}
