import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'l10n/l10n.dart';

class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.scanQrTitle)),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final rawValue = barcode.rawValue;
            if (rawValue == null || rawValue.isEmpty) {
              continue;
            }
            Navigator.of(context).pop(rawValue);
            break;
          }
        },
      ),
    );
  }
}
