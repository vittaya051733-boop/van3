import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สแกนคิวอาร์โค้ด')),
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