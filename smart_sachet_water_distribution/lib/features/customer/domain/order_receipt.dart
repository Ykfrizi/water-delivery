import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:smart_sachet_water_distribution/app/brand.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';

/// Builds and shares a printable PDF receipt for a customer order.
class OrderReceipt {
  OrderReceipt._();

  static Future<void> share(Map<String, dynamic> order) async {
    final doc = await buildPdf(order);
    final number =
        (order['order_number'] ??
                order['orderNumber'] ??
                order['id'] ??
                'order')
            .toString();
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'water-delivery-receipt-$number.pdf',
    );
  }

  static Future<void> preview(Map<String, dynamic> order) async {
    final doc = await buildPdf(order);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static Future<pw.Document> buildPdf(Map<String, dynamic> order) async {
    final number =
        (order['order_number'] ?? order['orderNumber'] ?? order['id'] ?? '—')
            .toString();
    final status = (order['status'] ?? '—').toString();
    final created = (order['created_at'] ?? order['placed_at'] ?? '')
        .toString();
    final lines = orderLineItems(order);
    final totals =
        order['totals_by_currency'] ?? order['totals'] ?? order['total'];

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            AppBrand.name,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF1565C0),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Order receipt', style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 16),
          pw.Text('Order #$number'),
          pw.Text('Status: $status'),
          if (created.isNotEmpty) pw.Text('Placed: $created'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Items',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          if (lines.isEmpty)
            pw.Text('No line items')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Item', 'Qty', 'Price'],
              data: [
                for (final line in lines)
                  [
                    orderLineTitle(line),
                    (orderLineQty(line) ?? ''),
                    orderLinePrice(line) ?? '',
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Totals',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 6),
          pw.Text(_totalsLabel(totals)),
          pw.SizedBox(height: 24),
          pw.Text(
            'Thank you for ordering with Water Delivery.',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc;
  }

  static String _totalsLabel(dynamic totals) {
    try {
      return prettyTotals(totals);
    } catch (e) {
      debugPrint('$e');
      if (totals is num) return formatMoney(totals);
      return totals?.toString() ?? '—';
    }
  }
}
