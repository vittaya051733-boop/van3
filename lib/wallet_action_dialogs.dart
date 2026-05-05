import 'package:flutter/material.dart';

class ReceiveMoneyDialog extends StatelessWidget {
  const ReceiveMoneyDialog({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('รับเงิน'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ให้ลูกค้าสแกน QR หรือกรอก UID ของคุณ'),
          const SizedBox(height: 8),
          SelectableText(uid, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
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
      title: const Text('จ่ายเงิน'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('กรอก UID ปลายทางและจำนวนเงิน'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
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
      title: const Text('โอนเงิน'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('กรอก UID ปลายทางและจำนวนเงิน'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}