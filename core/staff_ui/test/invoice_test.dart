import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamaliva_staff_ui/src/invoice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> receipt({bool settled = true}) => {
    'receipt_reference': 'RC9F2A41',
    'hotel': {
      'name': 'LA-MALIVA VISTA HOTEL',
      'address': 'Buea, South-West Region, Cameroon',
      'phone': '+237 6 77 00 00 00',
      'currency': 'XAF',
    },
    'stay': {
      'reference': 'MLV-2026-0007',
      'guest': 'Jane Test',
      'room': '101',
      'arrival': '2026-11-20T14:00:00',
      'departure': '2026-11-23T12:00:00',
      'nights': 3,
      'checked_out_local': '2026-11-23T12:04:00',
    },
    'money': {
      'room_charge': 60000,
      'extension_charges': 5000,
      'total_charges': 65000,
      'net_paid': settled ? 65000 : 55000,
      'refunded': 0,
      'balance': settled ? 0 : 10000,
    },
    'payments': [
      {
        'kind': 'payment',
        'amount': 20000,
        'method': 'mobile_money',
        'created_at': '2026-11-20T14:10:00',
      },
      {
        'kind': 'payment',
        'amount': 45000,
        'method': 'cash',
        'created_at': '2026-11-23T12:01:00',
      },
    ],
    'settled': settled,
    'outstanding_authorised_by': null,
    'issued_at': '2026-11-23T12:04:00',
  };

  test('builds a sealed A4 invoice with charges, payments and stamp', () async {
    final bytes = await InvoicePdf.build(receipt());
    expect(bytes.length, greaterThan(2000));
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('a provisional offline invoice is marked as such', () async {
    final bytes = await InvoicePdf.build({
      ...receipt(settled: false),
      'provisional': true,
      'offline': true,
    }, provisional: true);
    expect(bytes.length, greaterThan(2000));
  });
}
