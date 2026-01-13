import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/services/storage_service.dart';
import '../../../providers/user_provider.dart';

/// Simple PIN-based local authentication screen (offline - no Firebase)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final List<String> _enteredPin = [];
  final int _pinLength = 4;
  bool _isError = false;
  bool _isLoading = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Stored PIN loaded from persistent storage
  String? _storedPin;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });

    // Load PIN from persistent storage
    _loadStoredPin();
  }

  /// Load PIN from SharedPreferences
  void _loadStoredPin() {
    final pin = StorageService().getPIN();
    setState(() {
      _storedPin = pin;
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    if (_enteredPin.length < _pinLength && !_isLoading) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin.add(number);
        _isError = false;
      });

      if (_enteredPin.length == _pinLength) {
        _verifyPin();
      }
    }
  }

  void _onDeletePressed() {
    if (_enteredPin.isNotEmpty && !_isLoading) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin.removeLast();
        _isError = false;
      });
    }
  }

  Future<void> _verifyPin() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate verification delay
    await Future.delayed(const Duration(milliseconds: 500));

    final enteredPin = _enteredPin.join();
    
    // If no PIN is stored, this is first-time setup - save the PIN
    if (_storedPin == null) {
      await StorageService().savePIN(enteredPin);
      _storedPin = enteredPin;
      HapticFeedback.mediumImpact();
      if (mounted) {
        _navigateToNextScreen();
      }
    } else if (_storedPin == enteredPin) {
      // PIN matches - authentication successful
      HapticFeedback.mediumImpact();
      if (mounted) {
        _navigateToNextScreen();
      }
    } else {
      // PIN doesn't match - show error
      _showError();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToNextScreen() {
    final userProvider = context.read<UserProvider>();
    final nextRoute = userProvider.onboardingComplete ? '/dashboard' : '/profile-setup';
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    _shakeController.forward();
    setState(() {
      _isError = true;
      _enteredPin.clear();
    });
  }

  Future<void> _useBiometrics() async {
    // Placeholder for biometric authentication
    // In real app, would use local_auth package
    setState(() {
      _isLoading = true;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    
    // Simulate successful biometric auth
    HapticFeedback.mediumImpact();
    if (mounted) {
      _navigateToNextScreen();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _skipLogin() {
    // For demo mode - skip authentication
    _navigateToNextScreen();
  }

  void _forgotPin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset PIN'),
        content: const Text(
          'This will reset your PIN. Your health data will remain intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Clear PIN from storage
              await StorageService().clearPIN();
              setState(() {
                _storedPin = null;
                _enteredPin.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PIN reset. Enter a new PIN.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final userName = userProvider.userName;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Skip button (demo mode)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _skipLogin,
                  child: Text(
                    AppStrings.skip,
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Welcome message
              Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your PIN to continue',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // PIN dots
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(
                      _shakeAnimation.value * ((_shakeAnimation.value % 2 == 0) ? 1 : -1),
                      0,
                    ),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pinLength, (index) {
                    final isFilled = index < _enteredPin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _isError
                            ? AppColors.error
                            : isFilled
                                ? AppColors.primary
                                : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isError
                              ? AppColors.error
                              : isFilled
                                  ? AppColors.primary
                                  : Colors.grey[400]!,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Error message
              AnimatedOpacity(
                opacity: _isError ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Wrong PIN. Please try again.',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Number pad
              _buildNumberPad(),

              const SizedBox(height: 24),

              // Additional options
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Biometrics button
                  IconButton(
                    onPressed: _isLoading ? null : _useBiometrics,
                    icon: const Icon(Icons.fingerprint),
                    iconSize: 32,
                    color: AppColors.primary,
                  ),

                  const SizedBox(width: 32),

                  // Forgot PIN
                  TextButton(
                    onPressed: _forgotPin,
                    child: Text(
                      'Forgot PIN?',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('1'),
            _buildNumberButton('2'),
            _buildNumberButton('3'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('4'),
            _buildNumberButton('5'),
            _buildNumberButton('6'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('7'),
            _buildNumberButton('8'),
            _buildNumberButton('9'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildEmptyButton(),
            _buildNumberButton('0'),
            _buildDeleteButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberButton(String number) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _onDeletePressed,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 28,
              color: _enteredPin.isEmpty ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyButton() {
    return const SizedBox(width: 72, height: 72);
  }
}

/// Screen for setting up a new PIN
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final List<String> _pin = [];
  final List<String> _confirmPin = [];
  final int _pinLength = 4;
  bool _isConfirming = false;
  bool _isError = false;

  void _onNumberPressed(String number) {
    final targetList = _isConfirming ? _confirmPin : _pin;

    if (targetList.length < _pinLength) {
      HapticFeedback.lightImpact();
      setState(() {
        targetList.add(number);
        _isError = false;
      });

      if (targetList.length == _pinLength) {
        if (!_isConfirming) {
          // Move to confirmation
          setState(() {
            _isConfirming = true;
          });
        } else {
          // Verify PINs match
          _verifyAndSave();
        }
      }
    }
  }

  void _onDeletePressed() {
    final targetList = _isConfirming ? _confirmPin : _pin;

    if (targetList.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        targetList.removeLast();
        _isError = false;
      });
    } else if (_isConfirming) {
      // Go back to entering PIN
      setState(() {
        _isConfirming = false;
        _pin.clear();
      });
    }
  }

  Future<void> _verifyAndSave() async {
    if (_pin.join() == _confirmPin.join()) {
      // PINs match - save to persistent storage
      await StorageService().savePIN(_pin.join());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isError = true;
        _confirmPin.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirming ? _confirmPin : _pin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set PIN'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Instructions
              Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isConfirming ? Icons.check_circle_outline : Icons.lock_outline,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isConfirming ? 'Confirm your PIN' : 'Create a PIN',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConfirming
                        ? 'Re-enter your PIN to confirm'
                        : 'This PIN will be used to secure your app',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < currentPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _isError
                          ? AppColors.error
                          : isFilled
                              ? AppColors.primary
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isError
                            ? AppColors.error
                            : isFilled
                                ? AppColors.primary
                                : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),

              // Error message
              AnimatedOpacity(
                opacity: _isError ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'PINs don\'t match. Try again.',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Number pad
              _buildNumberPad(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('1'),
            _buildNumberButton('2'),
            _buildNumberButton('3'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('4'),
            _buildNumberButton('5'),
            _buildNumberButton('6'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNumberButton('7'),
            _buildNumberButton('8'),
            _buildNumberButton('9'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 72, height: 72),
            _buildNumberButton('0'),
            _buildDeleteButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberButton(String number) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    final currentPin = _isConfirming ? _confirmPin : _pin;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onDeletePressed,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 28,
              color: currentPin.isEmpty ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}
