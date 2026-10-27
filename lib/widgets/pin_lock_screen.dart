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
    this.maxPinLength = 4,
  });

  final Future<bool> Function(String pin) onPinSubmitted;
  final String title;
  final String subtitle;
  final int maxPinLength;

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
    if (_isAuthenticating || _enteredPin.length >= widget.maxPinLength) return;

    final nextPin = _enteredPin + digit;
    setState(() {
      _errorMessage = null;
      _enteredPin = nextPin;
    });

    if (nextPin.length == widget.maxPinLength) {
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
        setState(() {
          _enteredPin = '';
          _isAuthenticating = false;
          _errorMessage = 'PIN rejected. After five failed attempts, wait one minute.';
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
      child: LayoutBuilder(builder: (context, constraints) {
        return Row(children: [
          if (constraints.maxWidth >= 1000)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 48, height: 4, color: StreetFoodMafiaColors.cartelYellow),
                    const SizedBox(height: 24),
                    Text('READY FOR\nRUSH HOUR.', style: WarmCounterTypography.pageHeading.copyWith(
                      fontSize: 48, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                    const SizedBox(height: 20),
                    Text('Your counter. Your kitchen. One place.',
                      style: WarmCounterTypography.body.copyWith(color: StreetFoodMafiaColors.secondaryText)),
                    const SizedBox(height: 40),
                    const Row(children: [
                      Icon(Icons.offline_bolt_outlined, size: 18, color: StreetFoodMafiaColors.cartelYellow),
                      SizedBox(width: 8),
                      Text('Built for the everyday service.'),
                    ]),
                  ],
                ),
              ),
            ),
          Expanded(child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                key: const ValueKey('login_card'),
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: StreetFoodMafiaColors.darkNavy,
                  borderRadius: WarmCounterSpacing.panelBorderRadius,
                  border: Border.all(color: StreetFoodMafiaColors.border),
                ),
                child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Lock Icon & Header
              Container(
                width: 32,
                height: 32,
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
              const SizedBox(height: 8),

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
              const SizedBox(height: 12),

              // PIN Dots Indicator
              _buildPinDots(),
              const SizedBox(height: 8),

              // Reserve the action slot so PIN entry never pushes the keypad away.
              SizedBox(
                height: widget.maxPinLength > 4 ? 48 : 24,
                child: Center(child: widget.maxPinLength > 4 && _enteredPin.length >= 4 && !_isAuthenticating
                  ? ElevatedButton.icon(
                  key: const ValueKey('unlock_pin_button'),
                  onPressed: _isAuthenticating ? null : _submitPin,
                  icon: const Icon(Icons.lock_open_rounded, size: 20),
                  label: const Text('Unlock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: StreetFoodMafiaColors.textOnPrimary,
                    minimumSize: const Size(200, WarmCounterSpacing.touchTargetMin),
                    shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  ) : _buildStatusFeedback()),
              ),
              const SizedBox(height: 8),
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
          )),
        ]);
      }),
    );
  }

  Widget _buildPinDots() {
    final dotCount = _enteredPin.length > widget.maxPinLength ? _enteredPin.length : widget.maxPinLength;
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
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 14,
            height: 14,
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
