/// Protocolo de sincronización por Wi-Fi local de SZR Ventas.
///
/// - Emparejamiento: la PC muestra un código; el secreto compartido se
///   deriva del código en ambos lados y NUNCA viaja por la red.
/// - Cada solicitud va firmada con HMAC-SHA256 (método, ruta, hora, nonce y
///   huella del cuerpo). La PC rechaza firmas inválidas, horas fuera de
///   rango y nonces repetidos. Las respuestas también van firmadas.
library;

import 'dart:math';
import 'sha256.dart';

const String appPanel = 'szr-panel';
const int versionProtocolo = 1;
const int puertoPredeterminado = 8765;
const int toleranciaRelojMs = 5 * 60 * 1000;

class ErrorSync implements Exception {
  final String mensaje;
  final int? codigo;
  ErrorSync(this.mensaje, {this.codigo});
  @override
  String toString() => mensaje;
}

String aleatorioHex(int bytes) {
  final r = Random.secure();
  return aHex([for (var i = 0; i < bytes; i++) r.nextInt(256)]);
}

bool igualesConstante(String a, String b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return d == 0;
}

/// Secreto derivado del código de emparejamiento (no se transmite).
String derivarSecreto(String codigo, String dispositivoId, String sal, String nonceCliente) =>
    hmacHex(codigo, 'szr-sync|$dispositivoId|$sal|$nonceCliente');

String pruebaEmparejamiento(String secreto) => hmacHex(secreto, 'emparejar');

String firmarSolicitud(
  String secreto,
  String metodo,
  String ruta,
  int tiempo,
  String nonce,
  List<int> cuerpo,
) =>
    hmacHex(secreto, '$metodo\n$ruta\n$tiempo\n$nonce\n${sha256Hex(cuerpo)}');

String firmarRespuesta(String secreto, String nonceSolicitud, List<int> cuerpo) =>
    hmacHex(secreto, 'respuesta\n$nonceSolicitud\n${sha256Hex(cuerpo)}');

/// Recuerda los nonces vistos para rechazar solicitudes repetidas.
class CacheNonces {
  final Map<String, int> _vistos = {};

  /// Devuelve false si el nonce ya se había usado.
  bool registrar(String nonce, int ahoraMs) {
    _vistos.removeWhere((_, t) => ahoraMs - t > 2 * toleranciaRelojMs);
    if (_vistos.containsKey(nonce)) return false;
    _vistos[nonce] = ahoraMs;
    return true;
  }
}
