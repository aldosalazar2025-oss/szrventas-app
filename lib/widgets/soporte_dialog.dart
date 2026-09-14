import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/soporte_config.dart';

Future<void> showSoporteDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.support_agent_rounded, color: AppTheme.primary),
          SizedBox(width: 8),
          Text('Soporte', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SoporteConfig.desarrollador,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Desarrollador de Szr Ventas',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Contacto (solo WhatsApp)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                SoporteConfig.whatsappDisplay,
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text(
                'Versión Pro+',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                '¿Necesitas una app más personalizada? Con la versión Pro+ '
                'tus datos no se guardan solo en el teléfono: se sincronizan '
                'en la nube para que puedas ver tu negocio desde todos tus '
                'dispositivos.',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: const Text(
                  'Escríbenos por WhatsApp con el mensaje:\n'
                  '"quiero la version pro+"',
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
        ElevatedButton.icon(
          onPressed: () async {
            final ok = await SoporteConfig.abrirWhatsApp(
              mensaje: SoporteConfig.mensajePro,
            );
            if (!ctx.mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('No se pudo abrir WhatsApp'),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          icon: const Icon(Icons.chat_rounded, size: 20),
          label: const Text('WhatsApp Pro+'),
        ),
      ],
    ),
  );
}
