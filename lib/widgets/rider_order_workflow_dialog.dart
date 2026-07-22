import 'package:flutter/material.dart';

import '../services/rider_order_workflow_service.dart';

class RiderOrderWorkflowDialog extends StatelessWidget {
  const RiderOrderWorkflowDialog({
    super.key,
    required this.step,
    required this.orderCodeLabel,
    required this.shopName,
    required this.onAction,
  });

  final RiderOrderWorkflowStep step;
  final String orderCodeLabel;
  final String shopName;
  final ValueChanged<RiderOrderWorkflowAction> onAction;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titleForStep(step)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (orderCodeLabel.isNotEmpty)
            Text(
              orderCodeLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          if (shopName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              shopName,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
          const SizedBox(height: 12),
          Text(_bodyForStep(step)),
        ],
      ),
      actions: _actionsForStep(context),
    );
  }

  String _titleForStep(RiderOrderWorkflowStep step) {
    switch (step) {
      case RiderOrderWorkflowStep.shopReady:
        return 'ร้านพร้อมส่งแล้ว';
      case RiderOrderWorkflowStep.scanAtShop:
        return 'ถึงร้านแล้ว';
      case RiderOrderWorkflowStep.goToCustomer:
        return 'เริ่มจัดส่งแล้ว';
      case RiderOrderWorkflowStep.photoProof:
        return 'ถึงลูกค้าแล้ว';
    }
  }

  String _bodyForStep(RiderOrderWorkflowStep step) {
    switch (step) {
      case RiderOrderWorkflowStep.shopReady:
        return 'ไปรับสินค้าที่ร้านได้แล้ว';
      case RiderOrderWorkflowStep.scanAtShop:
        return 'สแกน QR ออเดอร์เพื่อยืนยันรับสินค้าจากร้าน';
      case RiderOrderWorkflowStep.goToCustomer:
        return 'นำสินค้าไปส่งลูกค้าตามแผนที่';
      case RiderOrderWorkflowStep.photoProof:
        return 'ถ่ายรูปยืนยันการส่งถึงมือลูกค้า';
    }
  }

  List<Widget> _actionsForStep(BuildContext context) {
    switch (step) {
      case RiderOrderWorkflowStep.shopReady:
        return [
          TextButton(
            onPressed: () => onAction(RiderOrderWorkflowAction.later),
            child: const Text('ทีหลัง'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openShopMap),
            icon: const Icon(Icons.store_mall_directory_outlined),
            label: const Text('แผนที่ร้าน'),
          ),
          FilledButton(
            onPressed: () => onAction(RiderOrderWorkflowAction.goToShopNow),
            child: const Text('ไปรับเลย'),
          ),
        ];
      case RiderOrderWorkflowStep.scanAtShop:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openShopMap),
            icon: const Icon(Icons.store_mall_directory_outlined),
            label: const Text('แผนที่ร้าน'),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.scanQr),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('สแกน QR'),
          ),
        ];
      case RiderOrderWorkflowStep.goToCustomer:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.capturePhoto),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('ถ่ายรูปเมื่อถึง'),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openCustomerMap),
            icon: const Icon(Icons.map_outlined),
            label: const Text('แผนที่ลูกค้า'),
          ),
        ];
      case RiderOrderWorkflowStep.photoProof:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openCustomerMap),
            icon: const Icon(Icons.map_outlined),
            label: const Text('แผนที่ลูกค้า'),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.capturePhoto),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('ถ่ายรูป'),
          ),
        ];
    }
  }
}
