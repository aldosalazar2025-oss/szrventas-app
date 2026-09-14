import 'dart:convert';

/// Una opción de un [ConjuntoOpcion] que el cliente eligió al vender,
/// junto con el nombre del conjunto al que pertenece (para agruparla en
/// el recibo) y el precio extra que sumó al total en ese momento.
class OpcionElegida {
  final String conjunto;
  final String opcion;
  final double precioExtra;

  const OpcionElegida({
    required this.conjunto,
    required this.opcion,
    this.precioExtra = 0,
  });

  Map<String, dynamic> toMap() => {
        'conjunto': conjunto,
        'opcion': opcion,
        'precioExtra': precioExtra,
      };

  factory OpcionElegida.fromMap(Map<String, dynamic> map) {
    return OpcionElegida(
      conjunto: map['conjunto'] as String? ?? '',
      opcion: map['opcion'] as String? ?? '',
      precioExtra: (map['precioExtra'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Firma canónica (orden estable) de una combinación de opciones, para
  /// comparar si dos líneas del carrito tienen exactamente los mismos
  /// extras elegidos y así saber si deben agruparse o ir por separado.
  static String firma(List<OpcionElegida> opciones) {
    final partes = opciones.map((o) => '${o.conjunto}:${o.opcion}').toList()
      ..sort();
    return partes.join('|');
  }

  static String encodeLista(List<OpcionElegida> opciones) =>
      jsonEncode(opciones.map((o) => o.toMap()).toList());

  static List<OpcionElegida> decodeLista(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final lista = jsonDecode(raw) as List;
      return lista
          .map((e) =>
              OpcionElegida.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
