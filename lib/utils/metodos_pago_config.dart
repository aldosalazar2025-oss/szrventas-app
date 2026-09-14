import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Métodos de pago del POS (etiquetas, iconos y preferencias).
class MetodosPagoConfig {
  static const todos = ['efectivo', 'yape', 'plin', 'tarjeta'];
  static const prefsKey = 'metodos_pago_habilitados';

  static const labels = {
    'efectivo': 'Efectivo',
    'yape': 'Yape',
    'plin': 'Plin',
    'tarjeta': 'Tarjeta',
  };

  static const icons = {
    'efectivo': Icons.money_rounded,
    'yape': Icons.phone_android_rounded,
    'plin': Icons.phone_iphone_rounded,
    'tarjeta': Icons.credit_card_rounded,
  };

  static const colors = {
    'efectivo': AppTheme.success,
    'yape': Color(0xFF6C2DC7),
    'plin': Color(0xFF00BFA5),
    'tarjeta': AppTheme.info,
  };

  static bool soportaQr(String metodo) => metodo == 'yape' || metodo == 'plin';

  static String label(String metodo) => labels[metodo] ?? metodo;
}
