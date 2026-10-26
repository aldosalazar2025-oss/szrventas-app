/// Cliente que usa el celular para hablar con la PC.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocolo.dart';

class ConfigSync {
  final String host;
  final int puerto;
  final String dispositivoId;
  final String secreto;
  const ConfigSync({
    required this.host,
    required this.puerto,
    required this.dispositivoId,
    required this.secreto,
  });
}

class ClienteSync {
  final ConfigSync config;
  final int Function() ahoraMs;
  ClienteSync(this.config, {int Function()? ahoraMs})
      : ahoraMs = ahoraMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static HttpClient _http() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 5);

  static Future<Map<String, dynamic>> ping(String host, int puerto) async {
    final http = _http();
    try {
      final req = await http.getUrl(Uri.parse('http://$host:$puerto/api/ping'));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final texto = await resp.transform(utf8.decoder).join();
      final datos = jsonDecode(texto);
      if (resp.statusCode != 200 || datos is! Map || datos['app'] != appPanel) {
        throw ErrorSync('Ese equipo no es el Panel SZR Ventas');
      }
      return Map<String, dynamic>.from(datos);
    } on ErrorSync {
      rethrow;
    } on TimeoutException {
      throw ErrorSync('La PC no responde. Revisa la IP y que estén en la misma red Wi-Fi.');
    } on SocketException {
      throw ErrorSync('No se pudo conectar con la PC. Revisa la IP, el puerto y el firewall.');
    } catch (e) {
      throw ErrorSync('Respuesta no válida de la PC ($e)');
    } finally {
      http.close(force: true);
    }
  }

  /// Empareja con la PC usando el código que muestra el panel.
  static Future<ConfigSync> emparejar({
    required String host,
    required int puerto,
    required String codigo,
    required String dispositivoId,
    required String nombre,
  }) async {
    final info = await ping(host, puerto);
    final sal = '${info['sal']}';
    final nonce = aleatorioHex(16);
    final secreto = derivarSecreto(codigo.trim(), dispositivoId, sal, nonce);
    final http = _http();
    try {
      final req = await http.postUrl(Uri.parse('http://$host:$puerto/api/emparejar'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'dispositivoId': dispositivoId,
        'nombre': nombre,
        'nonce': nonce,
        'prueba': pruebaEmparejamiento(secreto),
      }));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final texto = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        String mensaje = 'No se pudo emparejar';
        try {
          mensaje = '${(jsonDecode(texto) as Map)['error']}';
        } catch (_) {}
        throw ErrorSync(mensaje, codigo: resp.statusCode);
      }
      return ConfigSync(host: host, puerto: puerto, dispositivoId: dispositivoId, secreto: secreto);
    } on ErrorSync {
      rethrow;
    } on TimeoutException {
      throw ErrorSync('La PC no respondió al emparejar');
    } on SocketException {
      throw ErrorSync('Se perdió la conexión con la PC');
    } finally {
      http.close(force: true);
    }
  }

  Future<({int codigo, List<int> cuerpo})> _enviar(
    String metodo,
    String ruta, {
    Object? json,
    Duration espera = const Duration(seconds: 60),
  }) async {
    final cuerpo = json == null ? <int>[] : utf8.encode(jsonEncode(json));
    final tiempo = ahoraMs();
    final nonce = aleatorioHex(12);
    final http = _http();
    try {
      final req = await http.openUrl(
        metodo,
        Uri.parse('http://${config.host}:${config.puerto}$ruta'),
      );
      req.headers.set('x-dispositivo', config.dispositivoId);
      req.headers.set('x-tiempo', '$tiempo');
      req.headers.set('x-nonce', nonce);
      req.headers.set(
        'x-firma',
        firmarSolicitud(config.secreto, metodo, ruta, tiempo, nonce, cuerpo),
      );
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.add(cuerpo);
      }
      final resp = await req.close().timeout(espera);
      final bytes = <int>[];
      await for (final parte in resp.timeout(espera)) {
        bytes.addAll(parte);
      }
      if (resp.statusCode == 401 || resp.statusCode == 429) {
        String mensaje = 'La PC rechazó la solicitud';
        try {
          mensaje = '${(jsonDecode(utf8.decode(bytes)) as Map)['error']}';
        } catch (_) {}
        throw ErrorSync(mensaje, codigo: resp.statusCode);
      }
      final firma = resp.headers.value('x-firma-respuesta') ?? '';
      final esperada = firmarRespuesta(config.secreto, nonce, bytes);
      if (!igualesConstante(esperada, firma)) {
        throw ErrorSync('La respuesta de la PC no es de confianza (firma inválida)');
      }
      return (codigo: resp.statusCode, cuerpo: bytes);
    } on ErrorSync {
      rethrow;
    } on TimeoutException {
      throw ErrorSync('La PC tardó demasiado en responder');
    } on SocketException {
      throw ErrorSync('Se perdió la conexión con la PC');
    } on HttpException catch (e) {
      throw ErrorSync('Error de red: ${e.message}');
    } finally {
      http.close(force: true);
    }
  }

  Future<Map<String, dynamic>> getJson(String ruta) async {
    final r = await _enviar('GET', ruta);
    final datos = jsonDecode(utf8.decode(r.cuerpo));
    if (r.codigo != 200) throw ErrorSync('${(datos as Map)['error']}', codigo: r.codigo);
    return Map<String, dynamic>.from(datos as Map);
  }

  Future<Map<String, dynamic>> postJson(String ruta, Object cuerpo) async {
    final r = await _enviar('POST', ruta, json: cuerpo);
    final datos = jsonDecode(utf8.decode(r.cuerpo));
    if (r.codigo != 200) throw ErrorSync('${(datos as Map)['error']}', codigo: r.codigo);
    return Map<String, dynamic>.from(datos as Map);
  }

  /// Descarga una imagen. Devuelve null si la PC no tiene imagen.
  Future<List<int>?> getBytes(String ruta) async {
    final r = await _enviar('GET', ruta);
    if (r.codigo == 404) return null;
    if (r.codigo != 200) throw ErrorSync('No se pudo descargar la imagen', codigo: r.codigo);
    return r.cuerpo;
  }
}
