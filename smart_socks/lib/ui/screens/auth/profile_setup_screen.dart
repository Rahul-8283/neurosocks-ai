import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/user_profile.dart';
import '../../../providers/user_provider.dart';

/// Multi-step profile setup wizard for new users (offline - no Firebase)
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;

  // Form controllers
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _diabetesYearsController = TextEditingController();

  // Form values
  DiabetesType _diabetesType = DiabetesType.type2;
  bool _hasNeuropathy = false;
  bool _hasPAD = false;
  bool _hasPreviousUlcer = false;
  bool _hasHypertension = false;
  TemperatureUnit _temperatureUnit = TemperatureUnit.celsius;
  bool _enableNotifications = true;
  bool _enableCriticalAlerts = true;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _diabetesYearsController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      // Validate current step before proceeding
      if (_currentStep == 0 && !_validateBasicInfo()) return;

      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    } else {
      _saveProfile();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  bool _validateBasicInfo() {
    if (_nameController.text.trim().isEmpty) {
      _showError('Please enter your name');
      return false;
    }
    if (_ageController.text.isEmpty) {
      _showError('Please enter your age');
      return false;
    }
    final age = int.tryParse(_ageController.text);
    if (age == null || age < 1 || age > 120) {
      _showError('Please enter a valid age');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveProfile() async {
    final userProvider = context.read<UserProvider>();

    // Create HealthInfo with exact field names from user_profile.dart
    final healthInfo = HealthInfo(
      hasNeuropathy: _hasNeuropathy,
      hasPAD: _hasPAD,
      hasPreviousUlcer: _hasPreviousUlcer,
      hasHypertension: _hasHypertension,
    );

    // Create UserSettings with exact field names from user_profile.dart
    final settings = UserSettings(
      temperatureUnit: _temperatureUnit,
      notificationsEnabled: _enableNotifications,
      criticalAlertsEnabled: _enableCriticalAlerts,
    );

    // Create UserProfile with exact field names from user_profile.dart
    final profile = UserProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: '', // Not using email-based auth (offline mode)
      name: _nameController.text.trim(),
      age: int.parse(_ageController.text),
      diabetesType: _diabetesType,
      diabetesYears: int.tryParse(_diabetesYearsController.text),
      healthInfo: healthInfo,
      settings: settings,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Use saveProfile from user_provider.dart
    await userProvider.saveProfile(profile);
    await userProvider.setOnboardingComplete(true);

    if (mounted) {
      // Navigate to login screen to set PIN
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Setup'),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(),

          // Step content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicInfoStep(),
                _buildDiabetesInfoStep(),
                _buildHealthConditionsStep(),
                _buildPreferencesStep(),
              ],
            ),
          ),

          // Action button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentStep == _totalSteps - 1
                      ? AppStrings.done
                      : AppStrings.continueBtn,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(_totalSteps, (index) {
              final isCompleted = index < _currentStep;
              final isCurrent = index == _currentStep;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: isCompleted || isCurrent
                              ? AppColors.primary
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (index < _totalSteps - 1) const SizedBox(width: 4),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${_currentStep + 1} of $_totalSteps',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Basic Information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us a bit about yourself',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),

          // Name field
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: AppStrings.name,
              hintText: 'Enter your name',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),

          // Age field
          TextField(
            controller: _ageController,
            decoration: InputDecoration(
              labelText: AppStrings.age,
              hintText: 'Enter your age',
              prefixIcon: const Icon(Icons.cake_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildDiabetesInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diabetes Information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Help us personalize your risk assessment',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),

          // Diabetes type
          Text(
            AppStrings.diabetesType,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildDiabetesTypeOption(DiabetesType.type1, AppStrings.type1),
          const SizedBox(height: 8),
          _buildDiabetesTypeOption(DiabetesType.type2, AppStrings.type2),
          const SizedBox(height: 8),
          _buildDiabetesTypeOption(DiabetesType.preDiabetes, AppStrings.preDiabetes),
          const SizedBox(height: 8),
          _buildDiabetesTypeOption(DiabetesType.none, AppStrings.none),
          const SizedBox(height: 24),

          // Years with diabetes
          TextField(
            controller: _diabetesYearsController,
            decoration: InputDecoration(
              labelText: 'Years with Diabetes',
              hintText: 'Enter number of years',
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildDiabetesTypeOption(DiabetesType type, String label) {
    final isSelected = _diabetesType == type;
    return InkWell(
      onTap: () => setState(() => _diabetesType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : Colors.grey[400],
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? AppColors.primary : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthConditionsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Health Conditions',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select any conditions that apply to you',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),

          _buildConditionTile(
            icon: Icons.sensors_off,
            title: 'Peripheral Neuropathy',
            subtitle: 'Nerve damage causing reduced sensation',
            value: _hasNeuropathy,
            onChanged: (v) => setState(() => _hasNeuropathy = v),
          ),
          const SizedBox(height: 12),

          _buildConditionTile(
            icon: Icons.bloodtype,
            title: 'Peripheral Artery Disease (PAD)',
            subtitle: 'Reduced blood flow to limbs',
            value: _hasPAD,
            onChanged: (v) => setState(() => _hasPAD = v),
          ),
          const SizedBox(height: 12),

          _buildConditionTile(
            icon: Icons.healing,
            title: 'Previous Foot Ulcers',
            subtitle: 'History of foot ulcers',
            value: _hasPreviousUlcer,
            onChanged: (v) => setState(() => _hasPreviousUlcer = v),
          ),
          const SizedBox(height: 12),

          _buildConditionTile(
            icon: Icons.favorite,
            title: 'High Blood Pressure',
            subtitle: 'Hypertension diagnosis',
            value: _hasHypertension,
            onChanged: (v) => setState(() => _hasHypertension = v),
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This information helps us provide more accurate risk assessments. You can update these settings later.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: value
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: value ? AppColors.primary : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: value ? AppColors.primary : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferences',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Customize your app experience',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),

          // Temperature unit
          Text(
            AppStrings.temperatureUnit,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildUnitOption(
                TemperatureUnit.celsius,
                AppStrings.celsius,
                'Celsius',
              ),
              const SizedBox(width: 12),
              _buildUnitOption(
                TemperatureUnit.fahrenheit,
                AppStrings.fahrenheit,
                'Fahrenheit',
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Notifications section
          Text(
            AppStrings.notifications,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          _buildSwitchTile(
            icon: Icons.notifications_outlined,
            title: AppStrings.enableNotifications,
            subtitle: 'Receive alerts and updates',
            value: _enableNotifications,
            onChanged: (v) => setState(() => _enableNotifications = v),
          ),
          const SizedBox(height: 12),

          _buildSwitchTile(
            icon: Icons.warning_amber_outlined,
            title: AppStrings.criticalAlerts,
            subtitle: 'Always alert for critical risks',
            value: _enableCriticalAlerts,
            onChanged: (v) => setState(() => _enableCriticalAlerts = v),
          ),

          const SizedBox(height: 32),

          // Ready message
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withValues(alpha: 0.1),
                  AppColors.primary.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 48,
                  color: AppColors.success,
                ),
                const SizedBox(height: 12),
                const Text(
                  'You\'re all set!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Done" to start monitoring your foot health.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitOption(TemperatureUnit unit, String symbol, String label) {
    final isSelected = _temperatureUnit == unit;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _temperatureUnit = unit),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                symbol,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? AppColors.primary : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
