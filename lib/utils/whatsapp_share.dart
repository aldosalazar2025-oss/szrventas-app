import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre WhatsApp con el ticket en texto (nunca PDF ni archivo).
class WhatsAppShare {
  /// Normaliza a dígitos internacionales. 9XXXXXXXX (Perú) → 519XXXXXXXX.
  static String? normalizarNumero(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length == 9 && d.startsWith('9')) d = '51$d';
    if (d.length < 10 || d.length > 15) return null;
    return d;
  }

  static Future<bool> enviar({
    required String texto,
    String? numero,
  }) async {
    if (numero != null && numero.isNotEmpty) {
      final encoded = Uri.encodeComponent(texto);
      final uris = [
        Uri.parse('whatsapp://send?phone=$numero&text=$encoded'),
        Uri.parse('https://wa.me/$numero?text=$encoded'),
      ];
      for (final uri in uris) {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    }

    await SharePlus.instance.share(ShareParams(text: texto));
    return true;
  }

  /// Comparte una imagen (el ticket como foto, con el logo incluido) a
  /// través del selector de apps del sistema. WhatsApp no permite abrir
  /// un chat con un número específico y adjuntar una foto al mismo
  /// tiempo, así que aquí el usuario elige el chat manualmente tras
  /// tocar WhatsApp en el selector.
  static Future<bool> enviarImagen({
    required File imagen,
    String? texto,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imagen.path)],
          text: texto,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Abre el chat de WhatsApp de un número específico sin texto (solo
  /// para "activar" esa conversación). WhatsApp no soporta abrir un
  /// chat concreto y adjuntar una imagen en un solo paso, así que este
  /// método se usa justo antes de [enviarImagen]: primero se abre el
  /// chat del cliente, y el usuario elige ese mismo chat (aparece de
  /// primero, recién usado) en el selector que abre [enviarImagen].
  static Future<bool> abrirChat(String numero) async {
    final uris = [
      Uri.parse('whatsapp://send?phone=$numero'),
      Uri.parse('https://wa.me/$numero'),
    ];
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
