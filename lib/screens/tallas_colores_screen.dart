import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../theme/app_theme.dart';
import '../utils/safe_area_padding.dart';
import '../utils/color_hex.dart';
import '../utils/tallas_colores_config.dart';

/// Pantalla "Tallas y colores": permite activar/desactivar la función
/// y administrar (añadir/eliminar) las tallas y colores disponibles
/// para armar combinaciones en el formulario de productos.
class TallasColoresScreen extends StatefulWidget {
  const TallasColoresScreen({super.key});

  @override
  State<TallasColoresScreen> createState() => _TallasColoresScreenState();
}

class _TallasColoresScreenState extends State<TallasColoresScreen> {
  bool _loading = true;
  bool _habilitado = false;
  List<String> _tallas = [];
  List<ColorOpcion> _colores = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final habilitado = await TallasColoresConfig.estaHabilitado();
    final tallas = await TallasColoresConfig.obtenerTallas();
    final colores = await TallasColoresConfig.obtenerColores();
    if (mounted) {
      setState(() {
        _habilitado = habilitado;
        _tallas = tallas;
        _colores = colores;
        _loading = false;
      });
    }
  }

  Future<void> _cambiarHabilitado(bool valor) async {
    setState(() => _habilitado = valor);
    await TallasColoresConfig.guardarHabilitado(valor);
  }

  Future<void> _agregarTalla() async {
    final ctrl = TextEditingController();
    final talla = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir talla'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Ej: XS, M, 32, Único...'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (talla == null || talla.trim().isEmpty) return;
    final valor = talla.trim();
    if (_tallas.any((t) => t.toLowerCase() == valor.toLowerCase())) {
      _mostrarAviso('Esa talla ya existe', AppTheme.warning);
      return;
    }
    setState(() => _tallas.add(valor));
    await TallasColoresConfig.guardarTallas(_tallas);
  }

  Future<void> _eliminarTalla(String talla) async {
    setState(() => _tallas.remove(talla));
    await TallasColoresConfig.guardarTallas(_tallas);
  }

  /// Abre una rueda de color completa (no solo los tonos predeterminados)
  /// para que el usuario pueda elegir cualquier color, y deja el resultado
  /// en [hexCtrl] actualizando el diálogo que lo llamó.
  Future<void> _elegirColorPersonalizado(
    BuildContext context,
    TextEditingController hexCtrl,
    void Function(void Function()) setStateDialog,
  ) async {
    final actual = normalizarHex(hexCtrl.text);
    var colorTemporal = actual != null ? colorDesdeHex(actual) : AppTheme.primary;

    final elegido = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elige un color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: colorTemporal,
            onColorChanged: (c) => colorTemporal = c,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsvWithHue,
            pickerAreaHeightPercent: 0.7,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, colorTemporal),
            child: const Text('Elegir'),
          ),
        ],
      ),
    );

    if (elegido != null) {
      setStateDialog(() => hexCtrl.text = hexDesdeColor(elegido));
    }
  }

  Future<void> _agregarOEditarColor({ColorOpcion? existente}) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final hexCtrl = TextEditingController(text: existente?.hex ?? '#000000');

    const presets = [
      '#212121', '#FFFFFF', '#E53935', '#1E88E5', '#43A047', '#D7C4A3',
      '#FDD835', '#8E24AA', '#FB8C00', '#546E7A', '#00897B', '#6D4C41',
    ];

    final resultado = await showDialog<ColorOpcion>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final previa = normalizarHex(hexCtrl.text);
            return AlertDialog(
              title: Text(existente == null ? 'Añadir color' : 'Editar color'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre del color'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hexCtrl,
                      decoration: InputDecoration(
                        labelText: 'Tono (hex)',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: previa != null ? colorDesdeHex(previa) : AppTheme.bgGrey,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.border),
                            ),
                          ),
                        ),
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...presets.map((hex) {
                          return GestureDetector(
                            onTap: () => setStateDialog(() => hexCtrl.text = hex),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: colorDesdeHex(hex),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.border, width: 1.5),
                              ),
                            ),
                          );
                        }),
                        GestureDetector(
                          onTap: () => _elegirColorPersonalizado(context, hexCtrl, setStateDialog),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.border, width: 1.5),
                              gradient: const SweepGradient(
                                colors: [
                                  Colors.red,
                                  Colors.yellow,
                                  Colors.green,
                                  Colors.cyan,
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.red,
                                ],
                              ),
                            ),
                            child: const Icon(Icons.add, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final nombre = nombreCtrl.text.trim();
                    final hexNormalizado = normalizarHex(hexCtrl.text);
                    if (nombre.isEmpty) {
                      _mostrarAviso('Ingresa un nombre para el color', AppTheme.warning);
                      return;
                    }
                    if (hexNormalizado == null) {
                      _mostrarAviso('El tono no es un hex válido (ej. #E53935)', AppTheme.warning);
                      return;
                    }
                    Navigator.pop(ctx, ColorOpcion(nombre, hexNormalizado));
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado == null) return;
    if (existente == null &&
        _colores.any((c) => c.nombre.toLowerCase() == resultado.nombre.toLowerCase())) {
      _mostrarAviso('Ya existe un color con ese nombre', AppTheme.warning);
      return;
    }
    setState(() {
      if (existente != null) {
        final idx = _colores.indexOf(existente);
        if (idx != -1) _colores[idx] = resultado;
      } else {
        _colores.add(resultado);
      }
    });
    await TallasColoresConfig.guardarColores(_colores);
  }

  Future<void> _eliminarColor(ColorOpcion color) async {
    setState(() => _colores.remove(color));
    await TallasColoresConfig.guardarColores(_colores);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tallas y colores')),
      body: ListView(
        padding: listBottomPadding(context, bottomExtra: 24),
        children: [
          const SizedBox(height: 8),

          // Activar / desactivar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.checkroom_rounded, color: AppTheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Usar tallas y colores',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Al activarlo, en cada producto podrás agregar '
                        'combinaciones con su propio stock.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(value: _habilitado, onChanged: _cambiarHabilitado),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tallas
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
                const Text('Tallas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final talla in _tallas)
                      Chip(
                        label: Text(
                          talla,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.error),
                        onDeleted: () => _eliminarTalla(talla),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16, color: AppTheme.primary),
                      label: const Text(
                        'Añadir',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _agregarTalla,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Colores
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
                const Text('Colores', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Cada color tiene su tono. Toca el lápiz para cambiarlo.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                for (final color in _colores)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.border),
                      ),
                    ),
                    title: Text(color.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(color.hex, style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                          onPressed: () => _agregarOEditarColor(existente: color),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.error),
                          onPressed: () => _eliminarColor(color),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _agregarOEditarColor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir color'),
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
