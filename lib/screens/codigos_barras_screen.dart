import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/producto.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/barcode_generator.dart';
import '../utils/barcode_image_exporter.dart';
import '../utils/barcode_pdf_exporter.dart';
import '../utils/safe_area_padding.dart';

/// Catálogo visual de los códigos de barras de todos los productos del
/// inventario: se puede descargar o imprimir cada uno por separado, elegir
/// varios con el check, y exportar todo (o solo lo elegido) en un PDF con
/// las etiquetas acomodadas en filas de 3.
class CodigosBarrasScreen extends StatefulWidget {
  const CodigosBarrasScreen({super.key});

  @override
  State<CodigosBarrasScreen> createState() => _CodigosBarrasScreenState();
}

class _CodigosBarrasScreenState extends State<CodigosBarrasScreen> {
  final _db = DatabaseService.instance;
  List<Producto> _productos = [];
  final Set<String> _seleccionados = {};
  bool _cargando = true;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _cargando = true);
    final productos = await _db.obtenerProductos();
    if (!mounted) return;
    setState(() {
      _productos = productos
          .where((p) =>
              p.codigoBarras.trim().isNotEmpty ||
              p.variantes.any((v) => (v.codigoBarras ?? '').trim().isNotEmpty))
          .toList();
      _cargando = false;
    });
  }

  bw.Barcode _tipoParaCodigo(String codigo) {
    if (BarcodeGenerator.esEAN13Valido(codigo)) return bw.Barcode.ean13();
    if (RegExp(r'^\d{12}$').hasMatch(codigo)) return bw.Barcode.upcA();
    return bw.Barcode.code128();
  }

  void _avisar(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  void _toggleSeleccion(String productoId) {
    setState(() {
      if (_seleccionados.contains(productoId)) {
        _seleccionados.remove(productoId);
      } else {
        _seleccionados.add(productoId);
      }
    });
  }

  /// Los productos sobre los que actúa "Descargar todos": los elegidos con
  /// el check, o todos si no hay ninguno marcado.
  List<Producto> get _productosParaExportar => _seleccionados.isEmpty
      ? _productos
      : _productos.where((p) => _seleccionados.contains(p.id)).toList();

  /// El primer código disponible para acciones rápidas (descargar/imprimir
  /// uno solo): el principal del producto, o si no tiene, el de su primera
  /// variante con código propio.
  String _codigoParaAccionRapida(Producto p) {
    final principal = BarcodePdfExporter.codigoPrincipal(p);
    if (principal.isNotEmpty) return principal;
    for (final v in p.variantes) {
      final codigo = (v.codigoBarras ?? '').trim();
      if (codigo.isNotEmpty) return codigo;
    }
    return '';
  }

  Future<void> _descargarUno(Producto p) async {
    final codigo = _codigoParaAccionRapida(p);
    if (codigo.isEmpty) {
      _avisar('Este producto no tiene código de barras', AppTheme.warning);
      return;
    }
    try {
      final path = await BarcodeImageExporter.generarPng(
        codigo: codigo,
        nombreProducto: p.nombre,
      );
      await Share.shareXFiles([XFile(path)], text: 'Código de barras · ${p.nombre}');
    } catch (_) {
      if (mounted) _avisar('No se pudo generar el código', AppTheme.error);
    }
  }

  Future<void> _imprimirUno(Producto p) async {
    try {
      final doc = await BarcodePdfExporter.generar([p]);
      await Printing.layoutPdf(onLayout: (_) => doc.save());
    } catch (_) {
      if (mounted) _avisar('No se pudo preparar la impresión', AppTheme.error);
    }
  }

  Future<void> _exportarPdf() async {
    final productos = _productosParaExportar;
    if (productos.isEmpty) {
      _avisar('No hay productos con código de barras', AppTheme.warning);
      return;
    }
    setState(() => _exportando = true);
    try {
      final doc = await BarcodePdfExporter.generar(productos);
      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'codigos_barras.pdf');
    } catch (_) {
      if (mounted) _avisar('No se pudo generar el PDF', AppTheme.error);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayAlgunaSeleccion = _seleccionados.isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Códigos de barras'),
        actions: [
          TextButton.icon(
            onPressed: _cargando || _exportando ? null : _exportarPdf,
            icon: _exportando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primary, size: 20),
            label: Text(
              hayAlgunaSeleccion ? 'Descargar (${_seleccionados.length})' : 'Descargar todos',
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _productos.isEmpty
              ? const Center(
                  child: Text(
                    'No hay productos con código de barras todavía',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: listBottomPadding(context),
                  itemCount: _productos.length,
                  itemBuilder: (_, i) {
                    final p = _productos[i];
                    final codigo = BarcodePdfExporter.codigoPrincipal(p);
                    final seleccionado = _seleccionados.contains(p.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: seleccionado ? AppTheme.primary : AppTheme.border,
                          width: seleccionado ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: seleccionado,
                                onChanged: (_) => _toggleSeleccion(p.id),
                                activeColor: AppTheme.primary,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.nombre,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    Text(
                                      p.categoria?.trim().isNotEmpty == true ? p.categoria! : 'Sin categoría',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _descargarUno(p),
                                icon: const Icon(Icons.download_outlined, color: AppTheme.textPrimary),
                                tooltip: 'Descargar',
                              ),
                              IconButton(
                                onPressed: () => _imprimirUno(p),
                                icon: const Icon(Icons.print_outlined, color: AppTheme.textPrimary),
                                tooltip: 'Imprimir',
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (codigo.isNotEmpty)
                            Center(
                              child: bw.BarcodeWidget(
                                barcode: _tipoParaCodigo(codigo),
                                data: codigo,
                                width: 260,
                                height: 90,
                                drawText: true,
                                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                              ),
                            ),
                          for (final v in p.variantes)
                            if ((v.codigoBarras ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.etiqueta,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Center(
                                      child: bw.BarcodeWidget(
                                        barcode: _tipoParaCodigo(v.codigoBarras!.trim()),
                                        data: v.codigoBarras!.trim(),
                                        width: 260,
                                        height: 90,
                                        drawText: true,
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
