import 'package:flutter/material.dart';

import 'data/legal_content.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(document.titleTh),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'อัปเดตล่าสุด: ${document.updatedAtLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            document.bodyTh,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.55,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}
