import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
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
        return L10n.workflowShopReady;
      case RiderOrderWorkflowStep.scanAtShop:
        return L10n.workflowArrivedShop;
      case RiderOrderWorkflowStep.goToCustomer:
        return L10n.workflowDeliveryStarted;
      case RiderOrderWorkflowStep.photoProof:
        return L10n.workflowArrivedCustomer;
    }
  }

  String _bodyForStep(RiderOrderWorkflowStep step) {
    switch (step) {
      case RiderOrderWorkflowStep.shopReady:
        return L10n.workflowGoPickupShop;
      case RiderOrderWorkflowStep.scanAtShop:
        return L10n.workflowScanQrPickup;
      case RiderOrderWorkflowStep.goToCustomer:
        return L10n.workflowDeliverToCustomer;
      case RiderOrderWorkflowStep.photoProof:
        return L10n.workflowPhotoProof;
    }
  }

  List<Widget> _actionsForStep(BuildContext context) {
    switch (step) {
      case RiderOrderWorkflowStep.shopReady:
        return [
          TextButton(
            onPressed: () => onAction(RiderOrderWorkflowAction.later),
            child: Text(L10n.laterAction),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openShopMap),
            icon: const Icon(Icons.store_mall_directory_outlined),
            label: Text(L10n.shopMap),
          ),
          FilledButton(
            onPressed: () => onAction(RiderOrderWorkflowAction.goToShopNow),
            child: Text(L10n.goPickupNow),
          ),
        ];
      case RiderOrderWorkflowStep.scanAtShop:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.close),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openShopMap),
            icon: const Icon(Icons.store_mall_directory_outlined),
            label: Text(L10n.shopMap),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.scanQr),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(L10n.scanQr),
          ),
        ];
      case RiderOrderWorkflowStep.goToCustomer:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.close),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.capturePhoto),
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(L10n.photoOnArrival),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openCustomerMap),
            icon: const Icon(Icons.map_outlined),
            label: Text(L10n.customerMap),
          ),
        ];
      case RiderOrderWorkflowStep.photoProof:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.close),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.openCustomerMap),
            icon: const Icon(Icons.map_outlined),
            label: Text(L10n.customerMap),
          ),
          FilledButton.icon(
            onPressed: () => onAction(RiderOrderWorkflowAction.capturePhoto),
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(L10n.takePhoto),
          ),
        ];
    }
  }
}
