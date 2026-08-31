import 'package:cloud_functions/cloud_functions.dart';
import 'package:van3/utils/guarded_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/l10n.dart';

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
  static const double _defaultMinWithdrawAmount = 30;
  static const double _defaultWithdrawFeeBaht = 10;

  final TextEditingController _customAmountController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  double _availableBalance = 0;
  double _minWithdrawAmount = _defaultMinWithdrawAmount;
  double _minGrossWithdrawAmount =
      _defaultMinWithdrawAmount + _defaultWithdrawFeeBaht;
  double _withdrawFeeBaht = _defaultWithdrawFeeBaht;
  double? _selectedAmount;
  String? _bankLabel;
  String? _promptPayLabel;
  String? _accountName;
  bool _hasBankProfile = false;
  bool _hasPromptPayProfile = false;
  String? _loadError;

  List<double> get _presets {
    final presets = <double>[100, 500, 1000];
    if (_availableBalance >= _minGrossWithdrawAmount &&
        !presets.contains(_availableBalance)) {
      presets.add(_availableBalance);
    }
    return presets
        .where((value) => value <= _availableBalance)
        .where((value) => value >= _minGrossWithdrawAmount)
        .toList();
  }

  double? get _netReceive {
    final amount = _amount;
    if (amount == null) {
      return null;
    }
    return (amount - _withdrawFeeBaht).clamp(0, double.infinity);
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

  Future<void> _loadBalance() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final result = await GuardedFunctions.call(
        'getWithdrawableBalance',
        parameters: <String, dynamic>{'actorType': widget.actorType},
      );
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};

      if (!mounted) {
        return;
      }

      setState(() {
        _availableBalance =
            (data['availableBalance'] as num?)?.toDouble() ?? 0;
        _minWithdrawAmount =
            (data['minWithdrawAmount'] as num?)?.toDouble() ??
                _defaultMinWithdrawAmount;
        _withdrawFeeBaht =
            (data['withdrawFeeBaht'] as num?)?.toDouble() ??
                _defaultWithdrawFeeBaht;
        _minGrossWithdrawAmount =
            (data['minGrossWithdrawAmount'] as num?)?.toDouble() ??
                (_minWithdrawAmount + _withdrawFeeBaht);
        _bankLabel = data['bankLabel']?.toString();
        _promptPayLabel = data['promptPayLabel']?.toString();
        _accountName = data['accountName']?.toString();
        _hasBankProfile = data['hasBankProfile'] == true;
        _hasPromptPayProfile = data['hasPromptPayProfile'] == true;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.message ?? L10n.loadWithdrawBalanceFailed;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = L10n.loadWithdrawBalanceFailedWithError(error);
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
    if (_availableBalance < _minGrossWithdrawAmount) {
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

  bool get _hasPayoutProfile => _hasBankProfile || _hasPromptPayProfile;

  bool get _canSubmit {
    final amount = _amount;
    if (_submitting || !_hasPayoutProfile) {
      return false;
    }
    if (amount == null || amount < _minGrossWithdrawAmount) {
      return false;
    }
    return amount <= _availableBalance + 0.001;
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null) {
      _showSnack(L10n.pleaseSelectAmount);
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await GuardedFunctions.call(
        'requestManualWithdraw',
        parameters: <String, dynamic>{
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
      _showSnack(error.message ?? L10n.withdrawFailed);
    } catch (error) {
      _showSnack(L10n.withdrawFailedWithError(error));
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(L10n.withdrawTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadBalance,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(L10n.reloadAgain),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          L10n.withdrawableBalance(_availableBalance),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (_hasPayoutProfile) ...[
                          Text(
                            L10n.registeredPayoutChannels,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          if (_hasPromptPayProfile &&
                              _promptPayLabel != null)
                            Text(
                              L10n.promptPayChannel(_promptPayLabel!),
                              style: const TextStyle(fontSize: 13),
                            ),
                          if (_hasBankProfile && _bankLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              L10n.bankChannel(_bankLabel!),
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
                          ],
                          const SizedBox(height: 8),
                          Text(
                            L10n.withdrawAdminProcessHint,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          if (!_hasPromptPayProfile) ...[
                            const SizedBox(height: 8),
                            Text(
                              L10n.noPromptPayGoProfile,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB45309),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ] else ...[
                          Text(
                            L10n.addPromptPayOrBankInProfile,
                            style: const TextStyle(color: Colors.red, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          L10n.withdrawFeePerTime(_withdrawFeeBaht),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_availableBalance >= _minGrossWithdrawAmount) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in _presets)
                                ChoiceChip(
                                  label: Text(
                                    preset == _availableBalance
                                        ? L10n.all
                                        : preset.toStringAsFixed(0),
                                  ),
                                  selected: _selectedAmount == preset,
                                  onSelected: (_) => _selectPreset(preset),
                                ),
                              if (!_presets.contains(_availableBalance))
                                ChoiceChip(
                                  label: Text(L10n.all),
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
                              labelText: L10n.enterWithdrawAmountHint(_minGrossWithdrawAmount),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: _onCustomAmountChanged,
                          ),
                          if (_netReceive != null && _withdrawFeeBaht > 0) ...[
                            const SizedBox(height: 10),
                            Text(
                              L10n.netReceiveAfterFee(_netReceive!, _withdrawFeeBaht),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ] else
                          Text(
                            _availableBalance <= 0
                                ? L10n.noWithdrawableBalance
                                : L10n.withdrawMinimumHint(
                                    _minWithdrawAmount,
                                    _minGrossWithdrawAmount,
                                  ),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(L10n.cancel),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(L10n.confirmWithdraw),
        ),
      ],
    );
  }
}
