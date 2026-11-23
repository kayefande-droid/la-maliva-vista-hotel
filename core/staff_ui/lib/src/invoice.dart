import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:lamaliva_design/lamaliva_design.dart';

/// The checkout invoice, as the guest receives it.
///
/// One A4 page: the hotel's masthead, the stay, every charge and payment, and
/// the official stamp — the logo sealed in a circular ink mark that only a
/// closed stay earns. The same data draws the on-screen receipt, so the paper
/// and the screen can never disagree.
class InvoicePdf {
  const InvoicePdf._();

  static const _navy = PdfColor.fromInt(0xFF0B1930);
  static const _navySoft = PdfColor.fromInt(0xFF1B3257);
  static const _orange = PdfColor.fromInt(0xFFE87A2B);
  static const _cream = PdfColor.fromInt(0xFFFAF6EF);
  static const _creamDeep = PdfColor.fromInt(0xFFF2EADC);
  static const _ink = PdfColor.fromInt(0xFF111826);
  static const _muted = PdfColor.fromInt(0xFF5A6579);
  static const _faint = PdfColor.fromInt(0xFF8B95A7);
  static const _line = PdfColor.fromInt(0xFFDDD3C4);
  static const _stampInk = PdfColor.fromInt(0xFF1F3A63);

  static Future<Uint8List> build(
    Map<String, dynamic> receipt, {
    bool provisional = false,
  }) async {
    final hotel = _map(receipt['hotel']);
    final stay = _map(receipt['stay']);
    final money = _map(receipt['money']);
    final payments = (receipt['payments'] as List?) ?? const [];
    final currency = (hotel['currency'] ?? 'XAF').toString();
    final settled =
        receipt['settled'] == true || _num(money['balance']) <= 0.001;
    final authorised = receipt['outstanding_authorised_by'] != null;
    final reference = (receipt['receipt_reference'] ?? '—').toString();
    final issued = _parse(receipt['issued_at']);
    final checkout = _parse(
      stay['checked_out_local'] ?? stay['expected_checkout_local'],
    );
    final roomCharge = _num(money['room_charge']);
    final extensions = _num(money['extension_charges']);
    final total = _num(
      money['total_charges'] ?? money['total'] ?? (roomCharge + extensions),
    );
    final paid = _num(money['net_paid'] ?? money['paid']);
    final refunded = _num(money['refunded']);
    final balance = _num(money['balance']);
    final nights = (stay['nights'] as num?)?.toInt() ?? 1;
    final rate = nights > 0 ? roomCharge / nights : roomCharge;

    final base = await _font('assets/fonts/Inter.ttf');
    final logo = await _logo();

    final doc = pw.Document(
      title: 'Invoice $reference — ${hotel['name'] ?? 'La Maliva Vista Hotel'}',
      author: (hotel['name'] ?? 'La Maliva Vista Hotel').toString(),
      subject: 'Hotel invoice and checkout receipt',
    );

    pw.Widget label(String text) => pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 7.2,
        letterSpacing: 1.5,
        fontWeight: pw.FontWeight.bold,
        color: _muted,
      ),
    );

    pw.Widget line(String left, String right, {bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.2),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  left,
                  style: pw.TextStyle(
                    fontSize: 9.4,
                    color: strong ? _ink : _muted,
                    fontWeight: strong ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
              pw.Text(
                right,
                style: pw.TextStyle(
                  fontSize: 9.6,
                  color: _ink,
                  fontWeight: strong
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        theme: pw.ThemeData.withFont(
          base: base ?? pw.Font.helvetica(),
          bold: base ?? pw.Font.helveticaBold(),
          italic: base ?? pw.Font.helveticaOblique(),
          boldItalic: base ?? pw.Font.helveticaBoldOblique(),
          fontFallback: [pw.Font.helvetica()],
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${hotel['name'] ?? 'LA-MALIVA VISTA HOTEL'}'
                  '${(hotel['address'] ?? '').toString().isEmpty ? '' : ' · ${hotel['address']}'}'
                  '${(hotel['phone'] ?? '').toString().isEmpty ? '' : ' · ${hotel['phone']}'}',
                  style: const pw.TextStyle(fontSize: 7.4, color: _faint),
                ),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.4, color: _faint),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          // ---------------- Masthead ----------------
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 46,
                    height: 46,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      shape: pw.BoxShape.circle,
                    ),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        (hotel['name'] ?? 'LA-MALIVA VISTA HOTEL')
                            .toString()
                            .toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 20,
                          letterSpacing: 1.4,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'A TASTE OF PARADISE ABOVE THE COAST',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          letterSpacing: 2.1,
                          color: PdfColor.fromInt(0xFFEEC37A),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: _orange,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        provisional ? 'PROVISIONAL' : 'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.6,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      reference,
                      style: const pw.TextStyle(
                        fontSize: 8.2,
                        letterSpacing: 0.6,
                        color: PdfColor.fromInt(0xFFA5E1F2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),

          // ---------------- Guest / stay ----------------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 11,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(13),
                  decoration: pw.BoxDecoration(
                    color: _cream,
                    borderRadius: pw.BorderRadius.circular(9),
                    border: pw.Border.all(color: _creamDeep),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      label('Billed to'),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        (stay['guest'] ?? 'Guest').toString(),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Room ${stay['room'] ?? '—'} · '
                        '${stay['reference'] ?? '—'}',
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        children: [
                          _fact('Arrival', _date(stay['arrival'])),
                          pw.SizedBox(width: 18),
                          _fact('Departure', _date(stay['departure'])),
                          pw.SizedBox(width: 18),
                          _fact('Nights', '$nights'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 9,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(13),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(9),
                    border: pw.Border.all(color: _line),
                  ),
                  child: pw.Column(
                    children: [
                      line('Issued', _dateTime(issued)),
                      line('Checked out', _dateTime(checkout)),
                      line('Reference', reference, strong: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---------------- Charges ----------------
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            headerStyle: pw.TextStyle(
              fontSize: 8.4,
              letterSpacing: 1.1,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9.4, color: _ink),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7.5,
            ),
            headerPadding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            oddRowDecoration: const pw.BoxDecoration(color: _cream),
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2.2),
            },
            headers: ['DESCRIPTION', 'QTY', 'RATE', 'AMOUNT'],
            data: [
              [
                'Accommodation — Room ${stay['room'] ?? '—'}',
                '$nights night${nights == 1 ? '' : 's'}',
                _money(rate, currency),
                _money(roomCharge, currency),
              ],
              if (extensions > 0)
                ['Approved extensions', '—', '—', _money(extensions, currency)],
            ],
          ),
          pw.SizedBox(height: 14),

          // ---------------- Payments + totals + stamp ----------------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 12,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    label('Payments received'),
                    pw.SizedBox(height: 6),
                    if (payments.isEmpty)
                      pw.Text(
                        provisional
                            ? 'No payment taken on this device.'
                            : 'No payment has been recorded for this stay.',
                        style: const pw.TextStyle(fontSize: 9, color: _muted),
                      )
                    else
                      ...payments.map((raw) {
                        final p = _map(raw);
                        final refund = '${p['kind']}' == 'refund';
                        return pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 4.6),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: _creamDeep,
                                width: 0.6,
                              ),
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Expanded(
                                flex: 5,
                                child: pw.Text(
                                  _method(p['method']),
                                  style: const pw.TextStyle(
                                    fontSize: 9,
                                    color: _ink,
                                  ),
                                ),
                              ),
                              pw.Expanded(
                                flex: 5,
                                child: pw.Text(
                                  _dateTime(_parse(p['created_at'])),
                                  style: const pw.TextStyle(
                                    fontSize: 8.6,
                                    color: _muted,
                                  ),
                                ),
                              ),
                              pw.SizedBox(width: 8),
                              pw.Text(
                                '${refund ? '−' : ''}${_money(_num(p['amount']), currency)}',
                                style: pw.TextStyle(
                                  fontSize: 9.2,
                                  color: refund ? _orange : _ink,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    pw.SizedBox(height: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: _cream,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Thank you for staying with us.',
                            style: pw.TextStyle(
                              fontSize: 12.5,
                              fontStyle: pw.FontStyle.italic,
                              color: _navySoft,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'This invoice is computer-generated and valid with the official stamp of '
                            '${hotel['name'] ?? 'La Maliva Vista Hotel'}.',
                            style: const pw.TextStyle(
                              fontSize: 7.6,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 10,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(13, 12, 13, 14),
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(9),
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Column(
                        children: [
                          line('Total charges', _money(total, currency)),
                          line('Paid', _money(paid, currency)),
                          if (refunded > 0)
                            line('Refunded', '−${_money(refunded, currency)}'),
                          pw.Container(
                            margin: const pw.EdgeInsets.symmetric(vertical: 6),
                            height: 0.6,
                            color: _line,
                          ),
                          line(
                            balance > 0.001
                                ? (authorised
                                      ? 'Authorised balance'
                                      : 'Balance due')
                                : 'Settled',
                            balance > 0.001
                                ? _money(balance, currency)
                                : 'Paid in full',
                            strong: true,
                          ),
                          pw.SizedBox(height: 8),
                          _stamp(
                            settled: settled,
                            provisional: provisional,
                            authorised: authorised,
                            reference: reference,
                            issued: issued,
                            logo: logo,
                          ),
                        ],
                      ),
                    ),
                    if (provisional) ...[
                      pw.SizedBox(height: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(9),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFFDF1E3),
                          borderRadius: pw.BorderRadius.circular(7),
                          border: pw.Border.all(color: _orange, width: 0.7),
                        ),
                        child: pw.Text(
                          'Held on this device while the hotel server was '
                          'unreachable. This invoice is provisional and will be '
                          'replaced by the sealed hotel receipt once a manager '
                          'syncs the checkout.',
                          style: const pw.TextStyle(fontSize: 7.8, color: _ink),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 22),

          // ---------------- Signatures ----------------
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(height: 0.7, color: _line),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Guest signature',
                      style: const pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 60),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(height: 0.7, color: _line),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Authorised signature',
                      style: const pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ---- Official stamp ------------------------------------------------------

  /// The hotel seal: the logo inside a double ink ring, tilted the way a hand
  /// presses a rubber stamp. It carries the outcome — paid, authorised, or
  /// provisional — and the date it was pressed.
  static pw.Widget _stamp({
    required bool settled,
    required bool provisional,
    required bool authorised,
    required String reference,
    required DateTime issued,
    required pw.MemoryImage? logo,
  }) {
    final headline = provisional
        ? 'PENDING SYNC'
        : settled
        ? 'PAID IN FULL'
        : authorised
        ? 'BALANCE AUTHORISED'
        : 'CHECKED OUT';
    return pw.Transform.rotate(
      angle: -0.11,
      child: pw.Center(
        child: pw.Container(
          width: 132,
          height: 132,
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: _stampInk, width: 1.8),
          ),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _stampInk, width: 0.7),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 30,
                    height: 30,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'LA-MALIVA VISTA',
                  style: pw.TextStyle(
                    fontSize: 6.8,
                    letterSpacing: 1.15,
                    fontWeight: pw.FontWeight.bold,
                    color: _stampInk,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'HOTEL · BUEA',
                  style: const pw.TextStyle(
                    fontSize: 5.4,
                    letterSpacing: 1.05,
                    color: _stampInk,
                  ),
                ),
                pw.Container(
                  width: 74,
                  margin: const pw.EdgeInsets.symmetric(vertical: 3),
                  height: 0.6,
                  color: _stampInk,
                ),
                pw.Text(
                  headline,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: provisional ? 7.2 : 8.2,
                    letterSpacing: 0.6,
                    fontWeight: pw.FontWeight.bold,
                    color: _stampInk,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _date(issued),
                  style: const pw.TextStyle(fontSize: 6.2, color: _stampInk),
                ),
                pw.Text(
                  reference,
                  style: const pw.TextStyle(fontSize: 5.6, color: _stampInk),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _fact(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 5.8,
          letterSpacing: 1,
          color: _faint,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 8.4,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    ],
  );

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final data = await rootBundle.load('assets/logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font?> _font(String path) async {
    try {
      final data = await rootBundle.load(path);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  // ---- Shared formatting ---------------------------------------------------

  static Map<String, dynamic> _map(Object? value) =>
      (value as Map?)?.cast<String, dynamic>() ?? const {};

  static double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

  static DateTime _parse(Object? iso) =>
      DateTime.tryParse(iso?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _date(Object? iso) {
    final value = iso is DateTime ? iso : _parse(iso);
    if (value.millisecondsSinceEpoch == 0) return '—';
    return '${value.day.toString().padLeft(2, '0')} '
        '${_months[value.month - 1]} ${value.year}';
  }

  static String _dateTime(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '—';
    final local = value.isUtc ? value.toLocal() : value;
    return '${_date(local)} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// `1 250 000 FCFA` — grouped with the narrow space hotel invoices use.
  static String _money(double value, String currency) {
    final rounded = value.round();
    final negative = rounded < 0;
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u2009');
      buffer.write(digits[i]);
    }
    return '${negative ? '−' : ''}$buffer $currency';
  }

  static String _method(Object? method) {
    switch (method?.toString()) {
      case 'mobile_money':
        return 'Mobile money';
      case 'card':
        return 'Card';
      case 'transfer':
        return 'Transfer';
      case 'cash':
        return 'Cash';
      default:
        return 'Payment';
    }
  }
}

/// Finds the printers attached to this machine and sends the invoice to paper.
///
/// Windows asks the print spooler directly, so a desk printer receives the job
/// the moment the guest is checked out. Android hands the PDF to the system
/// print service through a small platform channel. Neither path ships its own
/// PDF engine, so a hotel PC needs nothing installed but its printer driver.
class InvoicePrinter {
  InvoicePrinter._();

  static const _channel = MethodChannel('lamaliva/print');

  static List<String> _cached = const [];
  static String? _default;

  static List<String> get cached => _cached;

  /// `false` for the PDF/XPS/Fax virtual drivers Windows always lists — they
  /// prompt for a file name, which must never block a checkout.
  static bool _physical(String name) {
    final lower = name.toLowerCase();
    return lower.isNotEmpty &&
        !lower.contains('pdf') &&
        !lower.contains('xps') &&
        !lower.contains('fax') &&
        !lower.contains('onenote');
  }

  /// Asks the OS for its printers and remembers the default physical one.
  static Future<List<String>> discover() async {
    if (!Platform.isWindows) return _cached;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Printer | Select-Object Name,Default | ConvertTo-Json -Compress',
      ], stdoutEncoding: const Utf8Codec()).timeout(const Duration(seconds: 8));
      if (res.exitCode != 0) return _cached;
      final text = '${res.stdout}'.trim();
      if (text.isEmpty) {
        _cached = const [];
        _default = null;
        return _cached;
      }
      final decoded = jsonDecode(text);
      final rows = decoded is List ? decoded : [decoded];
      final printers = <String>[];
      String? defaultPrinter;
      for (final row in rows) {
        if (row is! Map) continue;
        final name = '${row['Name'] ?? ''}';
        if (!_physical(name)) continue;
        printers.add(name);
        if (row['Default'] == true) defaultPrinter = name;
      }
      _cached = List<String>.unmodifiable(printers);
      _default = defaultPrinter ?? (printers.isEmpty ? null : printers.first);
      return _cached;
    } catch (_) {
      return _cached;
    }
  }

  static String _clean(String name) {
    final safe = name.replaceAll(RegExp(r"[^A-Za-z0-9 _-]"), '').trim();
    return safe.isEmpty ? 'invoice' : safe;
  }

  /// Prints [bytes]. Returns the printer that took the job, or `null` when no
  /// physical printer exists or a viewer was opened instead.
  ///
  /// [fallbackToDialog] is false during checkout: a desk with no printer gets
  /// the receipt at once and can print from the sheet when it is ready.
  static Future<String?> print(
    Uint8List bytes, {
    required String jobName,
    bool preferDirect = true,
    bool fallbackToDialog = true,
  }) async {
    if (Platform.isWindows) {
      if (_cached.isEmpty) await discover();
      File? file;
      try {
        final dir = await Directory.systemTemp.createTemp('lamaliva_invoice');
        file = File(
          '${dir.path}${Platform.pathSeparator}${_clean(jobName)}.pdf',
        );
        await file.writeAsBytes(bytes, flush: true);
        final quoted = file.path.replaceAll("'", "''");
        if (preferDirect && _default != null) {
          await Process.run('powershell', [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            "Start-Process -FilePath '$quoted' -Verb Print",
          ]);
          return _default;
        }
        if (!fallbackToDialog) return null;
        await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "Start-Process -FilePath '$quoted'",
        ]);
        return null;
      } catch (_) {
        return null;
      }
    }
    if (Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('printPdf', {
          'bytes': bytes,
          'name': jobName,
        });
        return ok == true ? 'the Android print service' : null;
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    return null;
  }
}

/// The ink seal as it appears in the receipt sheet, matching the printed page.
class InvoiceStamp extends StatelessWidget {
  const InvoiceStamp({
    super.key,
    required this.settled,
    required this.provisional,
    required this.authorised,
    required this.reference,
    required this.issuedOn,
    this.size = 132,
  });

  final bool settled;
  final bool provisional;
  final bool authorised;
  final String reference;
  final String issuedOn;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = _hex(0xFF1F3A63);
    final headline = provisional
        ? 'PENDING SYNC'
        : settled
        ? 'PAID IN FULL'
        : authorised
        ? 'BALANCE AUTHORISED'
        : 'CHECKED OUT';
    return Semantics(
      label: 'Official hotel stamp: $headline, $issuedOn',
      child: Transform.rotate(
        angle: -0.11,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: 1.8),
          ),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 0.7),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logo.png',
                  width: size * 0.22,
                  height: size * 0.22,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) =>
                      SizedBox(width: size * 0.22, height: size * 0.22),
                ),
                const SizedBox(height: 2),
                Text(
                  'LA-MALIVA VISTA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: size * 0.052,
                    letterSpacing: 1.05,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                Text(
                  'HOTEL · BUEA',
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: size * 0.041,
                    letterSpacing: 0.95,
                    color: ink,
                  ),
                ),
                Container(
                  width: size * 0.56,
                  height: 0.6,
                  margin: EdgeInsets.symmetric(vertical: size * 0.022),
                  color: ink,
                ),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: provisional ? size * 0.055 : size * 0.062,
                    letterSpacing: 0.55,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  issuedOn,
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: size * 0.047,
                    color: ink,
                  ),
                ),
                Text(
                  reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: size * 0.042,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _hex(int value) => Color(value);
}

/// Small helper shared by both receipt surfaces.
String invoiceDateLabel(Object? iso) {
  final parsed = DateTime.tryParse(iso?.toString() ?? '');
  if (parsed == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day.toString().padLeft(2, '0')} '
      '${months[parsed.month - 1]} ${parsed.year}';
}
