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
    if (_isAuthenticating || _enteredPin.length >= 4) return;

    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 4) {
      _submitPin();
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

  Future<void> _submitPin() async {
    if (_enteredPin.length != 4 || _isAuthenticating) return;

    final pinToVerify = _enteredPin;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onPinSubmitted(pinToVerify);
      if (!mounted) return;

      if (!success) {
        setState(() {
          _enteredPin = '';
          _isAuthenticating = false;
          _errorMessage = 'Invalid PIN. Please try again.';
        });
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Physical numbers 0-9
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _handleDigit('0');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _handleDigit('1');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      _handleDigit('2');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      _handleDigit('3');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      _handleDigit('4');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      _handleDigit('5');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      _handleDigit('6');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      _handleDigit('7');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      _handleDigit('8');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      _handleDigit('9');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      _handleClear();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_enteredPin.length == 4) {
        _submitPin();
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
                width: 64,
                height: 64,
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
                  size: 32,
                  color: WarmCounterColors.lightPrimaryAction,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space16),

              Text(
                widget.title,
                style: WarmCounterTypography.pageHeading.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space8),

              Text(
                widget.subtitle,
                style: WarmCounterTypography.bodyMedium.copyWith(
                  color: WarmCounterColors.lightSecondaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WarmCounterSpacing.space24),

              // 4 PIN Dots Indicator
              _buildPinDots(),
              const SizedBox(height: WarmCounterSpacing.space16),

              // Error or Status Message
              _buildStatusFeedback(),
              const SizedBox(height: WarmCounterSpacing.space24),

              // On-Screen Touch Numpad
              PinNumpad(
                isEnabled: !_isAuthenticating,
                onDigitPressed: _handleDigit,
                onClearPressed: _handleClear,
                onBackspacePressed: _handleBackspace,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
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
        children: List.generate(4, (index) {
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
