/// Lógica del celular: ventas pendientes, estado de envío y copia local del catálogo.
library;

import 'dart:convert';

import 'db_abstracta.dart';

const _columnasProducto = [
  'id', 'codigo_barras', 'nombre', 'descripcion', 'categoria', 'precio_compra',
  'precio_venta', 'stock', 'stock_minimo', 'tipo_venta', 'fecha_creacion',
  'fecha_actualizacion', 'variantes', 'tamanos', 'conjuntos',
];

class AndroidSyncStore {
  final SyncDb db;
  final DateTime Function() ahora;

  AndroidSyncStore(this.db, {DateTime Function()? ahora}) : ahora = ahora ?? DateTime.now;

  /// Agrega las columnas y tablas de sincronización. Las ventas que ya
  /// existían se marcan como 'previa' para que NO se envíen (su stock ya
  /// estaba contado en la PC).
  static Future<void> migrar(SyncDb db) async {
    final columnas =
        (await db.query('PRAGMA table_info(ventas)')).map((c) => '${c['name']}').toSet();
    if (!columnas.contains('sync_estado')) {
      await db.run("ALTER TABLE ventas ADD COLUMN sync_estado TEXT NOT NULL DEFAULT 'pendiente'");
      await db.run("UPDATE ventas SET sync_estado = 'previa'");
    }
    if (!columnas.contains('sync_fecha')) {
      await db.run('ALTER TABLE ventas ADD COLUMN sync_fecha TEXT');
    }
    if (!columnas.contains('sync_error')) {
      await db.run('ALTER TABLE ventas ADD COLUMN sync_error TEXT');
    }
    if (!columnas.contains('sync_intentos')) {
      await db.run('ALTER TABLE ventas ADD COLUMN sync_intentos INTEGER NOT NULL DEFAULT 0');
    }
    await db.run(
      'CREATE TABLE IF NOT EXISTS sync_eliminados (id TEXT PRIMARY KEY, fecha TEXT NOT NULL)',
    );
    await db.run(
      'CREATE TABLE IF NOT EXISTS sync_imagenes (producto_id TEXT PRIMARY KEY, version TEXT NOT NULL)',
    );
  }

  Future<bool> estaEliminado(String productoId) async =>
      (await db.query('SELECT id FROM sync_eliminados WHERE id = ?', [productoId])).isNotEmpty;

  // ---------- Ventas pendientes ----------

  Future<int> contarPendientes() async {
    final f = await db.query(
      "SELECT COUNT(*) AS n FROM ventas WHERE sync_estado IN ('pendiente', 'error')",
    );
    return (f.first['n'] as int?) ?? 0;
  }

  /// Ventas que el envío automático todavía debe intentar (las que fallaron
  /// 3 veces solo se reintentan a mano).
  Future<int> contarAutomaticas() async {
    final f = await db.query(
      "SELECT COUNT(*) AS n FROM ventas WHERE sync_estado = 'pendiente' "
      "OR (sync_estado = 'error' AND sync_intentos < 3)",
    );
    return (f.first['n'] as int?) ?? 0;
  }

  /// Ventas por enviar, con sus productos, listas para mandar a la PC.
  Future<List<Map<String, Object?>>> ventasPendientes({
    int limite = 50,
    Set<String> excluir = const {},
  }) async {
    final filtro = excluir.isEmpty
        ? ''
        : 'AND id NOT IN (${List.filled(excluir.length, '?').join(', ')}) ';
    final ventas = await db.query(
      "SELECT * FROM ventas WHERE sync_estado IN ('pendiente', 'error') $filtro"
      'ORDER BY sync_intentos, fecha LIMIT ?',
      [...excluir, limite],
    );
    final salida = <Map<String, Object?>>[];
    for (final v in ventas) {
      final items = await db.query(
        'SELECT * FROM items_venta WHERE venta_id = ?',
        [v['id']],
      );
      salida.add({
        for (final e in v.entries)
          if (!e.key.startsWith('sync_')) e.key: e.value,
        'items': [
          for (final i in items)
            {
              for (final e in i.entries)
                if (e.key != 'imagen_url') e.key: e.value,
            },
        ],
      });
    }
    return salida;
  }

  /// Para la pantalla "ver ventas pendientes".
  Future<List<Map<String, Object?>>> listarPendientes() => db.query(
        'SELECT id, fecha, total, sync_estado, sync_error, sync_intentos FROM ventas '
        "WHERE sync_estado IN ('pendiente', 'error') ORDER BY fecha DESC",
      );

  /// Marca como sincronizada SOLO la venta que la PC confirmó.
  Future<void> marcarResultados(List<Map<String, Object?>> resultados) async {
    final ts = ahora().toIso8601String();
    for (final r in resultados) {
      final id = '${r['id']}';
      final estado = '${r['estado']}';
      if (estado == 'ok' || estado == 'duplicada' || estado == 'conflicto') {
        await db.run(
          'UPDATE ventas SET sync_estado = ?, sync_fecha = ?, sync_error = ? WHERE id = ?',
          [
            estado == 'conflicto' ? 'conflicto' : 'sincronizada',
            ts,
            estado == 'conflicto' ? '${r['mensaje']}' : null,
            id,
          ],
        );
      } else {
        await db.run(
          "UPDATE ventas SET sync_estado = 'error', sync_error = ?, "
          'sync_intentos = sync_intentos + 1 WHERE id = ?',
          ['${r['mensaje'] ?? 'Error desconocido'}', id],
        );
      }
    }
  }

  // ---------- Catálogo ----------

  /// Aplica el catálogo de la PC. Devuelve cuántos productos se crearon,
  /// actualizaron y retiraron, y qué imágenes hay que descargar o borrar.
  Future<Map<String, Object?>> aplicarCatalogo(Map<String, Object?> snapshot) async {
    return db.transaction((tx) async {
      // Lo vendido aquí y aún no enviado: se descuenta del stock recibido
      // para que el teléfono muestre la disponibilidad real.
      final pendientes = await tx.query(
        'SELECT i.producto_id, i.cantidad, i.variante_talla, i.variante_color '
        'FROM items_venta i JOIN ventas v ON v.id = i.venta_id '
        "WHERE v.sync_estado IN ('pendiente', 'error')",
      );
      final porProducto = <String, int>{};
      final porVariante = <String, int>{};
      for (final p in pendientes) {
        final id = '${p['producto_id']}';
        final c = (p['cantidad'] as num).toInt();
        porProducto[id] = (porProducto[id] ?? 0) + c;
        final talla = '${p['variante_talla'] ?? ''}';
        final color = '${p['variante_color'] ?? ''}';
        if (talla.isNotEmpty || color.isNotEmpty) {
          final k = '$id|$talla|$color';
          porVariante[k] = (porVariante[k] ?? 0) + c;
        }
      }

      var creados = 0, actualizados = 0, retirados = 0;
      final imagenesDescargar = <Map<String, Object?>>[];
      final imagenesBorrar = <String>[];
      final productos = (snapshot['productos'] as List?) ?? const [];

      for (final raw in productos) {
        final p = Map<String, Object?>.from(raw as Map);
        final id = '${p['id']}';

        var stock = (p['stock'] as num).toInt() - (porProducto[id] ?? 0);
        if (stock < 0) stock = 0;

        var variantes = '${p['variantes'] ?? '[]'}';
        try {
          final lista = List<dynamic>.from(jsonDecode(variantes) as List);
          for (var i = 0; i < lista.length; i++) {
            final v = Map<String, Object?>.from(lista[i] as Map);
            final k = '$id|${v['talla'] ?? ''}|${v['color'] ?? ''}';
            final resta = porVariante[k] ?? 0;
            if (resta > 0) {
              final s = ((v['stock'] as num?)?.toInt() ?? 0) - resta;
              v['stock'] = s < 0 ? 0 : s;
              lista[i] = v;
            }
          }
          variantes = jsonEncode(lista);
        } catch (_) {
          // Si las variantes no se pueden leer, se guardan tal cual llegaron.
        }

        final valores = <String, Object?>{
          for (final c in _columnasProducto) c: p[c],
          'stock': stock,
          'variantes': variantes,
        };

        final existe = await tx.query('SELECT id FROM productos WHERE id = ?', [id]);
        if (existe.isEmpty) {
          final cols = valores.keys.toList();
          await tx.run(
            'INSERT INTO productos (${cols.join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) valores[c]],
          );
          creados++;
        } else {
          final cols = valores.keys.where((c) => c != 'id').toList();
          await tx.run(
            'UPDATE productos SET ${cols.map((c) => '$c = ?').join(', ')} WHERE id = ?',
            [for (final c in cols) valores[c], id],
          );
          actualizados++;
        }
        // Si el producto volvió a existir en la PC, deja de estar retirado.
        await tx.run('DELETE FROM sync_eliminados WHERE id = ?', [id]);

        final version = p['imagen_version'] as String?;
        final local = await tx.query(
          'SELECT version FROM sync_imagenes WHERE producto_id = ?',
          [id],
        );
        final versionLocal = local.isEmpty ? null : '${local.first['version']}';
        if (version == null) {
          if (versionLocal != null) {
            final img = await tx.query('SELECT imagen_url FROM productos WHERE id = ?', [id]);
            final ruta = img.isEmpty ? null : img.first['imagen_url'] as String?;
            if (ruta != null && ruta.isNotEmpty) imagenesBorrar.add(ruta);
            await tx.run('UPDATE productos SET imagen_url = NULL WHERE id = ?', [id]);
            await tx.run('DELETE FROM sync_imagenes WHERE producto_id = ?', [id]);
          }
        } else if (version != versionLocal) {
          imagenesDescargar.add({'id': id, 'version': version});
        }
      }

      final ts = ahora().toIso8601String();
      for (final idRaw in (snapshot['eliminados'] as List?) ?? const []) {
        final id = '$idRaw';
        final img = await tx.query('SELECT imagen_url FROM productos WHERE id = ?', [id]);
        if (img.isNotEmpty) {
          final ruta = img.first['imagen_url'] as String?;
          if (ruta != null && ruta.isNotEmpty) imagenesBorrar.add(ruta);
          await tx.run('DELETE FROM productos WHERE id = ?', [id]);
          retirados++;
        }
        await tx.run('DELETE FROM sync_imagenes WHERE producto_id = ?', [id]);
        await tx.run(
          'INSERT OR REPLACE INTO sync_eliminados (id, fecha) VALUES (?, ?)',
          [id, ts],
        );
      }

      for (final c in (snapshot['categorias'] as List?) ?? const []) {
        await tx.run('INSERT OR IGNORE INTO categorias (nombre) VALUES (?)', ['$c']);
      }

      return <String, Object?>{
        'creados': creados,
        'actualizados': actualizados,
        'retirados': retirados,
        'imagenesDescargar': imagenesDescargar,
        'imagenesBorrar': imagenesBorrar,
      };
    });
  }

  Future<void> guardarImagen(String productoId, String version, String rutaLocal) async {
    await db.run('UPDATE productos SET imagen_url = ? WHERE id = ?', [rutaLocal, productoId]);
    await db.run(
      'INSERT OR REPLACE INTO sync_imagenes (producto_id, version) VALUES (?, ?)',
      [productoId, version],
    );
  }

  Future<String?> imagenActual(String productoId) async {
    final f = await db.query('SELECT imagen_url FROM productos WHERE id = ?', [productoId]);
    return f.isEmpty ? null : f.first['imagen_url'] as String?;
  }
}
