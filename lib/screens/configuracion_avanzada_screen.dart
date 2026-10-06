import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../utils/safe_area_padding.dart';
import '../services/database_service.dart';
import '../services/printer_service.dart';
import '../utils/metodos_pago_config.dart';
import '../models/producto.dart';
import '../utils/tallas_colores_config.dart';
import '../utils/tamanos_variantes_config.dart';
import 'tallas_colores_screen.dart';
import 'tamanos_variantes_screen.dart';
import 'codigos_barras_screen.dart';

/// Pantalla "Configuración avanzada".
///
/// El apartado de Respaldo permite descargar el catálogo completo con
/// imágenes (.zip), descargar la INFO de la tienda (.zip aparte) y subir
/// cualquiera de los dos (o un Excel) para restaurar o actualizar.
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
  bool _generandoInfo = false;
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
    'IMAGEN',
  ];

  /// Nombres alternativos aceptados al leer un Excel importado, para
  /// soportar tanto el archivo de "Descargar" (catálogo) como el de
  /// el respaldo, sin importar el orden de las columnas.
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
    'imagen': ['IMAGEN', 'FOTO'],
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

  /// Pregunta qué hacer con el archivo generado: descargarlo en el
  /// teléfono (selector de carpetas del sistema) o compartirlo
  /// (WhatsApp, correo, etc.).
  Future<void> _guardarEnDispositivo(
    List<int> bytes,
    String nombreArchivo,
    String textoCompartir,
  ) async {
    if (!mounted) return;

    Future<void> compartir() async {
      final dir = await getApplicationDocumentsDirectory();
      final copia = '${dir.path}/$nombreArchivo';
      await File(copia).writeAsBytes(bytes);
      final resultado = await Share.shareXFiles(
        [XFile(copia)],
        text: textoCompartir,
      );
      if (resultado.status != ShareResultStatus.dismissed) {
        _mostrarAviso('Compartido', AppTheme.success);
      }
    }

    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '¿Qué quieres hacer con el archivo?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppTheme.primary),
              title: const Text('Descargar en el teléfono'),
              onTap: () => Navigator.pop(ctx, 'guardar'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: AppTheme.primary),
              title: const Text('Compartir'),
              onTap: () => Navigator.pop(ctx, 'compartir'),
            ),
          ],
        ),
      ),
    );
    if (opcion == null || !mounted) return;

    if (opcion == 'compartir') {
      await compartir();
      return;
    }

    final ruta = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar respaldo',
      fileName: nombreArchivo,
      bytes: Uint8List.fromList(bytes),
    );
    if (!mounted) return;
    if (ruta == null) {
      _mostrarAviso('Guardado cancelado', AppTheme.warning);
      return;
    }
    _mostrarAviso('Guardado en el teléfono', AppTheme.success);
  }

  /// Extensión en minúsculas de una ruta o nombre de archivo (jpg por
  /// defecto si no se puede determinar).
  String _extension(String ruta) {
    final punto = ruta.lastIndexOf('.');
    final barra = ruta.lastIndexOf('/');
    if (punto == -1 || punto < barra) return 'jpg';
    final ext = ruta.substring(punto + 1).toLowerCase();
    return (ext.isEmpty || ext.length > 5) ? 'jpg' : ext;
  }

  /// Guarda una imagen importada dentro de la carpeta de la app y
  /// devuelve su ruta definitiva. Lleva marca de tiempo para que Flutter
  /// no muestre una versión vieja en caché.
  Future<String> _guardarImagenImportada(
    String idProducto,
    String nombreEnZip,
    List<int> bytes,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/imagenes_productos')
      ..createSync(recursive: true);
    final ruta = '${carpeta.path}/${idProducto}_'
        '${DateTime.now().millisecondsSinceEpoch}.${_extension(nombreEnZip)}';
    await File(ruta).writeAsBytes(bytes);
    return ruta;
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
      final archivoZip = Archive();
      var imagenesIncluidas = 0;
      for (final p in productos) {
        // Si el producto tiene foto y el archivo existe, va dentro del
        // zip como imagenes/<id>.<ext> y se anota en la columna IMAGEN.
        var nombreImagen = '';
        final rutaImagen = p.imagenUrl;
        if (rutaImagen != null && rutaImagen.isNotEmpty) {
          final archivoImagen = File(rutaImagen);
          if (await archivoImagen.exists()) {
            final bytesImagen = await archivoImagen.readAsBytes();
            nombreImagen = 'imagenes/${p.id}.${_extension(rutaImagen)}';
            archivoZip.addFile(
              ArchiveFile(nombreImagen, bytesImagen.length, bytesImagen),
            );
            imagenesIncluidas++;
          }
        }
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
          TextCellValue(nombreImagen),
        ]);
      }

      final excelBytes = excel.save()!;
      archivoZip.addFile(
        ArchiveFile('Catalogo.xlsx', excelBytes.length, excelBytes),
      );
      final zipBytes = ZipEncoder().encode(archivoZip);
      if (zipBytes == null) {
        _mostrarAviso('No se pudo crear el respaldo', AppTheme.error);
        return;
      }

      final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await _guardarEnDispositivo(
        zipBytes,
        'SzrVentas_Respaldo_$fecha.zip',
        'Respaldo completo (catálogo + $imagenesIncluidas imágenes) - Szr Ventas',
      );
    } catch (e) {
      _mostrarAviso('Error al descargar: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  /// Descarga la INFO de la tienda (datos del negocio, logo, QR de pago,
  /// métodos de pago, vendedores y categorías) en un .zip aparte del
  /// respaldo de productos.
  Future<void> _descargarInfo() async {
    if (_generandoInfo) return;
    setState(() => _generandoInfo = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final archivoZip = Archive();

      Future<String> agregarImagen(String? ruta, String base) async {
        if (ruta == null || ruta.isEmpty) return '';
        final archivo = File(ruta);
        if (!await archivo.exists()) return '';
        final bytes = await archivo.readAsBytes();
        final nombre = 'imagenes/$base.${_extension(ruta)}';
        archivoZip.addFile(ArchiveFile(nombre, bytes.length, bytes));
        return nombre;
      }

      final info = <String, dynamic>{
        'version': 1,
        'nombre': prefs.getString('negocio_nombre') ?? '',
        'direccion': prefs.getString('negocio_direccion') ?? '',
        'telefono': prefs.getString('negocio_telefono') ?? '',
        'ruc': prefs.getString('negocio_ruc') ?? '',
        'mensaje': prefs.getString('negocio_mensaje') ?? '',
        'monedaSimbolo': (prefs.getString('moneda_simbolo')?.trim().isNotEmpty ?? false) ? prefs.getString('moneda_simbolo')!.trim() : 'S/',
        'anchoPapel': prefs.getDouble('impresora_ancho') ?? 58.0,
        'metodosPago': prefs.getStringList(MetodosPagoConfig.prefsKey) ??
            MetodosPagoConfig.todos,
        'vendedores': prefs.getStringList('vendedores') ?? <String>[],
        'vendedorActivo': prefs.getString('vendedor_activo') ?? '',
        'categorias': await _db.obtenerCategorias(),
        'logo': await agregarImagen(prefs.getString('negocio_logo_path'), 'logo'),
        'yapeQr': await agregarImagen(prefs.getString('yape_qr_path'), 'yape_qr'),
        'plinQr': await agregarImagen(prefs.getString('plin_qr_path'), 'plin_qr'),
      };

      final jsonBytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert(info));
      archivoZip.addFile(ArchiveFile('info.json', jsonBytes.length, jsonBytes));
      final zipBytes = ZipEncoder().encode(archivoZip);
      if (zipBytes == null) {
        _mostrarAviso('No se pudo crear el archivo de INFO', AppTheme.error);
        return;
      }

      final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await _guardarEnDispositivo(
        zipBytes,
        'SzrVentas_Info_$fecha.zip',
        'INFO de la tienda - Szr Ventas',
      );
    } catch (e) {
      _mostrarAviso('Error al generar la INFO: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _generandoInfo = false);
    }
  }

  /// Restaura la INFO de la tienda desde un `info.json` (y sus imágenes)
  /// leído de un .zip. Devuelve un texto corto para mostrar al usuario.
  Future<String> _restaurarInfo(
    Map<String, dynamic> info,
    Map<String, List<int>> imagenes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();

    String? texto(String clave) {
      final v = info[clave];
      return v is String ? v : null;
    }

    Future<void> guardarTexto(String clavePrefs, String claveInfo) async {
      final v = texto(claveInfo);
      if (v != null) await prefs.setString(clavePrefs, v);
    }

    Future<void> restaurarImagen(String claveInfo, String clavePrefs, String base) async {
      final nombreZip = texto(claveInfo);
      if (nombreZip == null || nombreZip.isEmpty) return;
      final bytes = imagenes[nombreZip];
      if (bytes == null) return;
      final ruta = '${dir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}'
          '.${_extension(nombreZip)}';
      await File(ruta).writeAsBytes(bytes);
      final anterior = prefs.getString(clavePrefs);
      await prefs.setString(clavePrefs, ruta);
      if (anterior != null && anterior != ruta && anterior.startsWith(dir.path)) {
        try {
          final viejo = File(anterior);
          if (await viejo.exists()) await viejo.delete();
        } catch (_) {}
      }
    }

    await guardarTexto('negocio_nombre', 'nombre');
    await guardarTexto('negocio_direccion', 'direccion');
    await guardarTexto('negocio_telefono', 'telefono');
    await guardarTexto('negocio_ruc', 'ruc');
    await guardarTexto('negocio_mensaje', 'mensaje');
    final simboloImportado = texto('monedaSimbolo')?.trim();
    await prefs.setString(
      'moneda_simbolo',
      (simboloImportado == null || simboloImportado.isEmpty) ? 'S/' : simboloImportado,
    );
    await guardarTexto('vendedor_activo', 'vendedorActivo');

    final ancho = info['anchoPapel'];
    if (ancho is num) await prefs.setDouble('impresora_ancho', ancho.toDouble());

    final metodos = info['metodosPago'];
    if (metodos is List) {
      await prefs.setStringList(
        MetodosPagoConfig.prefsKey,
        metodos.map((e) => e.toString()).toList(),
      );
    }
    final vendedores = info['vendedores'];
    if (vendedores is List) {
      await prefs.setStringList(
        'vendedores',
        vendedores.map((e) => e.toString()).toList(),
      );
    }

    final categorias = info['categorias'];
    if (categorias is List) {
      final existentes =
          (await _db.obtenerCategorias()).map((c) => c.toLowerCase()).toSet();
      for (final c in categorias.map((e) => e.toString())) {
        if (c.trim().isEmpty || existentes.contains(c.toLowerCase())) continue;
        await _db.agregarCategoria(c);
        existentes.add(c.toLowerCase());
      }
    }

    await restaurarImagen('logo', 'negocio_logo_path', 'negocio_logo');
    await restaurarImagen('yapeQr', 'yape_qr_path', 'yape_qr');
    await restaurarImagen('plinQr', 'plin_qr_path', 'plin_qr');

    await PrinterService.instance.cargarDesdePrefs();
    return 'INFO de la tienda restaurada. ';
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

  /// Lee la imagen de un producto de la tienda web: puede ser un enlace
  /// (Supabase) o una imagen incrustada (`data:`). Devuelve extensión ->
  /// bytes, o null si no se pudo obtener.
  Future<MapEntry<String, List<int>>?> _leerImagenWeb(
    String imagen,
    HttpClient cliente,
  ) async {
    try {
      if (imagen.startsWith('data:')) {
        final datos = UriData.parse(imagen);
        final mime = datos.mimeType;
        final ext = mime.contains('png')
            ? 'png'
            : mime.contains('webp')
                ? 'webp'
                : 'jpg';
        return MapEntry(ext, datos.contentAsBytes());
      }
      if (!imagen.startsWith('http')) return null;
      final uri = Uri.parse(imagen);
      final req = await cliente.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final acumulado = BytesBuilder(copy: false);
      await for (final trozo in resp.timeout(const Duration(seconds: 30))) {
        acumulado.add(trozo);
      }
      return MapEntry(_extension(uri.path), acumulado.takeBytes());
    } catch (_) {
      return null;
    }
  }

  /// Importa la copia de seguridad (.json) descargada de la tienda web:
  /// crea o actualiza productos y categorías, y descarga las fotos.
  /// Los productos existentes conservan su precio de compra, stock mínimo
  /// y códigos de barras (la web no maneja esos datos).
  Future<void> _importarCopiaWeb(List<int> bytes) async {
    dynamic datos;
    try {
      datos = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      datos = null;
    }
    if (datos is! Map || datos['prods'] is! List) {
      _mostrarAviso(
        'El .json no es una copia de seguridad de la tienda web',
        AppTheme.error,
      );
      return;
    }

    final nombresCategoria = <String, String>{};
    final listaCats = datos['cats'];
    if (listaCats is List) {
      for (final c in listaCats) {
        if (c is Map && c['id'] != null) {
          nombresCategoria[c['id'].toString()] =
              (c['name'] ?? '').toString().trim();
        }
      }
    }

    final categoriasExistentes = (await _db.obtenerCategorias())
        .map((c) => c.toLowerCase())
        .toSet();
    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    var creados = 0;
    var actualizados = 0;
    var fotosFallidas = 0;
    final errores = <String>[];

    try {
      for (final raw in datos['prods'] as List) {
        if (raw is! Map) continue;
        final nombre = (raw['name'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;

        try {
          final idWeb = (raw['id'] ?? '').toString().trim();
          final categoria = nombresCategoria[(raw['cat'] ?? '').toString()] ?? '';
          final descripcion = (raw['desc'] ?? '').toString().trim();
          final precioVenta = raw['price'] is num
              ? (raw['price'] as num).toDouble()
              : double.tryParse('${raw['price']}'.replaceAll(',', '.')) ?? 0;
          final stock = raw['stock'] is num
              ? (raw['stock'] as num).round()
              : int.tryParse('${raw['stock']}') ?? 0;
          final imagen = (raw['image'] ?? '').toString();

          if (categoria.isNotEmpty &&
              !categoriasExistentes.contains(categoria.toLowerCase())) {
            await _db.agregarCategoria(categoria);
            categoriasExistentes.add(categoria.toLowerCase());
          }

          // Primero por ID (si ya se importó antes) y si no, por nombre.
          Producto? existente;
          if (idWeb.isNotEmpty) existente = await _db.obtenerProducto(idWeb);
          existente ??= (await _db.buscarProductos(nombre))
              .cast<Producto?>()
              .firstWhere(
                (p) => p!.nombre.toLowerCase() == nombre.toLowerCase(),
                orElse: () => null,
              );

          final idDestino =
              existente?.id ?? (idWeb.isNotEmpty ? idWeb : const Uuid().v4());

          String? rutaImagen;
          if (imagen.isNotEmpty) {
            final leida = await _leerImagenWeb(imagen, cliente);
            if (leida != null) {
              rutaImagen = await _guardarImagenImportada(
                idDestino,
                'foto.${leida.key}',
                leida.value,
              );
            } else {
              fotosFallidas++;
            }
          }

          if (existente != null) {
            await _db.actualizarProducto(
              existente.copyWith(
                nombre: nombre,
                descripcion: descripcion.isNotEmpty ? descripcion : existente.descripcion,
                categoria: categoria.isNotEmpty ? categoria : existente.categoria,
                precioVenta: precioVenta,
                stock: stock,
                imagenUrl: rutaImagen,
                fechaActualizacion: DateTime.now(),
              ),
            );
            actualizados++;
          } else {
            await _db.insertarProducto(
              Producto(
                id: idDestino,
                codigoBarras: '',
                nombre: nombre,
                descripcion: descripcion.isEmpty ? null : descripcion,
                categoria: categoria.isEmpty ? null : categoria,
                precioCompra: 0,
                precioVenta: precioVenta,
                stock: stock,
                imagenUrl: rutaImagen,
              ),
            );
            creados++;
          }
        } catch (e) {
          errores.add('"$nombre": $e');
        }
      }
    } finally {
      cliente.close(force: true);
    }

    if (!mounted) return;
    final resumen = '$creados creados, $actualizados actualizados'
        '${fotosFallidas > 0 ? ', $fotosFallidas fotos no se pudieron descargar' : ''}'
        '${errores.isNotEmpty ? ', ${errores.length} con error' : ''}';
    _mostrarAviso(
      'Copia de la web importada: $resumen',
      (errores.isEmpty && fotosFallidas == 0)
          ? AppTheme.success
          : AppTheme.warning,
    );
    if (errores.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Errores al importar'),
          content: SingleChildScrollView(child: Text(errores.join('\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _subirRespaldo() async {
    if (_importando) return;

    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'zip', 'json'],
      withData: true,
    );
    if (resultado == null || resultado.files.single.bytes == null) return;

    setState(() => _importando = true);
    int creados = 0;
    int actualizados = 0;
    final errores = <String>[];
    var infoResumen = '';

    try {
      final extension = (resultado.files.single.extension ?? '').toLowerCase();
      if (extension == 'json') {
        // Copia de seguridad descargada desde la tienda web.
        await _importarCopiaWeb(resultado.files.single.bytes!);
        return;
      }

      var bytes = resultado.files.single.bytes!;
      // Imágenes que vienen dentro de un .zip (nombre -> bytes).
      final imagenesZip = <String, List<int>>{};
      Map<String, dynamic>? infoJson;
      final esZip = extension == 'zip';
      if (esZip) {
        final contenido = ZipDecoder().decodeBytes(bytes);
        List<int>? excelEnZip;
        for (final f in contenido) {
          if (!f.isFile) continue;
          final nombre = f.name.replaceAll('\\', '/');
          final datos = f.content as List<int>;
          final minusculas = nombre.toLowerCase();
          if (minusculas.endsWith('.xlsx') && excelEnZip == null) {
            excelEnZip = datos;
          } else if (minusculas == 'info.json') {
            infoJson = jsonDecode(utf8.decode(datos)) as Map<String, dynamic>;
          } else {
            imagenesZip[nombre] = datos;
          }
        }
        if (excelEnZip == null && infoJson == null) {
          _mostrarAviso(
            'El .zip no trae productos (Excel) ni INFO de la tienda',
            AppTheme.error,
          );
          return;
        }
        if (infoJson != null) {
          infoResumen = await _restaurarInfo(infoJson, imagenesZip);
        }
        if (excelEnZip == null) {
          _mostrarAviso(infoResumen.trim(), AppTheme.success);
          return;
        }
        bytes = Uint8List.fromList(excelEnZip);
      }
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
          'El archivo no tiene la columna "NOMBRE". Usa el respaldo descargado desde la app.',
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
          final nombreImagen = _celda(fila, columnas['imagen']);
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

          // Si el respaldo trae la foto de este producto, se restaura.
          final nuevoId = const Uuid().v4();
          final idDestino = existente?.id ?? nuevoId;
          String? rutaImagen;
          final bytesImagen = imagenesZip[nombreImagen];
          if (nombreImagen.isNotEmpty && bytesImagen != null) {
            rutaImagen = await _guardarImagenImportada(
              idDestino,
              nombreImagen,
              bytesImagen,
            );
          }

          if (existente != null) {
            final actualizado = existente.copyWith(
              imagenUrl: rutaImagen,
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
              id: nuevoId,
              imagenUrl: rutaImagen,
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
        '${infoResumen}Importación completa: $resumen',
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
                  'Descargar respaldo: catálogo en Excel con las imágenes de los '
                  'productos (.zip). Descargar INFO: datos de la tienda, logo y '
                  'QR de pago (.zip aparte). Subir respaldo: sirve para ambos '
                  'archivos (.zip), para un Excel de productos o para la copia '
                  '(.json) de tu tienda web.',
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
                      _descargando ? 'Generando...' : 'Descargar respaldo',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _generandoInfo ? null : _descargarInfo,
                    icon: _generandoInfo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : const Icon(Icons.storefront_outlined),
                    label: Text(
                      _generandoInfo ? 'Generando...' : 'Descargar INFO',
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
                      _importando ? 'Importando...' : 'Subir respaldo',
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
