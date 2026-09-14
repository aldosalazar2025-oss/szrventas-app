import 'package:url_launcher/url_launcher.dart';

/// Soporte Grupo Salazar — WhatsApp.
class SoporteConfig {
  static const whatsappNumero = '51900725974';
  static const whatsappDisplay = '+51 900 725 974';
  static const desarrollador = 'Grupo Salazar';
  static const mensajePro = 'quiero la version pro+';

  static Uri whatsappUri({String? mensaje}) {
    final base = 'https://wa.me/$whatsappNumero';
    if (mensaje == null || mensaje.isEmpty) return Uri.parse(base);
    return Uri.parse('$base?text=${Uri.encodeComponent(mensaje)}');
  }

  static Future<bool> abrirWhatsApp({String? mensaje}) async {
    return launchUrl(
      whatsappUri(mensaje: mensaje),
      mode: LaunchMode.externalApplication,
    );
  }
}
