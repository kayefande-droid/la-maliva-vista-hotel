import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../offline.dart';
import '../theme.dart';
import '../widgets.dart';

/// The shop till. A sale takes the item off the shelf and banks the money in
/// one step; when the server is away the sale is held on the device and pushed
/// once a manager signs the sync off, exactly like a payment.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late Future<(List<dynamic>, Map<String, dynamic>)> _sales = _load();
  late Future<List<dynamic>> _items = widget.api.inventoryItems();
  String _query = '';
  final _search = TextEditingController();

  Future<(List<dynamic>, Map<String, dynamic>)> _load() =>
      widget.api.shopSales();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _sales = _load();
      _items = widget.api.inventoryItems();
    });
  }

  void _toast(String message, {Color? tone}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: tone));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _items,
      builder: (context, itemsSnap) {
        final loading = itemsSnap.connectionState != ConnectionState.done;
        final all = itemsSnap.data ?? const <dynamic>[];
        final sellable = all
            .where(
              (raw) =>
                  raw is Map &&
                  (raw['sale_price'] as num?) != null &&
                  (raw['sale_price'] as num) > 0 &&
                  (raw['quantity'] as num? ?? 0) > 0,
            )
            .where(
              (raw) =>
                  _query.isEmpty ||
                  '${(raw as Map)['name']} ${raw['category']}'
                      .toLowerCase()
                      .contains(_query),
            )
            .toList();

        return RefreshIndicator(
          color: c(LamalivaColors.orangeMid),
          onRefresh: () async {
            _reload();
            await _items;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.xl,
            ),
            children: [
              FutureBuilder<(List<dynamic>, Map<String, dynamic>)>(
                future: _sales,
                builder: (context, snap) {
                  final totals = snap.data?.$2 ?? const <String, dynamic>{};
                  return Reveal(
                    child: Panel(
                      padding: const EdgeInsets.all(LamalivaSpace.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Till today', style: T.label),
                                const SizedBox(height: LamalivaSpace.xxs),
                                Text(
                                  formatMoney(totals['revenue']),
                                  style: T.figure,
                                ),
                                const SizedBox(height: LamalivaSpace.xxs),
                                Text(
                                  '${totals['sales'] ?? 0} sale'
                                  '${(totals['sales'] ?? 0) == 1 ? '' : 's'}'
                                  '  ·  cash, momo or transfer',
                                  style: T.micro,
                                ),
                              ],
                            ),
                          ),
                          GhostButton(
                            label: 'Refresh',
                            icon: Icons.refresh,
                            onPressed: _reload,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: LamalivaSpace.md),
              Reveal(
                delay: const Duration(milliseconds: 60),
                child: Panel(
                  title: 'Sell from the shelf',
                  trailing: SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Find an item',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  child: loading
                      ? const LoadingPanel(rows: 4)
                      : itemsSnap.hasError
                      ? ErrorPanel(
                          message: itemsSnap.error.toString(),
                          onRetry: _reload,
                        )
                      : sellable.isEmpty
                      ? EmptyPanel(
                          title: all.isEmpty
                              ? 'No stock recorded'
                              : 'Nothing to sell yet',
                          body: all.isEmpty
                              ? 'Add food and drinks to the stock room first.'
                              : 'An administrator sets a selling price on a stock item; '
                                    'items priced and in stock appear here.',
                          icon: Icons.storefront_outlined,
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < sellable.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  color: c(LamalivaColors.line),
                                  height: 1,
                                ),
                              _SellableRow(
                                item: (sellable[i] as Map)
                                    .cast<String, dynamic>(),
                                onSell: () => _sell(
                                  (sellable[i] as Map).cast<String, dynamic>(),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: LamalivaSpace.md),
              Reveal(
                delay: const Duration(milliseconds: 110),
                child: Panel(
                  title: "Today's sales",
                  child: FutureBuilder<(List<dynamic>, Map<String, dynamic>)>(
                    future: _sales,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const LoadingPanel(rows: 3);
                      }
                      if (snap.hasError) {
                        return ErrorPanel(
                          message: snap.error.toString(),
                          onRetry: _reload,
                        );
                      }
                      final rows = snap.data?.$1 ?? const [];
                      if (rows.isEmpty) {
                        return const EmptyPanel(
                          title: 'No sales today yet',
                          body:
                              'Every bottle and plate sold is listed here as it happens.',
                          icon: Icons.receipt_long_outlined,
                        );
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0)
                              Divider(color: c(LamalivaColors.line), height: 1),
                            _SaleRow(
                              sale: (rows[i] as Map).cast<String, dynamic>(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sell(Map<String, dynamic> item) async {
    final price = (item['sale_price'] as num?)?.toDouble() ?? 0;
    final result = await showModalBottomSheet<_SaleDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SaleSheet(item: item, price: price),
    );
    if (result == null || !mounted) return;

    final body = <String, dynamic>{
      'item_id': item['id'],
      'quantity': result.quantity,
      'unit_price': result.unitPrice,
      'method': result.method,
      'reference': 'SALE-${DateTime.now().microsecondsSinceEpoch}',
    };
    try {
      await widget.api.recordSale(
        itemId: item['id'] as int,
        quantity: result.quantity,
        unitPrice: result.unitPrice,
        method: result.method,
        reference: body['reference'] as String,
      );
      _reload();
      _toast(
        '${result.quantity} × ${item['name']} — '
        '${formatMoney(result.quantity * result.unitPrice)} banked.',
      );
    } on ApiException catch (error) {
      if (error.offline) {
        final held = await holdOfflineAction(
          context,
          api: widget.api,
          path: '/shop/sales',
          body: body,
          label:
              'Sale of ${result.quantity} × ${item['name']} '
              '(${formatMoney(result.quantity * result.unitPrice)})',
        );
        if (held && mounted) _reload();
        return;
      }
      _toast(error.message, tone: c(LamalivaColors.danger));
    }
  }
}

class _SellableRow extends StatelessWidget {
  const _SellableRow({required this.item, required this.onSell});

  final Map<String, dynamic> item;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final stock = (item['quantity'] as num?)?.toDouble() ?? 0;
    final price = (item['sale_price'] as num?)?.toDouble() ?? 0;
    return HoverRow(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LamalivaSpace.sm,
          vertical: LamalivaSpace.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c(LamalivaColors.creamDeep),
                borderRadius: BorderRadius.circular(LamalivaShape.card),
              ),
              child: Icon(
                _iconFor('${item['category']}'),
                size: 18,
                color: c(LamalivaColors.inkMuted),
              ),
            ),
            const SizedBox(width: LamalivaSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name']}',
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_compact(stock)} ${item['unit']} left'
                    '  ·  ${item['category']}',
                    style: T.micro,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LamalivaSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(price),
                  style: T.numeral.copyWith(fontWeight: FontWeight.w700),
                ),
                Text('each', style: T.micro),
              ],
            ),
            const SizedBox(width: LamalivaSpace.sm),
            GhostButton(
              label: 'Sell',
              icon: Icons.shopping_bag_outlined,
              onPressed: onSell,
            ),
          ],
        ),
      ),
    );
  }

  static String _compact(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  static IconData _iconFor(String category) {
    final c = category.toLowerCase();
    if (c.contains('drink') || c.contains('bever'))
      return Icons.local_drink_outlined;
    if (c.contains('food') || c.contains('kitchen'))
      return Icons.restaurant_outlined;
    if (c.contains('clean')) return Icons.cleaning_services_outlined;
    return Icons.inventory_2_outlined;
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale});

  final Map<String, dynamic> sale;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse('${sale['created_at']}')?.toLocal();
    final clock = at == null
        ? '—'
        : '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale['item_name']}  ×  ${_compact(sale['quantity'])}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$clock  ·  ${sale['method']}'
                  '${sale['reference'] == null ? '' : '  ·  ${sale['reference']}'}',
                  style: T.micro,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            formatMoney(sale['total']),
            style: T.numeral.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  static String _compact(Object? value) {
    final number = num.tryParse('${value ?? 0}') ?? 0;
    return number % 1 == 0
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }
}

class _SaleDraft {
  const _SaleDraft({
    required this.quantity,
    required this.unitPrice,
    required this.method,
  });

  final int quantity;
  final num unitPrice;
  final String method;
}

class _SaleSheet extends StatefulWidget {
  const _SaleSheet({required this.item, required this.price});

  final Map<String, dynamic> item;
  final double price;

  @override
  State<_SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<_SaleSheet> {
  int _quantity = 1;
  String _method = 'cash';
  late final TextEditingController _price = TextEditingController(
    text: widget.price.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  double get _unitPrice => double.tryParse(_price.text.trim()) ?? widget.price;

  @override
  Widget build(BuildContext context) {
    final stock = (widget.item['quantity'] as num?)?.toInt() ?? 0;
    final unit = '${widget.item['unit'] ?? 'unit'}';
    final total = _unitPrice * _quantity;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LamalivaShape.panel),
          ),
        ),
        padding: const EdgeInsets.all(LamalivaSpace.lg),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sell ${widget.item['name']}', style: T.panelTitle),
              const SizedBox(height: LamalivaSpace.xxs),
              Text(
                '$stock $unit${stock == 1 ? '' : 's'} on the shelf',
                style: T.micro,
              ),
              const SizedBox(height: LamalivaSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price each (XAF)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.md),
                  _Stepper(
                    value: _quantity,
                    max: math.max(stock, 1),
                    onChanged: (v) => setState(() => _quantity = v),
                  ),
                ],
              ),
              const SizedBox(height: LamalivaSpace.md),
              Wrap(
                spacing: LamalivaSpace.xs,
                children: [
                  for (final method in const ['cash', 'momo', 'transfer'])
                    ChoiceChip(
                      label: Text(
                        method == 'momo'
                            ? 'Mobile money'
                            : '${method[0].toUpperCase()}${method.substring(1)}',
                      ),
                      selected: _method == method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),
              const SizedBox(height: LamalivaSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: T.label),
                        Text(formatMoney(total), style: T.figure),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: LamalivaSpace.xs),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _SaleDraft(
                        quantity: _quantity,
                        unitPrice: _unitPrice,
                        method: _method,
                      ),
                    ),
                    child: const Text('Record sale'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: c(LamalivaColors.line)),
        borderRadius: BorderRadius.circular(LamalivaShape.input),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: T.numeral.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}
