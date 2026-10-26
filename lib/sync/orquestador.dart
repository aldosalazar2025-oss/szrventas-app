/// Coordina la sincronización en el celular: conectar, enviar ventas,
/// actualizar el catálogo y revisar cambios pedidos desde la PC.
library;

import 'dart:async';
import 'dart:io';

import 'android_store.dart';
import 'cliente_sync.dart';
import 'protocolo.dart';

abstract class AlmacenConfig {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String? valor);
}

class ResultadoEnvio {
  int enviadas = 0;
  int duplicadas = 0;
  int conConflicto = 0;
  int conError = 0;
  int pendientes = 0;
  final List<String> mensajes = [];
}

class ResultadoCatalogo {
  int creados = 0;
  int actualizados = 0;
  int retirados = 0;
  int imagenes = 0;
  int imagenesFallidas = 0;
}

class ServicioSync {
  final AndroidSyncStore store;
  final AlmacenConfig config;
  final Directory carpetaImagenes;
  final DateTime Function() ahora;

  ServicioSync({
    required this.store,
    required this.config,
    required this.carpetaImagenes,
    DateTime Function()? ahora,
  }) : ahora = ahora ?? DateTime.now;

  static const kHost = 'sync_host';
  static const kPuerto = 'sync_puerto';
  static const kId = 'sync_id';
  static const kSecreto = 'sync_secreto';
  static const kUltima = 'sync_ultima';
  static const kError = 'sync_error';
  static const kVersion = 'sync_catalogo_version';

  bool _ocupado = false;
  bool get ocupado => _ocupado;
  Timer? _timer;

  Future<ConfigSync?> cargarConfig() async {
    final host = await config.leer(kHost);
    final id = await config.leer(kId);
    final secreto = await config.leer(kSecreto);
    if (host == null || id == null || secreto == null) return null;
    return ConfigSync(
      host: host,
      puerto: int.tryParse(await config.leer(kPuerto) ?? '') ?? puertoPredeterminado,
      dispositivoId: id,
      secreto: secreto,
    );
  }

  Future<void> conectar({
    required String host,
    required int puerto,
    required String codigo,
    required String nombreDispositivo,
  }) async {
    var id = await config.leer(kId);
    id ??= aleatorioHex(16);
    final cfg = await ClienteSync.emparejar(
      host: host,
      puerto: puerto,
      codigo: codigo,
      dispositivoId: id,
      nombre: nombreDispositivo,
    );
    await config.escribir(kHost, cfg.host);
    await config.escribir(kPuerto, '${cfg.puerto}');
    await config.escribir(kId, cfg.dispositivoId);
    await config.escribir(kSecreto, cfg.secreto);
    await config.escribir(kError, null);
    // Prueba real con una solicitud firmada.
    await ClienteSync(cfg).getJson('/api/estado');
  }

  Future<void> desconectar() async {
    detenerAutoSync();
    await config.escribir(kSecreto, null);
    await config.escribir(kError, null);
  }

  Future<ClienteSync> _cliente() async {
    final cfg = await cargarConfig();
    if (cfg == null) throw ErrorSync('Primero conecta con la PC');
    return ClienteSync(cfg);
  }

  Future<T> _exclusivo<T>(Future<T> Function() accion) async {
    if (_ocupado) throw ErrorSync('Ya hay una sincronización en curso');
    _ocupado = true;
    try {
      return await accion();
    } finally {
      _ocupado = false;
    }
  }

  Future<ResultadoEnvio> enviarVentas() => _exclusivo(_enviarVentas);

  Future<ResultadoEnvio> _enviarVentas() async {
    final cliente = await _cliente();
    final r = ResultadoEnvio();
    try {
      // Cada venta se intenta una sola vez por sincronización.
      final intentadas = <String>{};
      while (true) {
        final lote = await store.ventasPendientes(excluir: intentadas);
        if (lote.isEmpty) break;
        intentadas.addAll([for (final v in lote) '${v['id']}']);
        final resp = await cliente.postJson('/api/ventas', {'ventas': lote});
        final resultados = [
          for (final x in (resp['resultados'] as List? ?? const []))
            if (x is Map) Map<String, Object?>.from(x),
        ];
        await store.marcarResultados(resultados);
        for (final x in resultados) {
          switch ('${x['estado']}') {
            case 'ok':
              r.enviadas++;
            case 'duplicada':
              r.duplicadas++;
            case 'conflicto':
              r.conConflicto++;
              r.mensajes.add('${x['mensaje']}');
            default:
              r.conError++;
              r.mensajes.add('${x['mensaje']}');
          }
        }
      }
    } on ErrorSync catch (e) {
      await config.escribir(kError, e.mensaje);
      r.pendientes = await store.contarPendientes();
      rethrow;
    }
    r.pendientes = await store.contarPendientes();
    return r;
  }

  Future<ResultadoCatalogo> actualizarProductos() => _exclusivo(_actualizarProductos);

  Future<ResultadoCatalogo> _actualizarProductos() async {
    final cliente = await _cliente();
    final r = ResultadoCatalogo();
    try {
      final snapshot = await cliente.getJson('/api/catalogo');
      final res = await store.aplicarCatalogo(Map<String, Object?>.from(snapshot));
      r.creados = res['creados'] as int;
      r.actualizados = res['actualizados'] as int;
      r.retirados = res['retirados'] as int;

      for (final ruta in (res['imagenesBorrar'] as List).cast<String>()) {
        try {
          final f = File(ruta);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      for (final img in (res['imagenesDescargar'] as List).cast<Map>()) {
        final id = '${img['id']}';
        final version = '${img['version']}';
        try {
          final bytes = await cliente.getBytes('/api/imagen/${Uri.encodeComponent(id)}');
          if (bytes == null) {
            r.imagenesFallidas++;
            continue;
          }
          await carpetaImagenes.create(recursive: true);
          final anterior = await store.imagenActual(id);
          final ext = _extensionDe(bytes);
          final destino = '${carpetaImagenes.path}${Platform.pathSeparator}'
              'sync_${id}_${version.hashCode.toUnsigned(32)}$ext';
          await File(destino).writeAsBytes(bytes, flush: true);
          await store.guardarImagen(id, version, destino);
          if (anterior != null && anterior != destino) {
            try {
              final f = File(anterior);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
          r.imagenes++;
        } on ErrorSync {
          r.imagenesFallidas++;
        }
      }
      await config.escribir(kVersion, '${snapshot['version']}');
    } on ErrorSync catch (e) {
      await config.escribir(kError, e.mensaje);
      rethrow;
    }
    return r;
  }

  static String _extensionDe(List<int> b) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return '.png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return '.webp';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return '.gif';
    return '.jpg';
  }

  /// Primero envía las ventas y después baja el catálogo, para que el
  /// stock recibido ya incluya lo vendido en el teléfono.
  Future<({ResultadoEnvio ventas, ResultadoCatalogo catalogo})> sincronizarTodo() =>
      _exclusivo(() async {
        final ventas = await _enviarVentas();
        final catalogo = await _actualizarProductos();
        await _terminar(null);
        return (ventas: ventas, catalogo: catalogo);
      });

  Future<void> _terminar(String? error) async {
    final cliente = await _cliente();
    try {
      await cliente.postJson('/api/sync/fin', {'error': error});
    } on ErrorSync {
      // Avisar a la PC es informativo; no invalida lo ya sincronizado.
    }
    await config.escribir(kUltima, ahora().toIso8601String());
    if (error == null) await config.escribir(kError, null);
  }

  // ---------- Revisión automática ----------

  void iniciarAutoSync({Duration cada = const Duration(seconds: 8), void Function(String)? alCambiar}) {
    detenerAutoSync();
    _timer = Timer.periodic(cada, (_) async {
      try {
        await revisarCambios(alCambiar: alCambiar);
      } catch (_) {}
    });
  }

  void detenerAutoSync() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pregunta a la PC si hay algo que hacer: una acción pedida desde el
  /// panel, cambios en el catálogo o ventas pendientes en el teléfono.
  Future<String?> revisarCambios({void Function(String)? alCambiar}) async {
    if (_ocupado) return null;
    final cfg = await cargarConfig();
    if (cfg == null) return null;
    final estado = await ClienteSync(cfg).getJson('/api/estado');
    final accion = estado['accion'] as String?;
    final versionPc = '${estado['catalogoVersion']}';
    final versionLocal = await config.leer(kVersion);
    final pendientes = await store.contarAutomaticas();

    String? hecho;
    if (accion == 'ventas') {
      await _exclusivo(() async {
        await _enviarVentas();
        await _terminar(null);
      });
      hecho = 'ventas';
    } else if (accion == 'productos') {
      await _exclusivo(() async {
        await _actualizarProductos();
        await _terminar(null);
      });
      hecho = 'productos';
    } else if (accion == 'todo' || pendientes > 0 || versionPc != versionLocal) {
      await sincronizarTodo();
      hecho = 'todo';
    }
    if (hecho != null) alCambiar?.call(hecho);
    return hecho;
  }
}
