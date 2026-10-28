import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../payments/domain/money.dart';

abstract final class ReceiptPdf {
  /// Accept only an immutable, server-issued receipt, never an outbox payment.
  static Future<Uint8List> build(Map<String, dynamic> receipt) async {
    if (receipt['receipt_number'] == null || receipt['snapshot'] is! Map) {
      throw ArgumentError('A finalized server receipt is required');
    }
    final data = Map<String, dynamic>.from(receipt['snapshot'] as Map);
    final currency = data['currency'] as String;
    final doc = pw.Document(
      title: 'GymPro Receipt ${receipt['receipt_number']}',
    );
    final end = DateTime.tryParse(data['end_exclusive'] as String? ?? '')
        ?.subtract(const Duration(days: 1));
    String money(String key) => Money.format(data[key] as int? ?? 0, currency);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Text(
            data['gym_name'] as String,
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('${data['gym_address'] ?? ''}\n${data['gym_phone'] ?? ''}'),
          pw.SizedBox(height: 28),
          pw.Text(
            receipt['status'] == 'voided'
                ? 'VOIDED PAYMENT RECEIPT'
                : 'PAYMENT RECEIPT',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Receipt #${receipt['receipt_number']}  |  Issued ${receipt['created_at']}',
          ),
          pw.Divider(height: 32),
          pw.Text(
            'Member: ${data['member_name']}  (#${data['member_number']})',
          ),
          pw.Text('Package: ${data['package_name'] ?? 'Membership'}'),
          pw.Text(
            'Membership: ${data['start_date'] ?? '-'} to ${end?.toIso8601String().substring(0, 10) ?? '-'}',
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Description', 'Amount'],
            data: [
              [
                'Subtotal before discount',
                Money.format(
                  data['subtotal_minor'] as int? ??
                      (data['total_minor'] as int? ?? 0) -
                          (data['tax_minor'] as int? ?? 0),
                  currency,
                ),
              ],
              if ((data['discount_minor'] as int? ?? 0) > 0)
                [
                  'Special discount',
                  Money.format(-(data['discount_minor'] as int), currency),
                ],
              ['Invoice total (including tax)', money('total_minor')],
              ['Tax included', money('tax_minor')],
              ['Payment received', money('paid_minor')],
              ['Balance outstanding', money('balance_minor')],
            ],
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE3F1E9),
            ),
            cellPadding: const pw.EdgeInsets.all(12),
          ),
          pw.SizedBox(height: 24),
          if ((data['discount_minor'] as int? ?? 0) > 0)
            pw.Text('Discount reason: ${data['discount_reason'] ?? ''}'),
          pw.Text(
            'Method: ${data['method']}\nReference: ${data['reference'] ?? ''}\nPayment date: ${data['payment_date']}\nAuthorized issuer: ${RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(data['issuer']?.toString() ?? '') ? 'Authorized team member' : data['issuer'] ?? 'Team member'}',
          ),
          pw.SizedBox(height: 32),
          pw.Text(
            'Verification reference: ${receipt['id']}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            'Thank you for being part of our community.',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
