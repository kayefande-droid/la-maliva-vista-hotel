import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Stock on the shelf. Anyone may move stock; only an administrator may create
/// or rewrite an item, and every movement is kept as an append-only ledger.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<dynamic>> _items = widget.api.inventoryItems();
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _items = widget.api.inventoryItems());

  Future<void> _move(Map<String, dynamic> item, String kind) async {
    final quantity = TextEditingController();
    final reason = TextEditingController();
    final unitCost = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LamalivaShape.panel),
        ),
        title: Text(
          kind == 'in' ? 'Add stock' : 'Take stock',
          style: T.screenTitle.copyWith(fontSize: 22),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${item['name']} - ${item['quantity']} ${item['unit']} on hand',
              style: T.bodyMuted,
            ),
            const SizedBox(height: LamalivaSpace.md),
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity (${item['unit']})',
              ),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            if (kind == 'in') ...[
              TextField(
                controller: unitCost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cost of one (optional)',
                  helperText:
                      'Giving the cost keeps the average cost of the shelf right.',
                ),
              ),
              const SizedBox(height: LamalivaSpace.sm),
            ],
            TextField(
              controller: reason,
              decoration: InputDecoration(
                labelText: kind == 'stock_take'
                    ? 'Why are you counting? (required)'
                    : 'Reason (optional)',
                hintText: kind == 'stock_take'
                    ? 'End of month count'
                    : 'Delivery, breakage, transfer',
              ),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            Text(
              'Movements are saved permanently and cannot be edited or removed.',
              style: T.micro,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save movement'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final amount = num.tryParse(quantity.text.trim());
    if (amount == null || amount <= 0) {
      _toast('Enter a quantity greater than zero.');
      return;
    }
    if (kind == 'stock_take' && reason.text.trim().isEmpty) {
      _toast('Say why you counted, so the change can be explained later.');
      return;
    }
    final cost = num.tryParse(unitCost.text.trim());
    try {
      await widget.api.recordMovement(
        item['id'] as int,
        kind: kind,
        quantity: amount,
        reason: reason.text,
        unitCost: kind == 'in' && cost != null && cost >= 0 ? cost : null,
      );
      _reload();
      _toast(switch (kind) {
        'in' => 'Stock added at the new cost.',
        'stock_take' => 'Count saved; the shelf now shows what you counted.',
        _ => 'Stock taken out.',
      });
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _items,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final all = snap.data ?? const <dynamic>[];
        final rows = all.where((raw) {
          if (raw is! Map) return false;
          if (_query.isEmpty) return true;
          return '${raw['name']} ${raw['sku']} ${raw['category']}'
              .toLowerCase()
              .contains(_query);
        }).toList();
        final lowStock = all
            .where((raw) => raw is Map && raw['low_stock'] == true)
            .length;

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
              Wrap(
                spacing: LamalivaSpace.sm,
                runSpacing: LamalivaSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search stock',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  if (lowStock > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LamalivaSpace.sm,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c(
                          LamalivaColors.warningSoft,
                        ).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(LamalivaShape.pill),
                      ),
                      child: Text(
                        '$lowStock item${lowStock == 1 ? '' : 's'} at reorder level',
                        style: T.micro.copyWith(
                          color: c(LamalivaColors.warning),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (widget.api.isAdmin)
                    GhostButton(
                      label: 'Add item',
                      icon: Icons.add,
                      onPressed: () => _addItem(),
                    ),
                ],
              ),
              const SizedBox(height: LamalivaSpace.md),
              if (loading)
                const Panel(child: LoadingPanel(rows: 6))
              else if (snap.hasError)
                Panel(
                  child: ErrorPanel(
                    message: snap.error.toString(),
                    onRetry: _reload,
                  ),
                )
              else if (rows.isEmpty)
                Panel(
                  child: EmptyPanel(
                    title: all.isEmpty
                        ? 'No stock recorded'
                        : 'Nothing matches',
                    body: all.isEmpty
                        ? 'An administrator creates the items; anyone on shift can then move stock in and out.'
                        : 'Try another item name or category.',
                    icon: Icons.inventory_2_outlined,
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.all(LamalivaSpace.xs),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(color: c(LamalivaColors.line), height: 1),
                        Reveal(
                          delay: Duration(milliseconds: (i * 22).clamp(0, 260)),
                          offset: 8,
                          child: _ItemRow(
                            item: rows[i] as Map<String, dynamic>,
                            onAdd: () =>
                                _move(rows[i] as Map<String, dynamic>, 'in'),
                            onTake: () =>
                                _move(rows[i] as Map<String, dynamic>, 'out'),
                            onStockTake: () => _move(
                              rows[i] as Map<String, dynamic>,
                              'stock_take',
                            ),
                            onEdit: widget.api.isAdmin
                                ? () =>
                                      _editItem(rows[i] as Map<String, dynamic>)
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addItem() async {
    final name = TextEditingController();
    final unit = TextEditingController(text: 'unit');
    final quantity = TextEditingController();
    final reorder = TextEditingController();
    final cost = TextEditingController();
    final price = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LamalivaShape.panel),
        ),
        title: Text(
          'New stock item',
          style: T.screenTitle.copyWith(fontSize: 22),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Opening quantity',
                ),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: reorder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reorder level'),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Unit cost (XAF)'),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Selling price (XAF, for the shop till)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create item'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    if (name.text.trim().isEmpty) {
      _toast('An item name is required.');
      return;
    }
    try {
      await widget.api.createItem(
        name: name.text.trim(),
        unit: unit.text.trim().isEmpty ? 'unit' : unit.text.trim(),
        quantity: num.tryParse(quantity.text.trim()) ?? 0,
        reorderLevel: num.tryParse(reorder.text.trim()) ?? 0,
        unitCost: num.tryParse(cost.text.trim()) ?? 0,
        salePrice: num.tryParse(price.text.trim()) ?? 0,
      );
      _reload();
      _toast('Item created.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final reorder = TextEditingController(text: '${item['reorder_level']}');
    final cost = TextEditingController(text: '${item['unit_cost']}');
    final price = TextEditingController(text: '${item['sale_price'] ?? 0}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LamalivaShape.panel),
        ),
        title: Text(
          '${item['name']}',
          style: T.screenTitle.copyWith(fontSize: 22),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reorder,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reorder level'),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit cost (XAF)'),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Selling price (XAF) — 0 hides it from the till',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await widget.api.updateItem(item['id'] as int, {
        'reorder_level': num.tryParse(reorder.text.trim()) ?? 0,
        'unit_cost': num.tryParse(cost.text.trim()) ?? 0,
        'sale_price': num.tryParse(price.text.trim()) ?? 0,
      });
      _reload();
      _toast('Item updated.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onAdd,
    required this.onTake,
    required this.onStockTake,
    this.onEdit,
  });

  final Map<String, dynamic> item;
  final VoidCallback onAdd;
  final VoidCallback onTake;
  final VoidCallback onStockTake;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final low = item['low_stock'] == true;
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
                color: low
                    ? c(LamalivaColors.dangerSoft).withValues(alpha: 0.5)
                    : c(LamalivaColors.creamDeep),
                borderRadius: BorderRadius.circular(LamalivaShape.card),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: low
                    ? c(LamalivaColors.danger)
                    : c(LamalivaColors.inkMuted),
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
                    '${item['sku']}  ·  ${item['category']}  ·  reorder at ${item['reorder_level']}',
                    style: T.micro,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LamalivaSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item['quantity']} ${item['unit']}',
                  style: T.numeral.copyWith(
                    fontWeight: FontWeight.w700,
                    color: low
                        ? c(LamalivaColors.danger)
                        : c(LamalivaColors.navy800),
                  ),
                ),
                Text(
                  (item['sale_price'] as num? ?? 0) > 0
                      ? 'sells ${formatMoney(item['sale_price'])}'
                      : 'cost ${formatMoney(item['unit_cost'])}',
                  style: T.micro,
                ),
              ],
            ),
            const SizedBox(width: LamalivaSpace.sm),
            IconButton(
              tooltip: 'Add stock',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
            IconButton(
              tooltip: 'Take stock',
              onPressed: onTake,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            IconButton(
              tooltip: 'Stock take (physical count)',
              onPressed: onStockTake,
              icon: const Icon(Icons.fact_check_outlined, size: 20),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit item (admin)',
                onPressed: onEdit,
                icon: const Icon(Icons.tune, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
