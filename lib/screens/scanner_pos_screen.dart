import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../providers/carrito_provider.dart';
import '../utils/safe_area_padding.dart';
import '../utils/currency_formatter.dart';
import '../utils/peso_formatter.dart';
import '../utils/sound_player.dart';
import '../widgets/safe_bottom_bar.dart';
import '../widgets/peso_cantidad_dialog.dart';
import '../widgets/variante_selector_dialog.dart';
import '../widgets/variante_chips.dart';
import '../widgets/detalle_chips.dart';
import '../widgets/tamano_conjunto_selector_dialog.dart';
import '../models/producto.dart';
import '../models/tamano_producto.dart';
import '../models/variante_producto.dart';
import '../models/venta.dart';
import 'revisar_orden_screen.dart';
import 'inventario_screen.dart';
import 'historial_screen.dart';
import 'ajustes_screen.dart';

class ScannerPosScreen extends StatefulWidget {
  const ScannerPosScreen({super.key});
  @override
  State<ScannerPosScreen> createState() => _ScannerPosScreenState();
}

class _ScannerPosScreenState extends State<ScannerPosScreen> {
  final _db = DatabaseService.instance;
  late MobileScannerController _scannerCtrl;
  bool _torchOn = false;
  bool _cameraOn = true;
  String? _lastScanned;
  DateTime? _lastScanTime;
  String _monedaSimbolo = 'S/';

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
    _scannerCtrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  Future<void> _cargarAjustes() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _monedaSimbolo = prefs.getString('moneda_simbolo') ?? 'S/';
      });
    }
  }

  String _formatMoney(double amount) {
    return CurrencyFormatter.format(amount, _monedaSimbolo);
  }

  /// SnackBar flotante en la zona del escáner (arriba), sin tapar botones del carrito.
  EdgeInsets _margenSnackSuperior(BuildContext context) {
    final mq = MediaQuery.of(context);
    return EdgeInsets.fromLTRB(16, mq.padding.top + 56, 16, mq.size.height * 0.52);
  }

  void _mostrarSnackPos({
    required Widget content,
    required Color backgroundColor,
    Duration duration = const Duration(milliseconds: 1500),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: _margenSnackSuperior(context),
        action: action,
      ),
    );
  }

  void _mostrarProductoAgregado(String nombre, double precio) {
    _mostrarSnackPos(
      backgroundColor: AppTheme.success,
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('$nombre agregado')),
          Text(
            _formatMoney(precio),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _mostrarStockBajo(String nombre, String stockLabel) {
    _mostrarSnackPos(
      backgroundColor: AppTheme.warning,
      duration: const Duration(seconds: 2),
      content: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('$nombre — Stock bajo o agotado ($stockLabel)')),
        ],
      ),
    );
  }

  Future<void> _navigateTo(Widget screen) async {
    await _scannerCtrl.stop();
    if (mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }
    if (mounted) {
      _scannerCtrl.start();
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final code = barcode!.rawValue!;

    // Evitar escaneos duplicados rápidos
    if (_lastScanned == code &&
        _lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastScanned = code;
    _lastScanTime = DateTime.now();

    final producto = await _db.buscarPorCodigoBarras(code);
    if (!mounted) return;

    if (producto == null) {
      _mostrarProductoNoEncontrado(code);
      return;
    }

    if (producto.esPeso) {
      _mostrarSnackPos(
        backgroundColor: AppTheme.warning,
        duration: const Duration(seconds: 3),
        content: const Row(
          children: [
            Icon(Icons.scale_outlined, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Este producto se vende por peso desde el catálogo'),
            ),
          ],
        ),
      );
      return;
    }

    if (producto.tieneVariantes) {
      final carrito = context.read<CarritoProvider>();
      await _scannerCtrl.stop();
      final variante = await showVarianteSelectorDialog(
        context: context,
        producto: producto,
        enCarrito: (v) =>
            carrito.cantidadEnCarritoVariante(producto.id, v.talla, v.color),
      );
      if (mounted) _scannerCtrl.start();
      if (variante == null || !mounted) return;

      HapticFeedback.heavyImpact();
      SoundPlayer.ping();
      carrito.agregarProducto(producto, variante: variante);
      _feedbackProductoAgregado(producto, variante: variante);
      return;
    }

    if (producto.tieneTamanos || producto.conjuntos.isNotEmpty) {
      final carrito = context.read<CarritoProvider>();
      await _scannerCtrl.stop();
      final seleccion = await showTamanoConjuntoSelectorDialog(
        context: context,
        producto: producto,
      );
      if (mounted) _scannerCtrl.start();
      if (seleccion == null || !mounted) return;

      HapticFeedback.heavyImpact();
      SoundPlayer.ping();
      carrito.agregarProducto(
        producto,
        tamano: seleccion.tamano,
        opcionesElegidas: seleccion.opciones,
      );
      _feedbackProductoAgregado(producto, tamano: seleccion.tamano);
      return;
    }

    HapticFeedback.heavyImpact();
    SoundPlayer.ping();

    context.read<CarritoProvider>().agregarProducto(producto);

    if (producto.stock <= producto.stockMinimo) {
      _mostrarStockBajo(producto.nombre, producto.formatoStock);
    } else {
      _mostrarProductoAgregado(producto.nombre, producto.precioVenta);
    }
  }

  void _mostrarProductoNoEncontrado(String code) {
    _mostrarSnackPos(
      backgroundColor: AppTheme.warning,
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          const Icon(Icons.search_off, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Código $code no encontrado')),
        ],
      ),
      action: SnackBarAction(
        label: 'AGREGAR',
        textColor: Colors.white,
        onPressed: () {
          _navigateTo(InventarioScreen(codigoInicial: code));
        },
      ),
    );
  }

  void _toggleTorch() {
    _scannerCtrl.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _mostrarCatalogo(CarritoProvider carrito) async {
    final todosProductos = await _db.obtenerProductos();
    final categorias = await _db.obtenerCategorias();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        String? selectedCat;

        return StatefulBuilder(
          builder: (context, setState) {
            final productosFiltrados = todosProductos.where((p) {
              final matchesQuery = p.nombre.toLowerCase().contains(
                query.toLowerCase(),
              );
              final matchesCat =
                  selectedCat == null ||
                  selectedCat == 'Todas' ||
                  p.categoria == selectedCat;
              return matchesQuery && matchesCat;
            }).toList();

            return SafeArea(
              top: false,
              child: DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.bgLight,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Text(
                        'Catálogo de Productos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          onChanged: (v) => setState(() => query = v),
                          decoration: InputDecoration(
                            hintText: 'Buscar producto...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: AppTheme.bgWhite,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (categorias.isNotEmpty)
                        Container(
                          height: 50,
                          margin: const EdgeInsets.only(top: 12),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    'Todas',
                                    style: TextStyle(
                                      color:
                                          (selectedCat == null ||
                                              selectedCat == 'Todas')
                                          ? Colors.white
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                  selected:
                                      selectedCat == null ||
                                      selectedCat == 'Todas',
                                  selectedColor: AppTheme.primary,
                                  onSelected: (_) =>
                                      setState(() => selectedCat = 'Todas'),
                                ),
                              ),
                              ...categorias.map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(
                                      c,
                                      style: TextStyle(
                                        color: selectedCat == c
                                            ? Colors.white
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                    selected: selectedCat == c,
                                    selectedColor: AppTheme.primary,
                                    onSelected: (_) =>
                                        setState(() => selectedCat = c),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: productosFiltrados.isEmpty
                            ? const Center(
                                child: Text('No hay productos que coincidan'),
                              )
                            : GridView.builder(
                                controller: controller,
                                padding: listBottomPadding(context, bottomExtra: 16),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 0.65,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                itemCount: productosFiltrados.length,
                                itemBuilder: (context, i) {
                                  final p = productosFiltrados[i];
                                  return GestureDetector(
                                    onTap: () => _onCatalogTap(context, p, carrito),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppTheme.bgWhite,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(12),
                                                  ),
                                              child: p.imagenUrl != null
                                                  ? Image.file(
                                                      File(p.imagenUrl!),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Container(
                                                      color: AppTheme.primary
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      child: const Icon(
                                                        Icons.inventory_2,
                                                        color: AppTheme.primary,
                                                        size: 32,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    p.nombre,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    p.precioLabel(_formatMoney),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: AppTheme.primary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    p.formatoStock,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: p.stock <=
                                                              p.stockMinimo
                                                          ? AppTheme.error
                                                          : AppTheme
                                                                .textSecondary,
                                                      fontWeight: p.stock <=
                                                              p.stockMinimo
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
            );
          },
        );
      },
    );
  }

  Future<void> _onCatalogTap(
    BuildContext catalogContext,
    Producto p,
    CarritoProvider carrito,
  ) async {
    if (p.tieneVariantes) {
      final variante = await showVarianteSelectorDialog(
        context: catalogContext,
        producto: p,
        enCarrito: (v) =>
            carrito.cantidadEnCarritoVariante(p.id, v.talla, v.color),
      );
      if (variante == null || !mounted) return;
      HapticFeedback.heavyImpact();
      SoundPlayer.ping();
      carrito.agregarProducto(p, variante: variante);
      if (catalogContext.mounted) Navigator.pop(catalogContext);
      _feedbackProductoAgregado(p, variante: variante);
      return;
    }

    if (p.tieneTamanos || p.conjuntos.isNotEmpty) {
      final seleccion = await showTamanoConjuntoSelectorDialog(
        context: catalogContext,
        producto: p,
      );
      if (seleccion == null || !mounted) return;
      HapticFeedback.heavyImpact();
      SoundPlayer.ping();
      carrito.agregarProducto(
        p,
        tamano: seleccion.tamano,
        opcionesElegidas: seleccion.opciones,
      );
      if (catalogContext.mounted) Navigator.pop(catalogContext);
      _feedbackProductoAgregado(p, tamano: seleccion.tamano);
      return;
    }

    if (p.esPeso) {
      final enCarrito = carrito.cantidadEnCarrito(p.id);
      final disponible = p.stock - enCarrito;
      if (disponible <= 0) {
        _mostrarStockBajo(p.nombre, p.formatoStock);
        return;
      }
      final grams = await showPesoCantidadDialog(
        context: catalogContext,
        producto: p,
        monedaSimbolo: _monedaSimbolo,
        stockDisponible: disponible,
      );
      if (grams == null || !mounted) return;
      HapticFeedback.heavyImpact();
      SoundPlayer.ping();
      carrito.agregarProducto(p, cantidad: grams);
      if (catalogContext.mounted) Navigator.pop(catalogContext);
      _feedbackProductoAgregado(p);
      return;
    }

    HapticFeedback.heavyImpact();
    SoundPlayer.ping();
    carrito.agregarProducto(p);
    if (catalogContext.mounted) Navigator.pop(catalogContext);
    _feedbackProductoAgregado(p);
  }

  Future<void> _editarPesoCarrito(int index, ItemVenta item) async {
    final producto = await _db.obtenerProducto(item.productoId);
    if (!mounted) return;
    final stock = producto?.stock ?? item.cantidad;
    final grams = await showPesoCantidadDialog(
      context: context,
      producto: producto ??
          Producto(
            id: item.productoId,
            codigoBarras: item.codigoBarras,
            nombre: item.productoNombre,
            precioCompra: item.precioCompra,
            precioVenta: item.precioUnitario,
            stock: stock,
            tipoVenta: TipoVenta.peso,
          ),
      monedaSimbolo: _monedaSimbolo,
      stockDisponible: stock,
      cantidadInicial: item.cantidad,
    );
    if (grams == null || !mounted) return;
    context.read<CarritoProvider>().actualizarCantidad(index, grams);
  }

  void _feedbackProductoAgregado(
    Producto p, {
    VarianteProducto? variante,
    TamanoProducto? tamano,
  }) {
    final etiqueta = variante?.etiqueta ?? tamano?.nombre;
    final nombre = etiqueta != null ? '${p.nombre} ($etiqueta)' : p.nombre;
    final precio = tamano?.precio ?? p.precioVenta;
    final stockBajo =
        variante != null ? variante.stock <= p.stockMinimo : p.stock <= p.stockMinimo;
    final stockLabel = variante != null ? '${variante.stock} und' : p.formatoStock;
    if (stockBajo) {
      _mostrarStockBajo(nombre, stockLabel);
    } else {
      _mostrarProductoAgregado(nombre, precio);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CarritoProvider>(
      builder: (context, carrito, _) {
        return Scaffold(
          body: Column(
            children: [
              // ============ ESCÁNER (mitad superior) ============
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    // Cámara
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                      child: _cameraOn
                          ? MobileScanner(
                              controller: _scannerCtrl,
                              onDetect: _onDetect,
                            )
                          : Container(
                              color: AppTheme.bgGrey,
                              width: double.infinity,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.videocam_off_rounded,
                                    size: 64,
                                    color: AppTheme.textMuted.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Cámara en Pausa',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Presiona el botón para reactivar',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    // Overlay con esquinas
                    if (_cameraOn)
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                        child: CustomPaint(
                          painter: _ScanFramePainter(),
                          size: Size.infinite,
                        ),
                      ),

                    // Botones flotantes a la derecha
                    Positioned(
                      right: 16,
                      top: MediaQuery.of(context).padding.top + 12,
                      child: Column(
                        children: [
                          _buildFloatingBtn(
                            Icons.settings,
                            onTap: () => _navigateTo(const AjustesScreen()),
                          ),
                          const SizedBox(height: 12),
                          _buildFloatingBtn(
                            _torchOn ? Icons.flash_on : Icons.flash_off,
                            onTap: _toggleTorch,
                            active: _torchOn,
                          ),
                          const SizedBox(height: 12),
                          _buildFloatingBtn(
                            _cameraOn
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            onTap: () {
                              if (_cameraOn) {
                                _scannerCtrl.stop();
                              } else {
                                _scannerCtrl.start();
                              }
                              setState(() => _cameraOn = !_cameraOn);
                            },
                            active: !_cameraOn,
                          ),
                        ],
                      ),
                    ),

                    // Botón menú izquierda
                    Positioned(
                      left: 16,
                      top: MediaQuery.of(context).padding.top + 12,
                      child: Column(
                        children: [
                          _buildFloatingBtn(
                            Icons.menu,
                            onTap: () => _mostrarMenu(),
                          ),
                          const SizedBox(height: 12),
                          _buildFloatingBtn(
                            Icons.grid_view_rounded,
                            onTap: () => _mostrarCatalogo(carrito),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ============ LISTA DE ARTÍCULOS (mitad inferior) ============
              Expanded(
                flex: 6,
                child: Container(
                  color: AppTheme.bgWhite,
                  child: Column(
                    children: [
                      // Header: "Artículos Escaneados" + precio total
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Izquierda
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    children: [
                                      const Text(
                                        'Artículos',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (carrito.totalItems > 0)
                                        GestureDetector(
                                          onTap: () =>
                                              _confirmarLimpiar(carrito),
                                          child: const Text(
                                            'LIMPIAR',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.error,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${carrito.totalItems} items',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Derecha - Precio total
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  _formatMoney(carrito.total),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Lista de items o estado vacío
                      Expanded(
                        child: carrito.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: carrito.items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final item = carrito.items[i];
                                  return Dismissible(
                                    key: Key(item.id),
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (_) => carrito.eliminarItem(i),
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        color: AppTheme.error,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          // Ícono producto
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              image: item.imagenUrl != null
                                                  ? DecorationImage(
                                                      image: FileImage(
                                                        File(item.imagenUrl!),
                                                      ),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                            ),
                                            child: item.imagenUrl == null
                                                ? const Icon(
                                                    Icons.shopping_bag_outlined,
                                                    color: AppTheme.primary,
                                                    size: 20,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          // Nombre y precio unitario
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.productoNombre,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.esPeso
                                                      ? '${_formatMoney(item.precioUnitario)}/kg'
                                                      : _formatMoney(
                                                          item.precioUnitario,
                                                        ),
                                                  style: const TextStyle(
                                                    color:
                                                        AppTheme.textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (item.tieneVariante)
                                                  VarianteChips(item: item),
                                                DetalleChips(item: item),
                                              ],
                                            ),
                                          ),
                                          if (item.esPeso)
                                            GestureDetector(
                                              onTap: () =>
                                                  _editarPesoCarrito(i, item),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.bgGrey,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  PesoFormatter.formatKg(
                                                    item.cantidad,
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.bgGrey,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _buildQtyBtn(
                                                  Icons.remove,
                                                  () => item.cantidad > 1
                                                      ? carrito
                                                            .actualizarCantidad(
                                                              i,
                                                              item.cantidad - 1,
                                                            )
                                                      : carrito.eliminarItem(i),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  child: Text(
                                                    '${item.cantidad}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                                _buildQtyBtn(
                                                  Icons.add,
                                                  () => carrito
                                                      .actualizarCantidad(
                                                        i,
                                                        item.cantidad + 1,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Subtotal
                                          SizedBox(
                                            width: 65,
                                            child: Text(
                                              _formatMoney(item.subtotal),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppTheme.primary,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Botón "Revisar Orden"
                      SafeBottomBar(
                        decoration: BoxDecoration(
                          color: AppTheme.bgWhite,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: carrito.isEmpty
                                ? null
                                : () => _navigateTo(const RevisarOrdenScreen()),
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 20,
                            ),
                            label: const Text(
                              'Revisar Orden',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: carrito.isEmpty
                                  ? AppTheme.bgGrey
                                  : AppTheme.primary,
                              foregroundColor: carrito.isEmpty
                                  ? AppTheme.textMuted
                                  : Colors.white,
                              disabledBackgroundColor: AppTheme.bgGrey,
                              disabledForegroundColor: AppTheme.textMuted,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgGrey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 40,
              color: AppTheme.textHint,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lista vacía',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Los productos escaneados con la cámara\naparecerán en esta lista.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingBtn(
    IconData icon, {
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.warning
              : Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.bgWhite,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: AppTheme.textPrimary),
      ),
    );
  }

  void _confirmarLimpiar(CarritoProvider carrito) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar carrito'),
        content: const Text('¿Eliminar todos los artículos escaneados?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              carrito.limpiar();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }

  void _mostrarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Szr Ventas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildMenuItem(
                Icons.inventory_2_rounded,
                'Inventario',
                'Gestionar productos',
                () {
                  Navigator.pop(ctx);
                  _navigateTo(const InventarioScreen());
                },
              ),
              _buildMenuItem(
                Icons.history_rounded,
                'Historial de Ventas',
                'Ver ventas anteriores',
                () {
                  Navigator.pop(ctx);
                  _navigateTo(const HistorialScreen());
                },
              ),
              _buildMenuItem(
                Icons.settings_outlined,
                'Ajustes',
                'Configurar negocio e impresora',
                () {
                  Navigator.pop(ctx);
                  _navigateTo(const AjustesScreen());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }
}

// ============ PAINTER: Marco del escáner ============
class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final frameW = size.width * 0.72;
    final frameH = frameW;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY - 10),
      width: frameW,
      height: frameH,
    );

    // Fondo semi-transparente con hueco
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      bgPath,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Esquinas verdes
    final paint = Paint()
      ..color = AppTheme.scannerCorner
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 35.0;
    const radius = 16.0;

    // Top-left
    canvas.drawArc(
      Rect.fromLTWH(rect.left, rect.top, radius * 2, radius * 2),
      3.14,
      0.5,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + radius),
      Offset(rect.left, rect.top + len + radius),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left + radius, rect.top),
      Offset(rect.left + len + radius, rect.top),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(rect.right, rect.top + radius),
      Offset(rect.right, rect.top + len + radius),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right - radius, rect.top),
      Offset(rect.right - len - radius, rect.top),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(rect.left, rect.bottom - radius),
      Offset(rect.left, rect.bottom - len - radius),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left + radius, rect.bottom),
      Offset(rect.left + len + radius, rect.bottom),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(rect.right, rect.bottom - radius),
      Offset(rect.right, rect.bottom - len - radius),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right - radius, rect.bottom),
      Offset(rect.right - len - radius, rect.bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
