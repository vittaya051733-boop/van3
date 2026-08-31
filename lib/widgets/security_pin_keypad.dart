import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// On-screen numeric keypad for 6-digit security PIN entry.
class SecurityPinKeypad extends StatefulWidget {
  const SecurityPinKeypad({
    super.key,
    this.length = 6,
    this.enabled = true,
    this.onChanged,
    this.onCompleted,
    this.controller,
  });

  final int length;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final TextEditingController? controller;

  @override
  State<SecurityPinKeypad> createState() => SecurityPinKeypadState();
}

class SecurityPinKeypadState extends State<SecurityPinKeypad> {
  String _pin = '';

  String get pin => _pin;

  void clear() {
    _setPin('');
  }

  void _setPin(String value) {
    final trimmed = value.length <= widget.length
        ? value
        : value.substring(0, widget.length);
    setState(() => _pin = trimmed);
    widget.controller?.text = trimmed;
    widget.onChanged?.call(trimmed);
    if (trimmed.length == widget.length) {
      widget.onCompleted?.call(trimmed);
    }
  }

  void _appendDigit(String digit) {
    if (!widget.enabled || _pin.length >= widget.length) {
      return;
    }
    _setPin('$_pin$digit');
  }

  void _backspace() {
    if (!widget.enabled || _pin.isEmpty) {
      return;
    }
    _setPin(_pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PinDots(filled: _pin.length, length: widget.length),
        const SizedBox(height: 28),
        _KeypadGrid(
          enabled: widget.enabled,
          onDigit: _appendDigit,
          onBackspace: _backspace,
        ),
      ],
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled, required this.length});

  final int filled;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (index) {
        final isFilled = index < filled;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? AppColors.accent : Colors.transparent,
            border: Border.all(
              color: isFilled ? AppColors.accent : Colors.black26,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

class _KeypadGrid extends StatelessWidget {
  const _KeypadGrid({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          if (rowIndex > 0) const SizedBox(height: 12),
          Row(
            children: [
              for (var colIndex = 0; colIndex < rows[rowIndex].length; colIndex++) ...[
                if (colIndex > 0) const SizedBox(width: 12),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.35,
                    child: _buildKey(rows[rowIndex][colIndex]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildKey(String key) {
    if (key.isEmpty) {
      return const SizedBox.shrink();
    }
    if (key == '⌫') {
      return _KeypadKey(
        enabled: enabled,
        label: key,
        isAction: true,
        onTap: onBackspace,
      );
    }
    return _KeypadKey(
      enabled: enabled,
      label: key,
      onTap: () => onDigit(key),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.isAction = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool isAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: isAction
              ? Icon(
                  Icons.backspace_outlined,
                  color: enabled ? AppColors.accent : Colors.black26,
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: enabled ? Colors.black87 : Colors.black26,
                  ),
                ),
        ),
      ),
    );
  }
}
