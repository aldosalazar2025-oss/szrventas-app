/// Acceso mínimo a SQLite. Las apps lo implementan con sqflite y las
/// pruebas con SQLite nativo, así la misma lógica se prueba de verdad.
library;

abstract class SyncDb {
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]);

  /// Ejecuta INSERT/UPDATE/DELETE/DDL y devuelve las filas afectadas.
  Future<int> run(String sql, [List<Object?> args = const []]);

  /// Ejecuta [accion] en una transacción: si lanza un error, se revierte todo.
  Future<T> transaction<T>(Future<T> Function(SyncDb tx) accion);
}
