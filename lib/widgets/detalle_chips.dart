import 'package:flutter/material.dart';
import '../models/venta.dart';
import '../theme/app_theme.dart';

/// Chips pequeños con ícono que muestran el tamaño y los extras/notas
/// elegidos en una línea del carrito, la orden, el ticket o el historial.
class DetalleChips extends StatelessWidget {
  const DetalleChips({super.key, required this.item});

  final ItemVenta item;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (item.tieneTamano) {
      chips.add(_chip(Icons.local_pizza_outlined, item.tamanoNombre!));
    }
    if (item.conjuntosElegidos.isNotEmpty) {
      chips.add(_chip(Icons.tune_rounded, item.etiquetaExtras));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
