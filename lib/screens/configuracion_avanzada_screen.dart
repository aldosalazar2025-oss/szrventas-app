import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../utils/safe_area_padding.dart';
import '../services/database_service.dart';
import '../models/producto.dart';
import '../utils/tallas_colores_config.dart';
import '../utils/tamanos_variantes_config.dart';
import 'tallas_colores_screen.dart';
import 'tamanos_variantes_screen.dart';
import 'codigos_barras_screen.dart';

/// Pantalla "Configuración avanzada".
///
/// El apartado de Respaldo permite descargar el catálogo completo,
/// descargar una plantilla en Excel y subir un Excel (catálogo o
/// plantilla) para crear y/o actualizar productos en bloque.
/// El resto de opciones son la estructura visual definida en el
/// diseño de referencia; cada `onTap` muestra un aviso de
/// "próximamente" mientras se desarrolla su funcionalidad.
class ConfiguracionAvanzadaScreen extends StatefulWidget {
  const ConfiguracionAvanzadaScreen({super.key});

  @override
  State<ConfiguracionAvanzadaScreen> createState() =>
      _ConfiguracionAvanzadaScreenState();
}

class _ConfiguracionAvanzadaScreenState
    extends State<ConfiguracionAvanzadaScreen> {
  final _db = DatabaseService.instance;
  bool _descargando = false;
  bool _generandoPlantilla = false;
  bool _importando = false;
  bool _tallasColoresHabilitado = false;
  bool _tamanosVariantesHabilitado = false;

  @override
  void initState() {
    super.initState();
    _cargarEstadoTallasColores();
    _cargarEstadoTamanosVariantes();
  }

  Future<void> _cargarEstadoTallasColores() async {
    final habilitado = await TallasColoresConfig.estaHabilitado();
    if (mounted) setState(() => _tallasColoresHabilitado = habilitado);
  }

  Future<void> _cargarEstadoTamanosVariantes() async {
    final habilitado = await TamanosVariantesConfig.estaHabilitado();
    if (mounted) setState(() => _tamanosVariantesHabilitado = habilitado);
  }

  /// Encabezados del catálogo completo (incluye ID, variantes, origen
  /// y fechas para tener trazabilidad total de cada producto).
  static const List<String> _encabezadosCatalogo = [
    'ID',
    'NOMBRE',
    'CÓDIGOS DE BARRAS',
    'DESCRIPCIÓN',
    'CATEGORÍA',
    'PRECIO COMPRA',
    'PRECIO VENTA',
    'STOCK',
    'STOCK MÍNIMO',
    'TIPO VENTA',
    'VARIANTES',
    'ORIGEN',
    'FECHA CREACIÓN',
    'FECHA ACTUALIZACIÓN',
  ];

  /// Encabezados de la plantilla para llenado manual/importación masiva.
  static const List<String> _encabezadosPlantilla = [
    'NOMBRE',
    'CÓDIGOS DE BARRAS',
    'DESCRIPCIÓN',
    'CATEGORÍA',
    'PRECIO COMPRA',
    'PRECIO VENTA',
    'STOCK',
    'STOCK MÍNIMO',
    'TIPO VENTA',
  ];

  /// Nombres alternativos aceptados al leer un Excel importado, para
  /// soportar tanto el archivo de "Descargar" (catálogo) como el de
  /// "Plantilla", sin importar el orden de las columnas.
  static const Map<String, List<String>> _aliasEncabezados = {
    'id': ['ID'],
    'nombre': ['NOMBRE'],
    'codigos': ['CÓDIGOS DE BARRAS', 'CODIGOS DE BARRAS', 'CÓDIGO DE BARRAS', 'CODIGO DE BARRAS'],
    'descripcion': ['DESCRIPCIÓN', 'DESCRIPCION'],
    'categoria': ['CATEGORÍA', 'CATEGORIA'],
    'precioCompra': ['PRECIO COMPRA'],
    'precioVenta': ['PRECIO VENTA'],
    'stock': ['STOCK'],
    'stockMinimo': ['STOCK MÍNIMO', 'STOCK MINIMO'],
    'tipoVenta': ['TIPO VENTA'],
  };

  void _proximamente(String funcion) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$funcion estará disponible próximamente'),
        backgroundColor: AppTheme.info,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarAviso(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _tipoVentaLabel(Producto p) => p.esPeso ? 'peso' : 'unidad';

  /// Estilo del encabezado (verde de marca, texto blanco en negrita).
  CellStyle _estiloEncabezado() => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#12A100'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  /// Aplica el estilo de encabezado a la primera fila ya escrita con
  /// [appendRow] y define un ancho de columna cómodo para leer.
  void _estilizarEncabezado(Sheet hoja, List<String> encabezados) {
    final estilo = _estiloEncabezado();
    for (var c = 0; c < encabezados.length; c++) {
      hoja.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = estilo;
      hoja.setColumnWidth(c, encabezados[c].length < 14 ? 16 : 22);
    }
    hoja.setRowHeight(0, 22);
  }

  Future<String> _guardarYCompartir(
    Excel excel,
    String nombreArchivo,
    String textoCompartir,
  ) async {
    final fileBytes = excel.save();
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$nombreArchivo';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);
    await Share.shareXFiles([XFile(path)], text: textoCompartir);
    return path;
  }

  Future<void> _descargarCatalogo() async {
    if (_descargando) return;
    setState(() => _descargando = true);
    try {
      final productos = await _db.obtenerProductos();
      if (productos.isEmpty) {
        _mostrarAviso('No hay productos para descargar', AppTheme.warning);
        return;
      }

      var excel = Excel.createExcel();
      Sheet hoja = excel['Catálogo'];
      excel.setDefaultSheet('Catálogo');

      hoja.appendRow(_encabezadosCatalogo.map(TextCellValue.new).toList());
      _estilizarEncabezado(hoja, _encabezadosCatalogo);

      final df = DateFormat('dd/MM/yyyy HH:mm');
      for (final p in productos) {
        hoja.appendRow([
          TextCellValue(p.id),
          TextCellValue(p.nombre),
          TextCellValue(p.codigoBarras),
          TextCellValue(p.descripcion ?? ''),
          TextCellValue(p.categoria ?? ''),
          DoubleCellValue(p.precioCompra),
          DoubleCellValue(p.precioVenta),
          IntCellValue(p.stock),
          IntCellValue(p.stockMinimo),
          TextCellValue(_tipoVentaLabel(p)),
          TextCellValue(''), // Variantes: próximamente
          TextCellValue(''), // Origen: próximamente
          TextCellValue(df.format(p.fechaCreacion)),
          TextCellValue(df.format(p.fechaActualizacion)),
        ]);
      }

      final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await _guardarYCompartir(
        excel,
        'SzrVentas_Catalogo_$fecha.xlsx',
        'Catálogo de productos - Szr Ventas',
      );
    } catch (e) {
      _mostrarAviso('Error al descargar: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _descargarPlantilla() async {
    if (_generandoPlantilla) return;
    setState(() => _generandoPlantilla = true);
    try {
      var excel = Excel.createExcel();
      Sheet hoja = excel['Plantilla'];
      excel.setDefaultSheet('Plantilla');

      hoja.appendRow(_encabezadosPlantilla.map(TextCellValue.new).toList());
      _estilizarEncabezado(hoja, _encabezadosPlantilla);

      // Fila de ejemplo para guiar el llenado.
      hoja.appendRow([
        TextCellValue('Inca Kola 500ml'),
        TextCellValue('7750243009123'),
        TextCellValue('Bebida gaseosa sabor a fruta'),
        TextCellValue('Bebidas'),
        DoubleCellValue(2.50),
        DoubleCellValue(3.50),
        IntCellValue(24),
        IntCellValue(5),
        TextCellValue('unidad'),
      ]);
      final estiloEjemplo = CellStyle(
        italic: true,
        fontColorHex: ExcelColor.fromHexString('#5C6B60'),
        backgroundColorHex: ExcelColor.fromHexString('#EFF6ED'),
      );
      for (var c = 0; c < _encabezadosPlantilla.length; c++) {
        hoja.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1)).cellStyle = estiloEjemplo;
      }

      final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await _guardarYCompartir(
        excel,
        'SzrVentas_Plantilla_$fecha.xlsx',
        'Plantilla de productos - Szr Ventas',
      );
    } catch (e) {
      _mostrarAviso('Error al generar la plantilla: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _generandoPlantilla = false);
    }
  }

  /// Busca, dentro de la fila de encabezados leída, la columna que
  /// corresponde a cada campo lógico usando [_aliasEncabezados].
  Map<String, int> _mapearColumnas(List<Data?> filaEncabezado) {
    final encabezados = filaEncabezado
        .map((c) => (c?.value?.toString() ?? '').trim().toUpperCase())
        .toList();
    final mapa = <String, int>{};
    _aliasEncabezados.forEach((campo, alias) {
      for (final nombre in alias) {
        final idx = encabezados.indexOf(nombre.toUpperCase());
        if (idx != -1) {
          mapa[campo] = idx;
          break;
        }
      }
    });
    return mapa;
  }

  String _celda(List<Data?> fila, int? idx) {
    if (idx == null || idx >= fila.length) return '';
    return fila[idx]?.value?.toString().trim() ?? '';
  }

  double _celdaDouble(List<Data?> fila, int? idx) {
    final texto = _celda(fila, idx).replaceAll(',', '.');
    return double.tryParse(texto) ?? 0;
  }

  int _celdaInt(List<Data?> fila, int? idx) {
    final texto = _celda(fila, idx);
    return int.tryParse(texto) ?? double.tryParse(texto)?.round() ?? 0;
  }

  Future<void> _subirRespaldo() async {
    if (_importando) return;

    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (resultado == null || resultado.files.single.bytes == null) return;

    setState(() => _importando = true);
    int creados = 0;
    int actualizados = 0;
    final errores = <String>[];

    try {
      final bytes = resultado.files.single.bytes!;
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        _mostrarAviso('El archivo no tiene hojas con datos', AppTheme.error);
        return;
      }

      final hoja = excel.tables[excel.tables.keys.first]!;
      if (hoja.maxRows < 2) {
        _mostrarAviso('El archivo no tiene productos para importar', AppTheme.warning);
        return;
      }

      final columnas = _mapearColumnas(hoja.rows.first);
      if (!columnas.containsKey('nombre')) {
        _mostrarAviso(
          'El archivo no tiene la columna "NOMBRE". Usa la plantilla o el catálogo descargado.',
          AppTheme.error,
        );
        return;
      }

      final categoriasExistentes = (await _db.obtenerCategorias())
          .map((c) => c.toLowerCase())
          .toSet();

      for (var i = 1; i < hoja.rows.length; i++) {
        final fila = hoja.rows[i];
        final nombre = _celda(fila, columnas['nombre']);
        if (nombre.isEmpty) continue; // fila vacía o nota de ayuda

        try {
          final idCelda = _celda(fila, columnas['id']);
          final codigos = _celda(fila, columnas['codigos']);
          final descripcion = _celda(fila, columnas['descripcion']);
          final categoria = _celda(fila, columnas['categoria']);
          final precioCompra = _celdaDouble(fila, columnas['precioCompra']);
          final precioVenta = _celdaDouble(fila, columnas['precioVenta']);
          final stock = _celdaInt(fila, columnas['stock']);
          final stockMinimo = _celdaInt(fila, columnas['stockMinimo']);
          final tipoVentaTexto =
              _celda(fila, columnas['tipoVenta']).toLowerCase();
          final tipoVenta =
              tipoVentaTexto == 'peso' ? TipoVenta.peso : TipoVenta.unidad;

          if (categoria.isNotEmpty &&
              !categoriasExistentes.contains(categoria.toLowerCase())) {
            await _db.agregarCategoria(categoria);
            categoriasExistentes.add(categoria.toLowerCase());
          }

          // Busca el producto existente: primero por ID (si vino en el
          // archivo), y si no, por coincidencia de nombre o código de barras.
          Producto? existente;
          if (idCelda.isNotEmpty) {
            existente = await _db.obtenerProducto(idCelda);
          }
          if (existente == null && codigos.isNotEmpty) {
            final primerCodigo = codigos.split(',').first.trim();
            if (primerCodigo.isNotEmpty) {
              existente = await _db.buscarPorCodigoBarras(primerCodigo);
            }
          }
          existente ??= (await _db.buscarProductos(nombre)).cast<Producto?>().firstWhere(
                (p) => p!.nombre.toLowerCase() == nombre.toLowerCase(),
                orElse: () => null,
              );

          if (existente != null) {
            final actualizado = existente.copyWith(
              nombre: nombre,
              codigoBarras: codigos.isNotEmpty ? codigos : existente.codigoBarras,
              descripcion: descripcion.isNotEmpty ? descripcion : existente.descripcion,
              categoria: categoria.isNotEmpty ? categoria : existente.categoria,
              precioCompra: precioCompra,
              precioVenta: precioVenta,
              stock: stock,
              stockMinimo: stockMinimo > 0 ? stockMinimo : existente.stockMinimo,
              tipoVenta: tipoVenta,
              fechaActualizacion: DateTime.now(),
            );
            await _db.actualizarProducto(actualizado);
            actualizados++;
          } else {
            final nuevo = Producto(
              id: const Uuid().v4(),
              codigoBarras: codigos,
              nombre: nombre,
              descripcion: descripcion.isEmpty ? null : descripcion,
              categoria: categoria.isEmpty ? null : categoria,
              precioCompra: precioCompra,
              precioVenta: precioVenta,
              stock: stock,
              stockMinimo: stockMinimo > 0 ? stockMinimo : 5,
              tipoVenta: tipoVenta,
            );
            await _db.insertarProducto(nuevo);
            creados++;
          }
        } catch (e) {
          errores.add('Fila ${i + 1} ("$nombre"): $e');
        }
      }

      if (!mounted) return;
      final resumen = '$creados creados, $actualizados actualizados'
          '${errores.isNotEmpty ? ', ${errores.length} con error' : ''}';
      _mostrarAviso(
        'Importación completa: $resumen',
        errores.isEmpty ? AppTheme.success : AppTheme.warning,
      );
      if (errores.isNotEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Errores al importar'),
            content: SingleChildScrollView(
              child: Text(errores.join('\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _mostrarAviso('Error al leer el archivo: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración avanzada')),
      body: ListView(
        padding: listBottomPadding(context, bottomExtra: 24),
        children: [
          const SizedBox(height: 8),

          // Opciones individuales
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.checkroom_rounded,
                    color: AppTheme.primary,
                  ),
                  title: const Text(
                    'Tallas y colores',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _tallasColoresHabilitado
                        ? 'Para tiendas de ropa · Activado'
                        : 'Para tiendas de ropa · Desactivado',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textMuted,
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TallasColoresScreen(),
                      ),
                    );
                    _cargarEstadoTallasColores();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.restaurant_rounded,
                    color: AppTheme.primary,
                  ),
                  title: const Text(
                    'Tamaños y variantes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _tamanosVariantesHabilitado
                        ? 'Para restaurantes · Activado'
                        : 'Para restaurantes · Desactivado',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textMuted,
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TamanosVariantesScreen(),
                      ),
                    );
                    _cargarEstadoTamanosVariantes();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppTheme.primary,
                  ),
                  title: const Text(
                    'Ver códigos de barras',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Catálogo visual de cada producto',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textMuted,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CodigosBarrasScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Respaldo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Respaldo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Descarga todo lo actual, una plantilla para llenar, o '
                  'sube un Excel para añadir y actualizar productos.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _descargando ? null : _descargarCatalogo,
                    icon: _descargando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(
                      _descargando ? 'Generando...' : 'Descargar',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed:
                        _generandoPlantilla ? null : _descargarPlantilla,
                    icon: _generandoPlantilla
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : const Icon(Icons.table_chart_outlined),
                    label: Text(
                      _generandoPlantilla ? 'Generando...' : 'Plantilla',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _importando ? null : _subirRespaldo,
                    icon: _importando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _importando ? 'Importando...' : 'Subir respaldo o en masa',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
