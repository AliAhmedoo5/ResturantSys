import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'pin_numpad.dart';

/// Fullscreen lock screen providing touch and physical numpad PIN entry for counter staff.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({
    super.key,
    required this.onPinSubmitted,
    this.title = 'Enter Staff PIN',
    this.subtitle = 'Enter your 4-digit numeric code to unlock the register',
  });

  final Future<bool> Function(String pin) onPinSubmitted;
  final String title;
  final String subtitle;

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _enteredPin = '';
  String? _errorMessage;
  bool _isAuthenticating = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleDigit(String digit) {
    if (_isAuthenticating || _enteredPin.length >= 8) return;

    final nextPin = _enteredPin + digit;
    setState(() {
      _errorMessage = null;
      _enteredPin = nextPin;
    });

    if (nextPin.length == 4) {
      _submitPin(force: false);
    } else if (nextPin.length == 8) {
      _submitPin(force: true);
    }
  }

  void _handleBackspace() {
    if (_isAuthenticating || _enteredPin.isEmpty) return;
    setState(() {
      _errorMessage = null;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  void _handleClear() {
    if (_isAuthenticating) return;
    setState(() {
      _errorMessage = null;
      _enteredPin = '';
    });
  }

  Future<void> _submitPin({bool force = true}) async {
    if (_enteredPin.length < 4 || _isAuthenticating) return;

    final pinToVerify = _enteredPin;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onPinSubmitted(pinToVerify);
      if (!mounted) return;

      if (!success) {
        if (force || pinToVerify.length == 8) {
          setState(() {
            _enteredPin = '';
            _isAuthenticating = false;
            _errorMessage = 'Invalid PIN. Please try again.';
          });
        } else {
          // If not forced (auto-checked at 4 digits) and failed, allow user to keep typing longer PIN
          setState(() {
            _isAuthenticating = false;
          });
        }
      } else {
        setState(() {
          _enteredPin = '';
          _isAuthenticating = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enteredPin = '';
        _isAuthenticating = false;
        _errorMessage = 'Authentication error. Please retry.';
      });
    }
  }

  static final Map<LogicalKeyboardKey, String> _digitKeyMap = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad9: '9',
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    final digit = _digitKeyMap[key];
    if (digit != null) {
      _handleDigit(digit);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      _handleClear();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_enteredPin.length >= 4) {
        _submitPin(force: true);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Lock Icon & Header
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: WarmCounterColors.lightActiveNavHighlight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: WarmCounterColors.lightBorder,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 24,
                  color: WarmCounterColors.lightPrimaryAction,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space12),

              Text(
                widget.title,
                style: WarmCounterTypography.pageHeading.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space4),

              Text(
                widget.subtitle,
                style: WarmCounterTypography.bodyMedium.copyWith(
                  color: WarmCounterColors.lightSecondaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WarmCounterSpacing.space16),

              // PIN Dots Indicator
              _buildPinDots(),
              const SizedBox(height: WarmCounterSpacing.space12),

              // Error or Status Message
              _buildStatusFeedback(),
              const SizedBox(height: WarmCounterSpacing.space16),

              // On-Screen Touch Numpad
              PinNumpad(
                isEnabled: !_isAuthenticating,
                onDigitPressed: _handleDigit,
                onClearPressed: _handleClear,
                onBackspacePressed: _handleBackspace,
              ),
              if (_enteredPin.length >= 4) ...[
                const SizedBox(height: WarmCounterSpacing.space16),
                ElevatedButton.icon(
                  key: const ValueKey('unlock_pin_button'),
                  onPressed: _isAuthenticating ? null : () => _submitPin(force: true),
                  icon: const Icon(Icons.lock_open_rounded, size: 20),
                  label: const Text('Unlock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 44),
                    shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    final dotCount = _enteredPin.length > 4 ? _enteredPin.length : 4;
    return Container(
      key: const ValueKey('pin_dots_container'),
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space24,
        vertical: WarmCounterSpacing.space12,
      ),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: _errorMessage != null
              ? WarmCounterColors.lightDestructive
              : WarmCounterColors.lightBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(dotCount, (index) {
          final isFilled = index < _enteredPin.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: WarmCounterSpacing.space8),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled
                  ? WarmCounterColors.lightPrimaryAction
                  : Colors.transparent,
              border: Border.all(
                color: isFilled
                    ? WarmCounterColors.lightPrimaryAction
                    : WarmCounterColors.lightSecondaryText.withValues(alpha: 0.5),
                width: 2.0,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatusFeedback() {
    if (_isAuthenticating) {
      return const SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WarmCounterColors.lightPrimaryAction,
              ),
            ),
            SizedBox(width: WarmCounterSpacing.space8),
            Text(
              'Verifying PIN...',
              style: WarmCounterTypography.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return SizedBox(
        height: 24,
        child: Text(
          _errorMessage!,
          style: WarmCounterTypography.bodyMedium.copyWith(
            color: WarmCounterColors.lightDestructive,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return const SizedBox(height: 24);
  }
}
