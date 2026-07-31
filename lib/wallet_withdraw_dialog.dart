import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WalletWithdrawDialog extends StatefulWidget {
  const WalletWithdrawDialog({
    super.key,
    required this.actorType,
  });

  final String actorType;

  @override
  State<WalletWithdrawDialog> createState() => _WalletWithdrawDialogState();
}

class _WalletWithdrawDialogState extends State<WalletWithdrawDialog> {
  static const double _minWithdrawAmount = 30;

  final TextEditingController _customAmountController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  double _availableBalance = 0;
  double? _selectedAmount;
  String? _bankLabel;
  String? _accountName;
  bool _hasBankProfile = false;
  String? _loadError;

  List<double> get _presets {
    final presets = <double>[100, 500, 1000];
    if (_availableBalance >= _minWithdrawAmount &&
        !presets.contains(_availableBalance)) {
      presets.add(_availableBalance);
    }
    return presets.where((value) => value <= _availableBalance).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> _loadBalance() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final result = await _functions
          .httpsCallable('getWithdrawableBalance')
          .call(<String, dynamic>{'actorType': widget.actorType});
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};

      if (!mounted) {
        return;
      }

      setState(() {
        _availableBalance =
            (data['availableBalance'] as num?)?.toDouble() ?? 0;
        _bankLabel = data['bankLabel']?.toString();
        _accountName = data['accountName']?.toString();
        _hasBankProfile = data['hasBankProfile'] == true;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.message ?? 'โหลดยอดถอนไม่สำเร็จ';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'โหลดยอดถอนไม่สำเร็จ: $error';
        _loading = false;
      });
    }
  }

  void _selectPreset(double amount) {
    setState(() {
      _selectedAmount = amount.clamp(0, _availableBalance);
      _customAmountController.text = '';
    });
  }

  void _selectAll() {
    if (_availableBalance < _minWithdrawAmount) {
      return;
    }
    _selectPreset(_availableBalance);
  }

  void _onCustomAmountChanged(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '').trim());
    setState(() {
      if (parsed == null || parsed <= 0) {
        _selectedAmount = null;
        return;
      }
      _selectedAmount = parsed > _availableBalance ? _availableBalance : parsed;
      if (parsed > _availableBalance) {
        final text = _availableBalance.toStringAsFixed(2);
        _customAmountController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
  }

  double? get _amount => _selectedAmount;

  bool get _canSubmit {
    final amount = _amount;
    if (_submitting || !_hasBankProfile) {
      return false;
    }
    if (amount == null || amount < _minWithdrawAmount) {
      return false;
    }
    return amount <= _availableBalance + 0.001;
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null) {
      _showSnack('กรุณาเลือกจำนวนเงิน');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _functions.httpsCallable('requestOmiseWithdraw').call(
        <String, dynamic>{
          'amount': amount,
          'actorType': widget.actorType,
        },
      );
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      final submittedAmount =
          (data['amount'] as num?)?.toDouble() ?? amount;

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(submittedAmount);
    } on FirebaseFunctionsException catch (error) {
      _showSnack(error.message ?? 'ถอนเงินไม่สำเร็จ');
    } catch (error) {
      _showSnack('ถอนเงินไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ถอนเงิน'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError != null
                ? Text(_loadError!)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ถอนได้ ${_availableBalance.toStringAsFixed(2)} บาท',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_hasBankProfile) ...[
                          Text(
                            'โอนเข้า: $_bankLabel',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (_accountName != null &&
                              _accountName!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _accountName!,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ] else ...[
                          const Text(
                            'กรุณาอัปเดตข้อมูลธนาคารในโปรไฟล์ก่อนถอนเงิน',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'ยอดโอนสุทธิอาจหักค่าธรรมเนียม Omise',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        if (_availableBalance >= _minWithdrawAmount) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in _presets)
                                ChoiceChip(
                                  label: Text(
                                    preset == _availableBalance
                                        ? 'ทั้งหมด'
                                        : preset.toStringAsFixed(0),
                                  ),
                                  selected: _selectedAmount == preset,
                                  onSelected: (_) => _selectPreset(preset),
                                ),
                              if (!_presets.contains(_availableBalance))
                                ChoiceChip(
                                  label: const Text('ทั้งหมด'),
                                  selected:
                                      _selectedAmount == _availableBalance,
                                  onSelected: (_) => _selectAll(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'ระบุจำนวนเงิน (ขั้นต่ำ $_minWithdrawAmount บาท)',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: _onCustomAmountChanged,
                          ),
                        ] else
                          Text(
                            _availableBalance <= 0
                                ? 'ไม่มียอดที่ถอนได้'
                                : 'ยอดถอนขั้นต่ำ $_minWithdrawAmount บาท',
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ยืนยันถอน'),
        ),
      ],
    );
  }
}
