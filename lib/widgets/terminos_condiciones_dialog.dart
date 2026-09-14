import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<void> showTerminosCondicionesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Términos y condiciones',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Términos de uso',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Szr Ventas es un sistema de punto de venta (POS) para uso '
                'personal o comercial. Los datos de productos, ventas e '
                'inventario se almacenan localmente en tu dispositivo. '
                'Eres responsable de la información que ingresas: precios, '
                'stock, métodos de pago y demás datos de tu negocio.',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text(
                'Soporte',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'WhatsApp / teléfono: +51 900 725 974',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text(
                'Desarrollador',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Grupo Salazar — desarrollador del sistema Szr Ventas.',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'Los tickets impresos por Szr Ventas son comprobantes '
                  'simples de venta. No constituyen facturas, boletas de '
                  'venta ni documentos tributarios vinculados a SUNAT. '
                  'Para emitir comprobantes oficiales, debes usar los '
                  'sistemas autorizados por la normativa peruana.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
