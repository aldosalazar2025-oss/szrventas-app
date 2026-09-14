import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/peso_formatter.dart';

/// Devuelve gramos a vender, o null si se cancela.
Future<int?> showPesoCantidadDialog({
  required BuildContext context,
  required Producto producto,
  required String monedaSimbolo,
  required int stockDisponible,
  int? cantidadInicial,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PesoCantidadSheet(
      producto: producto,
      monedaSimbolo: monedaSimbolo,
      stockDisponible: stockDisponible,
      cantidadInicial: cantidadInicial,
    ),
  );
}

class _PesoCantidadSheet extends StatefulWidget {
  const _PesoCantidadSheet({
    required this.producto,
    required this.monedaSimbolo,
    required this.stockDisponible,
    this.cantidadInicial,
  });

  final Producto producto;
  final String monedaSimbolo;
  final int stockDisponible;
  final int? cantidadInicial;

  @override
  State<_PesoCantidadSheet> createState() => _PesoCantidadSheetState();
}

class _PesoCantidadSheetState extends State<_PesoCantidadSheet> {
  final _ctrl = TextEditingController();
  bool _enKg = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCantidadChanged);
    if (widget.cantidadInicial != null && widget.cantidadInicial! > 0) {
      _ctrl.text = PesoFormatter.kgInputFromGrams(widget.cantidadInicial!);
    }
  }

  void _onCantidadChanged() => setState(() => _error = null);

  int get _gramos =>
      PesoFormatter.parseToGrams(_ctrl.text, enKg: _enKg);

  String _money(double v) =>
      CurrencyFormatter.format(v, widget.monedaSimbolo);

  void _aplicarAtajo(int gramos) {
    setState(() {
      if (_enKg) {
        _ctrl.text = PesoFormatter.kgInputFromGrams(gramos);
      } else {
        _ctrl.text = '$gramos';
      }
      _error = null;
    });
  }

  void _confirmar() {
    final g = _gramos;
    if (g <= 0) {
      setState(() => _error = 'Ingresa una cantidad mayor a 0');
      return;
    }
    if (g > widget.stockDisponible) {
      setState(() => _error =
          'Stock insuficiente (${PesoFormatter.formatGrams(widget.stockDisponible)})');
      return;
    }
    Navigator.pop(context, g);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCantidadChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = _gramos;
    final preview = g > 0
        ? PesoFormatter.subtotal(
            gramos: g,
            precioPorKg: widget.producto.precioVenta,
          )
        : 0.0;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.producto.nombre,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${_money(widget.producto.precioVenta)}/kg  ·  Stock ${PesoFormatter.formatGrams(widget.stockDisponible)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('kg')),
              ButtonSegment(value: false, label: Text('g')),
            ],
            selected: {_enKg},
            onSelectionChanged: (s) {
              final grams = _gramos;
              setState(() {
                _enKg = s.first;
                if (grams > 0) {
                  _ctrl.text = _enKg
                      ? PesoFormatter.kgInputFromGrams(grams)
                      : '$grams';
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: widget.cantidadInicial == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: _enKg ? 'Cantidad (kg)' : 'Cantidad (g)',
              hintText: _enKg ? 'Ej: 0.250' : 'Ej: 250',
              hintStyle: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.normal,
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final gAtajo in [100, 250, 500, 1000])
                ActionChip(
                  label: Text(
                    gAtajo == 1000 ? '1 kg' : '$gAtajo g',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  side: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                  ),
                  onPressed: () => _aplicarAtajo(gAtajo),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              g > 0
                  ? '${PesoFormatter.formatKg(g)} × ${_money(widget.producto.precioVenta)}/kg = ${_money(preview)}'
                  : 'Ingresa el peso para ver el total',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _confirmar,
              child: Text(
                widget.cantidadInicial != null ? 'Actualizar' : 'Agregar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
