import 'package:flutter/material.dart';

import 'l10n/l10n.dart';

class ReceiveMoneyDialog extends StatelessWidget {
  const ReceiveMoneyDialog({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.receiveMoney),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L10n.receiveMoneyHint),
          const SizedBox(height: 8),
          SelectableText(uid, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.close),
        ),
      ],
    );
  }
}

class PayMoneyDialog extends StatelessWidget {
  const PayMoneyDialog({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.payMoney),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L10n.payMoneyHint),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.close),
        ),
      ],
    );
  }
}

class TransferMoneyDialog extends StatelessWidget {
  const TransferMoneyDialog({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.transferMoney),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L10n.transferMoneyHint),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.close),
        ),
      ],
    );
  }
}