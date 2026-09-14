import 'package:flutter/material.dart';
import '../models/venta.dart';
import '../theme/app_theme.dart';

/// Chips pequeños que muestran la talla y el color vendidos en una
/// línea del carrito, la orden, el ticket o el historial de ventas.
class VarianteChips extends StatelessWidget {
  const VarianteChips({super.key, required this.item});

  final ItemVenta item;

  @override
  Widget build(BuildContext context) {
    if (!item.tieneVariante) return const SizedBox.shrink();

    final chips = <Widget>[];
    final talla = item.varianteTalla?.trim() ?? '';
    final color = item.varianteColor?.trim() ?? '';

    if (talla.isNotEmpty) {
      chips.add(_chip(Icons.straighten_rounded, 'Talla $talla'));
    }
    if (color.isNotEmpty) {
      chips.add(_chip(Icons.palette_outlined, color));
    }

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
