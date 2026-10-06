import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/opcion_elegida.dart';
import '../models/producto.dart';
import '../models/tamano_producto.dart';
import '../models/variante_producto.dart';
import '../models/venta.dart';
import '../services/database_service.dart';
import '../utils/peso_formatter.dart';

/// Provider central del carrito de ventas
class CarritoProvider extends ChangeNotifier {
  final List<ItemVenta> _items = [];
  // El descuento se guarda como regla (monto fijo o porcentaje) y se
  // recalcula siempre sobre el subtotal actual, para que no quede
  // desfasado si cambian las cantidades o se elimina un producto.
  bool _descuentoEsPorcentaje = false;
  double _descuentoValor = 0;
  final _uuid = const Uuid();

  List<ItemVenta> get items => List.unmodifiable(_items);
  int get totalItems =>
      _items.fold(0, (s, i) => s + (i.esPeso ? 1 : i.cantidad));
  bool get isEmpty => _items.isEmpty;

  double get subtotal => _items.fold(0.0, (s, i) => s + i.subtotal);
  double get descuento {
    final sub = subtotal;
    final d = _descuentoEsPorcentaje
        ? sub * (_descuentoValor.clamp(0.0, 100.0) / 100.0)
        : _descuentoValor;
    return _redondear(d.clamp(0.0, sub).toDouble());
  }

  double get total =>
      _redondear((subtotal - descuento).clamp(0.0, double.infinity).toDouble());

  static double _redondear(double v) => (v * 100).roundToDouble() / 100;

  int cantidadEnCarrito(String productoId) {
    final idx = _items.indexWhere((i) => i.productoId == productoId);
    if (idx < 0) return 0;
    return _items[idx].cantidad;
  }

  /// Cantidad ya presente en el carrito para una combinación específica
  /// de talla/color de un producto.
  int cantidadEnCarritoVariante(String productoId, String talla, String color) {
    final idx = _items.indexWhere((i) =>
        i.productoId == productoId &&
        i.varianteTalla == talla &&
        i.varianteColor == color);
    if (idx < 0) return 0;
    return _items[idx].cantidad;
  }

  double _subtotalDesdeItem(ItemVenta item, int cantidad) {
    if (item.esPeso) {
      return PesoFormatter.subtotal(
        gramos: cantidad,
        precioPorKg: item.precioUnitario,
      );
    }
    return (item.precioUnitario + item.extrasPorUnidad) * cantidad;
  }

  /// Agrega un producto al carrito.
  ///
  /// Si [variante] viene informada, la línea queda asociada a esa
  /// combinación de talla/color. Si [tamano] viene informado, su precio
  /// reemplaza el precio base del producto; [opcionesElegidas] suma sus
  /// precios extra al subtotal. En todos los casos se agrupa en la misma
  /// línea solo si ya existe una con exactamente la misma combinación.
  void agregarProducto(
    Producto producto, {
    int cantidad = 1,
    VarianteProducto? variante,
    TamanoProducto? tamano,
    List<OpcionElegida> opcionesElegidas = const [],
  }) {
    final firmaExtras = OpcionElegida.firma(opcionesElegidas);
    final idx = _items.indexWhere((i) =>
        i.productoId == producto.id &&
        i.varianteTalla == variante?.talla &&
        i.varianteColor == variante?.color &&
        i.tamanoNombre == tamano?.nombre &&
        i.firmaExtras == firmaExtras);
    if (idx >= 0) {
      final item = _items[idx];
      final nuevaCant = item.cantidad + cantidad;
      _items[idx] = item.copyWith(
        cantidad: nuevaCant,
        subtotal: _subtotalDesdeItem(item, nuevaCant),
      );
    } else {
      final nuevo = ItemVenta(
        id: _uuid.v4(),
        ventaId: '',
        productoId: producto.id,
        productoNombre: producto.nombre,
        codigoBarras: variante?.codigoBarras ?? producto.codigoBarras,
        precioUnitario: tamano?.precio ?? producto.precioVenta,
        precioCompra: producto.precioCompra,
        cantidad: cantidad,
        subtotal: 0,
        tipoVenta: producto.tipoVenta,
        imagenUrl: producto.imagenUrl,
        varianteTalla: variante?.talla,
        varianteColor: variante?.color,
        varianteColorHex: variante?.colorHex,
        tamanoNombre: tamano?.nombre,
        conjuntosElegidos: opcionesElegidas,
      );
      _items.add(nuevo.copyWith(subtotal: _subtotalDesdeItem(nuevo, cantidad)));
    }
    notifyListeners();
  }

  void actualizarCantidad(int index, int cantidad) {
    if (index < 0 || index >= _items.length || cantidad < 1) return;
    final item = _items[index];
    _items[index] = item.copyWith(
      cantidad: cantidad,
      subtotal: _subtotalDesdeItem(item, cantidad),
    );
    notifyListeners();
  }

  void eliminarItem(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    notifyListeners();
  }

  /// Descuento como monto fijo en moneda.
  void setDescuento(double desc) {
    _descuentoEsPorcentaje = false;
    _descuentoValor = desc < 0 ? 0 : desc;
    notifyListeners();
  }

  /// Descuento como regla: [porcentaje] true = %, false = monto fijo.
  void setDescuentoRegla({required bool porcentaje, required double valor}) {
    _descuentoEsPorcentaje = porcentaje;
    _descuentoValor = valor < 0 ? 0 : valor;
    notifyListeners();
  }

  void limpiar() {
    _items.clear();
    _descuentoValor = 0;
    _descuentoEsPorcentaje = false;
    notifyListeners();
  }

  Future<Venta> finalizarVenta({
    required String metodoPago,
    double? montoPagado,
    String? nota,
  }) async {
    final ventaId = _uuid.v4();
    final descuentoFinal = descuento;
    final totalFinal = total;
    final subtotalFinal = subtotal;
    final itemsConVentaId =
        _items.map((i) => i.copyWith(ventaId: ventaId)).toList();

    double? vuelto;
    if (metodoPago == 'efectivo' && montoPagado != null) {
      vuelto = _redondear(montoPagado - totalFinal);
    }

    final venta = Venta(
      id: ventaId,
      items: itemsConVentaId,
      subtotal: subtotalFinal,
      descuento: descuentoFinal,
      total: totalFinal,
      metodoPago: metodoPago,
      montoPagado: montoPagado,
      vuelto: vuelto,
      nota: (nota != null && nota.trim().isNotEmpty) ? nota.trim() : null,
    );

    await DatabaseService.instance.registrarVenta(venta);
    limpiar();
    return venta;
  }
}
