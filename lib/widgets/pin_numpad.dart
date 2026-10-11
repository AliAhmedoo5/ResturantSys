import 'package:flutter/material.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Touch-friendly on-screen numpad optimized for fast 4-digit PIN entry at the counter.
class PinNumpad extends StatelessWidget {
  const PinNumpad({
    super.key,
    required this.onDigitPressed,
    required this.onClearPressed,
    required this.onBackspacePressed,
    this.onSubmitPressed,
    this.isEnabled = true,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onBackspacePressed;
  final VoidCallback? onSubmitPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(['1', '2', '3']),
          const SizedBox(height: WarmCounterSpacing.space12),
          _buildRow(['4', '5', '6']),
          const SizedBox(height: WarmCounterSpacing.space12),
          _buildRow(['7', '8', '9']),
          const SizedBox(height: WarmCounterSpacing.space12),
          _buildBottomRow(),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: digits.map((digit) => _buildNumpadButton(digit)).toList(),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionTile(
          label: 'C',
          tooltip: 'Clear',
          onTap: isEnabled ? onClearPressed : null,
          color: WarmCounterColors.lightDestructive.withValues(alpha: 0.1),
          textColor: WarmCounterColors.lightDestructive,
        ),
        _buildNumpadButton('0'),
        _buildActionTile(
          icon: Icons.backspace_outlined,
          tooltip: 'Backspace',
          onTap: isEnabled ? onBackspacePressed : null,
          color: WarmCounterColors.lightPageBackground,
          textColor: WarmCounterColors.lightPrimaryText,
        ),
      ],
    );
  }

  Widget _buildNumpadButton(String digit) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: 88,
        height: 72,
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          border: Border.all(
            color: WarmCounterColors.lightBorder,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          onTap: isEnabled ? () => onDigitPressed(digit) : null,
          child: Center(
            child: Text(
              digit,
              style: WarmCounterTypography.pageHeading.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: WarmCounterColors.lightPrimaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    String? label,
    IconData? icon,
    required String tooltip,
    required VoidCallback? onTap,
    required Color color,
    required Color textColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 88,
          height: 72,
          decoration: BoxDecoration(
            color: color,
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            border: Border.all(
              color: WarmCounterColors.lightBorder,
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            onTap: onTap,
            child: Center(
              child: label != null
                  ? Text(
                      label,
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 26,
                      color: textColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
