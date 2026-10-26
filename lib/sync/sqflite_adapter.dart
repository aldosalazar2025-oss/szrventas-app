import 'package:sqflite/sqflite.dart';
import 'db_abstracta.dart';

/// Conecta la lógica de sincronización con la base SQLite de la app.
class SqfliteSyncDb implements SyncDb {
  final DatabaseExecutor _ex;
  final Database? _raiz;

  SqfliteSyncDb(Database db)
      : _ex = db,
        _raiz = db;
  SqfliteSyncDb._tx(Transaction tx)
      : _ex = tx,
        _raiz = null;

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) =>
      _ex.rawQuery(sql, args);

  @override
  Future<int> run(String sql, [List<Object?> args = const []]) async {
    final t = sql.trimLeft().toUpperCase();
    if (t.startsWith('INSERT')) {
      await _ex.rawInsert(sql, args);
      return 1;
    }
    if (t.startsWith('UPDATE') || t.startsWith('DELETE')) {
      return _ex.rawUpdate(sql, args);
    }
    await _ex.execute(sql, args);
    return 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SyncDb tx) accion) {
    final raiz = _raiz;
    if (raiz == null) return accion(this);
    return raiz.transaction((tx) => accion(SqfliteSyncDb._tx(tx)));
  }
}
