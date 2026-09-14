/// Un tamaño (ej. "Personal", "Familiar") con el precio que tiene
/// dentro de un producto específico. El nombre del tamaño viene de
/// la lista global en [TamanosVariantesConfig]; el precio es propio
/// de cada producto (ej. la pizza Familiar cuesta distinto que la
/// hamburguesa Familiar).
class TamanoProducto {
  final String nombre;
  final double precio;

  const TamanoProducto({required this.nombre, required this.precio});

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'precio': precio,
      };

  factory TamanoProducto.fromMap(Map<String, dynamic> map) {
    return TamanoProducto(
      nombre: map['nombre'] as String? ?? '',
      precio: (map['precio'] as num?)?.toDouble() ?? 0,
    );
  }

  TamanoProducto copyWith({String? nombre, double? precio}) {
    return TamanoProducto(
      nombre: nombre ?? this.nombre,
      precio: precio ?? this.precio,
    );
  }
}
