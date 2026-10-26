import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'android_store.dart';
import 'orquestador.dart';
import 'sqflite_adapter.dart';

class _PrefsConfig implements AlmacenConfig {
  @override
  Future<String?> leer(String clave) async =>
      (await SharedPreferences.getInstance()).getString(clave);

  @override
  Future<void> escribir(String clave, String? valor) async {
    final p = await SharedPreferences.getInstance();
    if (valor == null) {
      await p.remove(clave);
    } else {
      await p.setString(clave, valor);
    }
  }
}

/// Mantiene el servicio de sincronización mientras la app está abierta.
class ServicioSyncAndroid {
  ServicioSyncAndroid._();
  static final ServicioSyncAndroid instance = ServicioSyncAndroid._();

  ServicioSync? _servicio;
  AndroidSyncStore? _store;

  /// Se incrementa cuando una sincronización automática cambió datos.
  final ValueNotifier<int> cambios = ValueNotifier<int>(0);

  Future<ServicioSync> servicio() async {
    if (_servicio != null) return _servicio!;
    final dir = await getApplicationDocumentsDirectory();
    final db = await DatabaseService.instance.database;
    _store = AndroidSyncStore(SqfliteSyncDb(db));
    _servicio = ServicioSync(
      store: _store!,
      config: _PrefsConfig(),
      carpetaImagenes: Directory('${dir.path}/imagenes_productos'),
    );
    return _servicio!;
  }

  Future<AndroidSyncStore> store() async {
    await servicio();
    return _store!;
  }

  /// Si el celular ya está emparejado, revisa cada pocos segundos si la PC
  /// pidió algo o cambió el catálogo.
  Future<void> iniciarSiConfigurado() async {
    final s = await servicio();
    if (await s.cargarConfig() != null) {
      s.iniciarAutoSync(alCambiar: (_) => cambios.value++);
    }
  }
}
