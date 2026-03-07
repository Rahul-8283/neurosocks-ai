import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/alert.dart';
import '../../../data/models/risk_score.dart';
import '../../../providers/sensor_provider.dart';
import '../../../providers/risk_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/firebase/firebase_auth_provider.dart';
import '../../widgets/risk_gauge.dart';
import '../../widgets/sensor_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/alert_tile.dart';
import '../../widgets/connection_status.dart';
import 'classic_bt_scan_screen.dart';

/// ESP32 Edge ML: Dashboard shows real-time sensor data and risk predictions from hardware
/// Risk predictions computed on-device (ESP32) and transmitted via 17-byte BLE packets

/// Main dashboard screen showing overview of foot health
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Start streaming data when dashboard opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDashboard();
    });
  }

  Future<void> _initializeDashboard() async {
    // 1. Sync profile from Firestore if logged in
    final authProvider = context.read<FirebaseAuthProvider>();
    final userProvider = context.read<UserProvider>();
    final sensorProvider = context.read<SensorProvider>();

    if (authProvider.isLoggedIn && authProvider.currentUserId != null) {
      await userProvider.syncFromFirestore(authProvider.currentUserId!);

      // IMPORTANT: Set the current user ID in SensorProvider
      // This is required for saving sensor data to Firestore
      sensorProvider.setCurrentUser(authProvider.currentUserId!);

      // Set user in RiskProvider for Firestore alert & prediction storage
      final riskProvider = context.read<RiskProvider>();
      riskProvider.setCurrentUser(authProvider.currentUserId!);
    }

    // 2. Start sensor monitoring (real BLE mode - no auto-connect)
    // Real BLE requires manual connection via device scan in settings
    debugPrint('Dashboard initialized. Real BLE mode is default.');
    debugPrint('Please go to Settings to scan and connect your device.');
  }


  Future<void> _onRefresh() async {
    final sensorProvider = context.read<SensorProvider>();

    if (!sensorProvider.isStreaming) {
      // Always attempt to start streaming
      // If not connected, the provider will load from Firestore as fallback
      await sensorProvider.startStreaming();
    } else {
      await sensorProvider.stopStreaming();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Consumer3<SensorProvider, RiskProvider, UserProvider>(
          builder: (context, sensorProvider, riskProvider, userProvider, _) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning banner if not connected to Bluetooth
                  if (!sensorProvider.isConnected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        border: Border.all(color: Colors.orange, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Device not connected. All readings are zero. Go to Settings to connect your device.',
                              style: TextStyle(color: Colors.orange[900]),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Connection status bar
                  _buildConnectionStatus(sensorProvider),
                  const SizedBox(height: 16),

                  // Edge ML Status Indicator
                  _buildEdgeMLStatusIndicator(sensorProvider),
                  const SizedBox(height: 20),

                  // Risk gauge section
                  _buildRiskSection(riskProvider),
                  const SizedBox(height: 24),

                  // Quick stats row
                  _buildQuickStats(sensorProvider, riskProvider),
                  const SizedBox(height: 24),

                  // Sensor cards section
                  _buildSensorSection(sensorProvider),
                  const SizedBox(height: 24),

                  // Recent alerts section
                  _buildAlertsSection(riskProvider),
                  const SizedBox(height: 24),

                  // Recommendations section
                  if (riskProvider.recommendations.isNotEmpty)
                    _buildRecommendationsSection(riskProvider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(AppStrings.appName),
          Consumer<UserProvider>(
            builder: (context, userProvider, _) {
              return Text(
                'Hello, ${userProvider.userName}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey[600],
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        // Alerts badge
        Consumer<RiskProvider>(
          builder: (context, riskProvider, _) {
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    Navigator.of(context).pushNamed('/alerts');
                  },
                ),
                if (riskProvider.unreadAlertCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${riskProvider.unreadAlertCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () {
            Navigator.of(context).pushNamed('/settings');
          },
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(SensorProvider provider) {
    ConnectionState state;
    if (provider.isConnecting) {
      state = ConnectionState.connecting;
    } else if (provider.isConnected) {
      state = ConnectionState.connected;
    } else if (provider.errorMessage != null) {
      state = ConnectionState.error;
    } else {
      state = ConnectionState.disconnected;
    }

    return ConnectionStatus(
      state: state,
      deviceName: provider.deviceName,
      batteryLevel: provider.batteryLevel,
      onTap: () {
        if (!provider.isConnected) {
          // Navigate to device scan screen to connect
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const ClassicBtScanScreen(),
            ),
          );
        }
      },
    );
  }

  Widget _buildRiskSection(RiskProvider riskProvider) {
    final riskScore = riskProvider.currentRiskScore;

    return Center(
      child: Column(
        children: [
          Text(
            AppStrings.dailyRiskScore,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),

          // Risk gauge
          if (riskScore != null)
            RiskGauge.fromRiskScore(
              riskScore,
              size: 220,
              showScore: true,
              showLabel: true,
            )
          else
            RiskGauge(score: 0, level: RiskLevel.low, size: 220),

          const SizedBox(height: 16),

          // Risk level message
          _buildRiskMessage(riskProvider.currentRiskLevel),
          const SizedBox(height: 12),

          // Edge ML Badge
          _buildEdgeMLBadge(riskProvider),
        ],
      ),
    );
  }

  /// Edge ML badge below risk gauge
  Widget _buildEdgeMLBadge(RiskProvider riskProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.memory, size: 14, color: Colors.teal[700]),
          const SizedBox(width: 6),
          Text(
            'Edge ML (ESP32)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.teal[700],
            ),
          ),
        ],
      ),
    );
  }

  /// Edge ML status indicator showing connection & prediction status
  Widget _buildEdgeMLStatusIndicator(SensorProvider sensorProvider) {
    final isConnected = sensorProvider.isConnected;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    String subText;

    if (isConnected) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Edge ML Active';
      subText = 'ESP32 sending predictions via Bluetooth';
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.cloud_off;
      statusText = 'Edge ML Offline';
      subText = 'Connect device to receive predictions';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                Text(
                  subText,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.memory, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  'ESP32',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskMessage(RiskLevel level) {
    String message;
    Color color;
    IconData icon;

    switch (level) {
      case RiskLevel.low:
        message = AppStrings.lookingGood;
        color = AppColors.riskLow;
        icon = Icons.check_circle;
        break;
      case RiskLevel.moderate:
        message = AppStrings.needsAttention;
        color = AppColors.riskModerate;
        icon = Icons.info;
        break;
      case RiskLevel.high:
        message = AppStrings.takeAction;
        color = AppColors.riskHigh;
        icon = Icons.warning;
        break;
      case RiskLevel.critical:
        message = AppStrings.seekHelp;
        color = AppColors.riskCritical;
        icon = Icons.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(
    SensorProvider sensorProvider,
    RiskProvider riskProvider,
  ) {
    return Row(
      children: [
        Expanded(
          child: StatCard.steps(steps: sensorProvider.stepCount, goal: 10000),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard.alerts(
            count: riskProvider.alerts.length,
            criticalCount: riskProvider.alerts
                .where((a) => a.severity == AlertSeverity.critical)
                .length,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorSection(SensorProvider provider) {
    final reading = provider.currentReading; // null when disconnected
    final isLive = provider.isConnected && reading != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.currentReadings,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (isLive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/sensors');
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Sensor cards grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            // Temperature (average of all zones)
            SensorCard.temperature(
              value: reading != null && reading.temperatures.isNotEmpty
                  ? reading.temperatures.reduce((a, b) => a + b) /
                        reading.temperatures.length
                  : 0,
              onTap: () => Navigator.of(context).pushNamed('/sensors'),
            ),

            // Pressure (average)
            SensorCard.pressure(
              value: reading != null && reading.pressures.isNotEmpty
                  ? reading.pressures.reduce((a, b) => a + b) /
                        reading.pressures.length
                  : 0,
              onTap: () => Navigator.of(context).pushNamed('/sensors'),
            ),

            // SpO2
            SensorCard.spO2(
              value: provider.spO2,
              onTap: () => Navigator.of(context).pushNamed('/sensors'),
            ),

            // Heart Rate
            SensorCard.heartRate(
              value: provider.heartRate,
              onTap: () => Navigator.of(context).pushNamed('/sensors'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsSection(RiskProvider riskProvider) {
    final recentAlerts = riskProvider.alerts.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppStrings.alerts,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (recentAlerts.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/alerts');
                },
                child: const Text('View All'),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (recentAlerts.isEmpty)
          _buildNoAlertsCard()
        else
          ...recentAlerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AlertTile(
                alert: alert,
                dismissible: false,
                onTap: () {
                  riskProvider.markAlertAsRead(alert.id);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoAlertsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 48),
          const SizedBox(height: 12),
          Text(
            AppStrings.allClear,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 4),
          Text(AppStrings.noAlerts, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildRecommendationsSection(RiskProvider riskProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.recommendations,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        ...riskProvider.recommendations
            .take(3)
            .map(
              (rec) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: AppColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
