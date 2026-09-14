import 'dart:convert';

/// Una opción dentro de un [ConjuntoOpcion] (ej. "Queso extra", "Mayonesa"),
/// con su precio adicional si el cliente la elige.
class OpcionExtra {
  final String nombre;
  final double precioExtra;

  const OpcionExtra({required this.nombre, this.precioExtra = 0});

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'precioExtra': precioExtra,
      };

  factory OpcionExtra.fromMap(Map<String, dynamic> map) {
    return OpcionExtra(
      nombre: map['nombre'] as String? ?? '',
      precioExtra: (map['precioExtra'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Un conjunto de opciones (ej. "Cremas", "Extras") que se puede
/// asociar a un producto. Define si el cliente puede elegir una o
/// varias opciones, si es obligatorio elegir alguna, y un máximo
/// opcional de opciones seleccionables.
class ConjuntoOpcion {
  final String nombre;
  final bool seleccionMultiple; // true = "Varias", false = "Una"
  final bool obligatorio;
  final int? maximo;
  final List<OpcionExtra> opciones;

  const ConjuntoOpcion({
    required this.nombre,
    this.seleccionMultiple = true,
    this.obligatorio = false,
    this.maximo,
    this.opciones = const [],
  });

  ConjuntoOpcion copyWith({
    String? nombre,
    bool? seleccionMultiple,
    bool? obligatorio,
    int? maximo,
    bool limpiarMaximo = false,
    List<OpcionExtra>? opciones,
  }) {
    return ConjuntoOpcion(
      nombre: nombre ?? this.nombre,
      seleccionMultiple: seleccionMultiple ?? this.seleccionMultiple,
      obligatorio: obligatorio ?? this.obligatorio,
      maximo: limpiarMaximo ? null : (maximo ?? this.maximo),
      opciones: opciones ?? this.opciones,
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'seleccionMultiple': seleccionMultiple,
        'obligatorio': obligatorio,
        'maximo': maximo,
        'opciones': opciones.map((o) => o.toMap()).toList(),
      };

  factory ConjuntoOpcion.fromMap(Map<String, dynamic> map) {
    return ConjuntoOpcion(
      nombre: map['nombre'] as String? ?? '',
      seleccionMultiple: map['seleccionMultiple'] as bool? ?? true,
      obligatorio: map['obligatorio'] as bool? ?? false,
      maximo: (map['maximo'] as num?)?.toInt(),
      opciones: (map['opciones'] as List<dynamic>? ?? [])
          .map((o) => OpcionExtra.fromMap(Map<String, dynamic>.from(o as Map)))
          .toList(),
    );
  }

  String toStorage() => jsonEncode(toMap());

  factory ConjuntoOpcion.fromStorage(String raw) {
    return ConjuntoOpcion.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }
}
