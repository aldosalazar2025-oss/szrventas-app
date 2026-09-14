import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../utils/safe_area_padding.dart';
import '../models/producto.dart';
import '../models/variante_producto.dart';
import '../services/database_service.dart';
import '../utils/peso_formatter.dart';
import '../utils/barcode_generator.dart';
import '../utils/barcode_image_exporter.dart';
import '../utils/tallas_colores_config.dart';
import '../utils/tamanos_variantes_config.dart';
import '../models/tamano_producto.dart';
import '../models/conjunto_opcion.dart';
import '../widgets/conjunto_dialogs.dart';
import 'scanner_screen.dart';

class ProductoFormScreen extends StatefulWidget {
  final Producto? producto;
  final String? codigoBarras;
  const ProductoFormScreen({super.key, this.producto, this.codigoBarras});
  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  static const TextStyle _valorStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
    color: AppTheme.textPrimary,
  );

  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseService.instance;
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _precioCompraCtrl;
  late final TextEditingController _precioVentaCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _stockMinimoCtrl;
  String? _categoriaSeleccionada;
  List<String> _categorias = [];
  String? _imagenUrl;
  bool _isEditing = false;
  bool _saving = false;
  String _tipoVenta = TipoVenta.unidad;

  bool _tallasColoresHabilitado = false;
  List<String> _tallasDisponibles = [];
  List<ColorOpcion> _coloresDisponibles = [];
  List<VarianteProducto> _variantes = [];

  bool _tamanosVariantesHabilitado = false;
  List<String> _tamanosDisponibles = [];
  List<ConjuntoOpcion> _conjuntosDisponibles = [];
  List<TamanoProducto> _tamanosProducto = [];
  List<ConjuntoOpcion> _conjuntosProducto = [];

  @override
  void initState() {
    super.initState();
    _isEditing = widget.producto != null;
    final p = widget.producto;
    _codigoCtrl = TextEditingController(text: p?.codigoBarras ?? widget.codigoBarras ?? '');
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _descripcionCtrl = TextEditingController(text: p?.descripcion ?? '');
    _precioCompraCtrl = TextEditingController(text: p != null ? p.precioCompra.toStringAsFixed(2) : '');
    _precioVentaCtrl = TextEditingController(text: p != null ? p.precioVenta.toStringAsFixed(2) : '');
    _tipoVenta = p?.tipoVenta ?? TipoVenta.unidad;
    _stockCtrl = TextEditingController(
      text: p == null
          ? ''
          : p.esPeso
              ? PesoFormatter.kgInputFromGrams(p.stock)
              : '${p.stock}',
    );
    _stockMinimoCtrl = TextEditingController(
      text: p == null
          ? '5'
          : p.esPeso
              ? PesoFormatter.kgInputFromGrams(p.stockMinimo)
              : '${p.stockMinimo}',
    );
    _categoriaSeleccionada = p?.categoria;
    _imagenUrl = p?.imagenUrl;
    _variantes = List.from(p?.variantes ?? const <VarianteProducto>[]);
    _tamanosProducto = List.from(p?.tamanos ?? const <TamanoProducto>[]);
    _conjuntosProducto = List.from(p?.conjuntos ?? const <ConjuntoOpcion>[]);
    _cargarCategorias();
    _cargarTallasColores();
    _cargarTamanosVariantes();
  }

  Future<void> _cargarTamanosVariantes() async {
    final habilitado = await TamanosVariantesConfig.estaHabilitado();
    final tamanos = await TamanosVariantesConfig.obtenerTamanos();
    final conjuntos = await TamanosVariantesConfig.obtenerConjuntos();
    if (mounted) {
      setState(() {
        _tamanosVariantesHabilitado = habilitado;
        _tamanosDisponibles = tamanos;
        _conjuntosDisponibles = conjuntos;
      });
    }
  }

  Future<void> _cargarCategorias() async {
    final cats = await _db.obtenerCategorias();
    if (mounted) setState(() => _categorias = cats);
  }

  Future<void> _cargarTallasColores() async {
    final habilitado = await TallasColoresConfig.estaHabilitado();
    final tallas = await TallasColoresConfig.obtenerTallas();
    final colores = await TallasColoresConfig.obtenerColores();
    if (mounted) {
      setState(() {
        _tallasColoresHabilitado = habilitado;
        _tallasDisponibles = tallas;
        _coloresDisponibles = colores;
      });
    }
  }

  void _actualizarStockDesdeVariantes() {
    if (_variantes.isEmpty) return;
    final total = _variantes.fold<int>(0, (suma, v) => suma + v.stock);
    _stockCtrl.text = '$total';
  }

  void _eliminarVariante(int index) {
    setState(() {
      _variantes.removeAt(index);
      _actualizarStockDesdeVariantes();
    });
  }

  Future<void> _agregarVariante({int? index}) async {
    final existente = index != null ? _variantes[index] : null;
    String? tallaSeleccionada = existente?.talla;
    ColorOpcion? colorSeleccionado = existente == null
        ? null
        : _coloresDisponibles.firstWhere(
            (c) => c.nombre == existente.color,
            orElse: () => ColorOpcion(existente.color, existente.colorHex),
          );
    final stockCtrl = TextEditingController(text: '${existente?.stock ?? 0}');
    final codigoCtrl = TextEditingController(text: existente?.codigoBarras ?? '');

    final agregado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      existente == null ? 'Agregar talla y color' : 'Editar talla y color',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Talla',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tallasDisponibles.map((t) {
                        final seleccionada = tallaSeleccionada == t;
                        return ChoiceChip(
                          label: Text(
                            t,
                            style: TextStyle(
                              color: seleccionada ? Colors.white : AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: seleccionada,
                          onSelected: (_) => setStateModal(() => tallaSeleccionada = t),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Color',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _coloresDisponibles.map((c) {
                        final seleccionado = colorSeleccionado?.nombre == c.nombre;
                        return ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: c.color, radius: 9),
                          label: Text(
                            c.nombre,
                            style: TextStyle(
                              color: seleccionado ? Colors.white : AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: seleccionado,
                          onSelected: (_) => setStateModal(() => colorSeleccionado = c),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stock',
                              prefixIcon: Icon(Icons.numbers),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: codigoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Código (opcional)',
                              prefixIcon: Icon(Icons.qr_code),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (tallaSeleccionada == null || colorSeleccionado == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Selecciona talla y color'),
                                backgroundColor: AppTheme.warning,
                              ),
                            );
                            return;
                          }
                          final yaExiste = _variantes.asMap().entries.any(
                                (e) =>
                                    e.key != index &&
                                    e.value.talla == tallaSeleccionada &&
                                    e.value.color == colorSeleccionado!.nombre,
                              );
                          if (yaExiste) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Esa combinación ya existe'),
                                backgroundColor: AppTheme.warning,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: Text(existente == null ? 'Agregar' : 'Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (agregado == true && tallaSeleccionada != null && colorSeleccionado != null) {
      final nueva = VarianteProducto(
        talla: tallaSeleccionada!,
        color: colorSeleccionado!.nombre,
        colorHex: colorSeleccionado!.hex,
        stock: int.tryParse(stockCtrl.text.trim()) ?? 0,
        codigoBarras: codigoCtrl.text.trim().isEmpty ? null : codigoCtrl.text.trim(),
      );
      setState(() {
        if (index != null) {
          _variantes[index] = nueva;
        } else {
          _variantes.add(nueva);
        }
        _actualizarStockDesdeVariantes();
      });
    }
  }

  // ---------------------------------------------------------------
  // Tamaños y conjuntos (restaurantes)
  // ---------------------------------------------------------------

  void _avisar(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Diálogo "Nuevo tamaño": nombre + precio de ese tamaño en este
  /// producto. Si el nombre no existe aún en la lista global, se
  /// agrega también ahí para poder reutilizarlo en otros productos.
  Future<void> _agregarTamanoProducto({int? index}) async {
    final existente = index != null ? _tamanosProducto[index] : null;
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final precioCtrl = TextEditingController(
      text: existente != null ? existente.precio.toStringAsFixed(2) : '',
    );
    final resultado = await showDialog<TamanoProducto>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Nuevo tamaño' : 'Editar tamaño'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej: Familiar, Mediana',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: precioCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio en este producto'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final nombre = nombreCtrl.text.trim();
              if (nombre.isEmpty) {
                _avisar('Ingresa un nombre para el tamaño', AppTheme.warning);
                return;
              }
              final precio = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              if (precio == null || precio <= 0) {
                _avisar('Ingresa un precio válido', AppTheme.warning);
                return;
              }
              Navigator.pop(ctx, TamanoProducto(nombre: nombre, precio: precio));
            },
            child: Text(existente == null ? 'Agregar' : 'Guardar'),
          ),
        ],
      ),
    );
    if (resultado == null) return;
    final duplicado = _tamanosProducto.asMap().entries.any(
          (e) => e.key != index && e.value.nombre.toLowerCase() == resultado.nombre.toLowerCase(),
        );
    if (duplicado) {
      _avisar('Ese tamaño ya está en este producto', AppTheme.warning);
      return;
    }
    if (!_tamanosDisponibles.any((t) => t.toLowerCase() == resultado.nombre.toLowerCase())) {
      _tamanosDisponibles = List.from(_tamanosDisponibles)..add(resultado.nombre);
      await TamanosVariantesConfig.guardarTamanos(_tamanosDisponibles);
    }
    setState(() {
      if (index != null) {
        _tamanosProducto[index] = resultado;
      } else {
        _tamanosProducto.add(resultado);
      }
    });
  }

  /// Muestra los tamaños ya creados globalmente que aún no están en
  /// este producto, para elegir uno y ponerle precio.
  Future<void> _elegirTamanoExistente() async {
    final disponibles = _tamanosDisponibles
        .where((t) => !_tamanosProducto.any((tp) => tp.nombre.toLowerCase() == t.toLowerCase()))
        .toList();
    if (disponibles.isEmpty) {
      _avisar('Ya agregaste todos los tamaños creados', AppTheme.info);
      return;
    }
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tamaños ya creados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: disponibles
                    .map((t) => ActionChip(label: Text(t), onPressed: () => Navigator.pop(ctx, t)))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (elegido == null || !mounted) return;

    final precioCtrl = TextEditingController();
    final precio = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Precio de "$elegido"'),
        content: TextField(
          controller: precioCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio en este producto'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final valor = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              if (valor == null || valor <= 0) {
                _avisar('Ingresa un precio válido', AppTheme.warning);
                return;
              }
              Navigator.pop(ctx, valor);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (precio == null) return;
    setState(() => _tamanosProducto.add(TamanoProducto(nombre: elegido, precio: precio)));
  }

  void _eliminarTamanoProducto(int index) {
    setState(() => _tamanosProducto.removeAt(index));
  }

  /// Crea un conjunto nuevo (se guarda también en la lista global
  /// para reutilizarlo en otros productos) y lo agrega a este.
  Future<void> _crearConjuntoProducto() async {
    final resultado = await mostrarDialogoConjunto(context);
    if (resultado == null) return;
    if (_conjuntosProducto.any((c) => c.nombre.toLowerCase() == resultado.nombre.toLowerCase())) {
      _avisar('Ese conjunto ya está en este producto', AppTheme.warning);
      return;
    }
    if (!_conjuntosDisponibles.any((c) => c.nombre.toLowerCase() == resultado.nombre.toLowerCase())) {
      _conjuntosDisponibles = List.from(_conjuntosDisponibles)..add(resultado);
      await TamanosVariantesConfig.guardarConjuntos(_conjuntosDisponibles);
    }
    setState(() => _conjuntosProducto.add(resultado));
  }

  /// Muestra los conjuntos ya creados globalmente que aún no están
  /// en este producto, para agregar una copia directamente.
  Future<void> _elegirConjuntoExistente() async {
    final disponibles = _conjuntosDisponibles
        .where((c) => !_conjuntosProducto.any((cp) => cp.nombre.toLowerCase() == c.nombre.toLowerCase()))
        .toList();
    if (disponibles.isEmpty) {
      _avisar('Ya agregaste todos los conjuntos creados', AppTheme.info);
      return;
    }
    final elegido = await showModalBottomSheet<ConjuntoOpcion>(
      context: context,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Conjuntos ya creados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final c in disponibles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${c.opciones.length} opciones', style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (elegido == null) return;
    setState(() => _conjuntosProducto.add(elegido));
  }

  Future<void> _editarConjuntoProducto(int index) async {
    final resultado = await mostrarDialogoConjunto(context, existente: _conjuntosProducto[index]);
    if (resultado == null) return;
    setState(() => _conjuntosProducto[index] = resultado);
  }

  void _eliminarConjuntoProducto(int index) {
    setState(() => _conjuntosProducto.removeAt(index));
  }

  Future<void> _generarCodigo() async {
    if (_codigoCtrl.text.trim().isNotEmpty) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Generar nuevo código'),
          content: const Text(
            'Ya tienes un código ingresado. ¿Quieres reemplazarlo por uno generado automáticamente?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reemplazar')),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    setState(() {
      _codigoCtrl.text = BarcodeGenerator.generarEAN13();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Código generado. Puedes descargar su imagen para imprimirlo.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  bool _descargando = false;

  Future<void> _descargarCodigoBarras() async {
    final primerCodigo = _codigoCtrl.text.split(',').first.trim();
    if (primerCodigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero genera o ingresa un código de barras'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    setState(() => _descargando = true);
    try {
      final path = await BarcodeImageExporter.generarPng(
        codigo: primerCodigo,
        nombreProducto: _nombreCtrl.text.trim(),
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Código de barras — ${_nombreCtrl.text.trim()}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar la imagen: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
    if (mounted) setState(() => _descargando = false);
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen(titulo: 'Escanear Código')),
    );
    if (codigo != null) {
      if (_codigoCtrl.text.trim().isEmpty) {
        _codigoCtrl.text = codigo;
      } else {
        if (!_codigoCtrl.text.contains(codigo)) {
          _codigoCtrl.text = '${_codigoCtrl.text.trim()}, $codigo';
        }
      }
    }
  }

  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _imagenUrl = image.path);
    }
  }

  void _cambiarTipo(String tipo) {
    if (tipo == _tipoVenta) return;
    setState(() {
      _tipoVenta = tipo;
      if (!_isEditing) {
        _stockCtrl.clear();
        _stockMinimoCtrl.text = tipo == TipoVenta.peso ? '1' : '5';
      }
    });
  }

  int _parseStock(String text) {
    if (_tipoVenta == TipoVenta.peso) {
      return PesoFormatter.parseToGrams(text, enKg: true);
    }
    return int.tryParse(text.trim()) ?? 0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final codigosIngresados = _codigoCtrl.text
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();

      final codigosVariantes = _variantes
          .map((v) => v.codigoBarras)
          .whereType<String>()
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();

      final codigosParaValidar = [...codigosIngresados, ...codigosVariantes];

      if (codigosParaValidar.isNotEmpty) {
        final duplicado = await _db.buscarProductoConCodigoDuplicado(
          codigosParaValidar,
          excluirId: widget.producto?.id,
        );
        if (duplicado != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'Ese código de barras ya lo usa "${duplicado.nombre}". Usa uno diferente.',
              ),
              backgroundColor: AppTheme.error,
            ));
          }
          if (mounted) setState(() => _saving = false);
          return;
        }
      }

      final producto = Producto(
        id: widget.producto?.id ?? const Uuid().v4(),
        codigoBarras: _codigoCtrl.text.trim(),
        nombre: _nombreCtrl.text.trim(),
        descripcion: _descripcionCtrl.text.trim().isEmpty ? null : _descripcionCtrl.text.trim(),
        categoria: _categoriaSeleccionada,
        precioCompra: double.tryParse(_precioCompraCtrl.text) ?? 0,
        precioVenta: double.parse(_precioVentaCtrl.text),
        stock: _parseStock(_stockCtrl.text),
        stockMinimo: _tipoVenta == TipoVenta.peso
            ? PesoFormatter.parseToGrams(
                _stockMinimoCtrl.text.isEmpty ? '0' : _stockMinimoCtrl.text,
                enKg: true,
              )
            : int.tryParse(_stockMinimoCtrl.text) ?? 5,
        tipoVenta: _tipoVenta,
        imagenUrl: _imagenUrl,
        fechaCreacion: widget.producto?.fechaCreacion,
        variantes: _variantes,
        tamanos: _tamanosProducto,
        conjuntos: _conjuntosProducto,
      );
      if (_isEditing) {
        await _db.actualizarProducto(producto);
      } else {
        await _db.insertarProducto(producto);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? '✓ Producto actualizado' : '✓ Producto guardado'),
          backgroundColor: AppTheme.success,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _eliminar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Eliminar "${widget.producto!.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.eliminarProducto(widget.producto!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado'), backgroundColor: AppTheme.error),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _asociarAProductoExistente() async {
    final productos = await _db.obtenerProductos();
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateModal) {
            final filtrados = productos.where((p) => 
              p.nombre.toLowerCase().contains(searchQuery.toLowerCase()) || 
              p.codigoBarras.contains(searchQuery)
            ).toList();
            
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                  ),
                  const Text('Vincular a producto existente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Busca y selecciona el producto al que quieres añadir este nuevo código.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setStateModal(() => searchQuery = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar producto...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(child: Text('No hay productos que coincidan.'))
                        : ListView.builder(
                            itemCount: filtrados.length,
                            itemBuilder: (_, i) {
                              final p = filtrados[i];
                          return ListTile(
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 20),
                            ),
                            title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${p.formatoStock} | Cód: ${p.codigoBarras.split(',').first}..',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.link, color: AppTheme.primary),
                            onTap: () async {
                              Navigator.pop(ctx);
                              if (!p.codigoBarras.contains(widget.codigoBarras!)) {
                                final pActualizado = p.copyWith(
                                  codigoBarras: '${p.codigoBarras}, ${widget.codigoBarras!}',
                                );
                                await _db.actualizarProducto(pActualizado);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Código vinculado a ${p.nombre}'), backgroundColor: AppTheme.success),
                                  );
                                  Navigator.pop(context); // Cierra el formulario de "Nuevo producto"
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Este código ya estaba vinculado a este producto.')),
                                  );
                                  Navigator.pop(context);
                                }
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto'),
        actions: [
          if (_isEditing)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.error), onPressed: _eliminar),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: listBottomPadding(context, bottomExtra: 20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _seleccionarImagen,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.bgGrey,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                    image: _imagenUrl != null
                        ? DecorationImage(image: FileImage(File(_imagenUrl!)), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _imagenUrl == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: AppTheme.textSecondary, size: 32),
                            SizedBox(height: 8),
                            Text('Añadir foto', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          ],
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            _buildLabel('Código de Barras'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _codigoCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: _tipoVenta == TipoVenta.peso
                          ? 'Opcional (no se vende con escáner)'
                          : 'Ej: 7750... o varios separados por coma',
                      prefixIcon: const Icon(Icons.qr_code),
                    ),
                    validator: (v) {
                      if (_tipoVenta == TipoVenta.peso) return null;
                      return v == null || v.isEmpty ? 'Ingresa el código' : null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                    tooltip: 'Escanear código',
                    onPressed: _escanear,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _generarCodigo,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text('Generar código de barras'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _descargando ? null : _descargarCodigoBarras,
                icon: _descargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_descargando ? 'Generando...' : 'Descargar código de barras'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 16),

            _buildLabel('Nombre del Producto'),
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Inca Kola 500ml', prefixIcon: Icon(Icons.inventory_2_outlined)),
              validator: (v) => v == null || v.isEmpty ? 'Ingresa el nombre' : null,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            _buildLabel('Descripción (opcional)'),
            TextFormField(
              controller: _descripcionCtrl,
              decoration: const InputDecoration(hintText: 'Descripción breve...'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            _buildLabel('Categoría'),
            DropdownButtonFormField<String>(
              initialValue: _categoriaSeleccionada,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
              hint: const Text('Seleccionar categoría'),
              items: _categorias.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _categoriaSeleccionada = v),
            ),
            const SizedBox(height: 20),

            _buildLabel('Se vende por'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: TipoVenta.unidad,
                  label: Text('Unidad'),
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                ),
                ButtonSegment(
                  value: TipoVenta.peso,
                  label: Text('Kilos'),
                  icon: Icon(Icons.scale_outlined, size: 18),
                ),
              ],
              selected: {_tipoVenta},
              onSelectionChanged: (s) => _cambiarTipo(s.first),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(_tipoVenta == TipoVenta.peso
                          ? 'Precio Compra (S/ por kg)'
                          : 'Precio Compra (S/)'),
                      TextFormField(
                        controller: _precioCompraCtrl,
                        style: _valorStyle,
                        decoration: const InputDecoration(hintText: '0.00', prefixIcon: Icon(Icons.money_off_outlined)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(_tipoVenta == TipoVenta.peso
                          ? 'Precio Venta (S/ por kg)'
                          : 'Precio Venta (S/)'),
                      TextFormField(
                        controller: _precioVentaCtrl,
                        style: _valorStyle,
                        decoration: const InputDecoration(hintText: '0.00', prefixIcon: Icon(Icons.attach_money)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => v == null || v.isEmpty || (double.tryParse(v) ?? 0) <= 0 ? 'Precio inválido' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(_tipoVenta == TipoVenta.peso
                          ? 'Stock Actual (kg)'
                          : 'Stock Actual'),
                      TextFormField(
                        controller: _stockCtrl,
                        readOnly: _variantes.isNotEmpty,
                        style: _valorStyle,
                        decoration: InputDecoration(
                          hintText: _tipoVenta == TipoVenta.peso ? '0.000' : '0',
                          prefixIcon: const Icon(Icons.numbers),
                          helperText: _variantes.isNotEmpty
                              ? 'Se calcula sumando las combinaciones'
                              : null,
                          helperMaxLines: 2,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          if (_tipoVenta == TipoVenta.peso) {
                            final n = double.tryParse(v.replaceAll(',', '.'));
                            if (n == null || n < 0) return 'Kg inválido';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(_tipoVenta == TipoVenta.peso
                          ? 'Stock Mínimo (kg)'
                          : 'Stock Mínimo'),
                      TextFormField(
                        controller: _stockMinimoCtrl,
                        style: _valorStyle,
                        decoration: InputDecoration(
                          hintText: _tipoVenta == TipoVenta.peso ? '1' : '5',
                          prefixIcon: const Icon(Icons.warning_amber),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_tallasColoresHabilitado && _tipoVenta == TipoVenta.unidad) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildLabel('Tallas y colores'),
                  const Spacer(),
                  if (_variantes.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_variantes.fold<int>(0, (s, v) => s + v.stock)} und',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                ],
              ),
              const Text(
                'Cada fila es una talla y color con su stock y código.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              if (_variantes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: AppTheme.bgGrey,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.checkroom_outlined, color: AppTheme.textMuted, size: 32),
                      SizedBox(height: 8),
                      Text('Sin combinaciones', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text(
                        'Agrega las tallas y colores que vendes',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _variantes.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.bgGrey,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            'Talla ${_variantes[i].talla}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryDark,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.bgGrey,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 12,
                                                height: 12,
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: _variantes[i].colorObj,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: AppTheme.border),
                                                ),
                                              ),
                                              Text(
                                                'Color: ${_variantes[i].color}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.inventory_2_outlined, size: 15, color: AppTheme.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_variantes[i].stock} und',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if ((_variantes[i].codigoBarras ?? '').isNotEmpty) ...[
                                          const SizedBox(width: 12),
                                          const Icon(Icons.qr_code, size: 15, color: AppTheme.textSecondary),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              _variantes[i].codigoBarras!,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                                onPressed: () => _agregarVariante(index: i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                                onPressed: () => _eliminarVariante(i),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_tallasDisponibles.isEmpty || _coloresDisponibles.isEmpty)
                      ? null
                      : () => _agregarVariante(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar talla y color'),
                ),
              ),
              if (_tallasDisponibles.isEmpty || _coloresDisponibles.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Configura tus tallas y colores en Ajustes → Configuración avanzada.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
            ],
            if (_tamanosVariantesHabilitado && _tipoVenta == TipoVenta.unidad) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildLabel('Tamaños y conjuntos'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.bgGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Restaurante',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Tamaños
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
                    const Text('Tamaños', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    if (_tamanosProducto.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Sin tamaños en este producto',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      )
                    else
                      for (var i = 0; i < _tamanosProducto.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(_tamanosProducto[i].nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('S/ ${_tamanosProducto[i].precio.toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                                onPressed: () => _agregarTamanoProducto(index: i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.error),
                                onPressed: () => _eliminarTamanoProducto(i),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _agregarTamanoProducto,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Añadir tamaño'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _elegirTamanoExistente,
                          child: const Text('Ya creados'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Conjuntos
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
                    const Text('Conjuntos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    if (_conjuntosProducto.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Sin conjuntos en este producto',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      )
                    else
                      for (var i = 0; i < _conjuntosProducto.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(_conjuntosProducto[i].nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${_conjuntosProducto[i].opciones.length} opciones · '
                            '${_conjuntosProducto[i].seleccionMultiple ? "Varias" : "Una"}'
                            '${_conjuntosProducto[i].obligatorio ? " · Obligatorio" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                                onPressed: () => _editarConjuntoProducto(i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.error),
                                onPressed: () => _eliminarConjuntoProducto(i),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _crearConjuntoProducto,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Añadir conjunto'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _elegirConjuntoExistente,
                          child: const Text('Ya creados'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _guardar,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Guardando...' : (_isEditing ? 'Actualizar Producto' : 'Guardar Producto')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
    );
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _precioCompraCtrl.dispose();
    _precioVentaCtrl.dispose();
    _stockCtrl.dispose();
    _stockMinimoCtrl.dispose();
    super.dispose();
  }
}
