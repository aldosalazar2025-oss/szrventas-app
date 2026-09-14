import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/safe_area_padding.dart';
import '../utils/tamanos_variantes_config.dart';
import '../models/conjunto_opcion.dart';
import '../widgets/conjunto_dialogs.dart';

/// Pantalla "Tamaños y variantes": permite activar/desactivar la
/// función (pensada para restaurantes) y administrar los tamaños
/// (ej. Personal, Mediana, Familiar) y conjuntos (ej. Cremas, Extras)
/// disponibles para usar en el formulario de productos.
class TamanosVariantesScreen extends StatefulWidget {
  const TamanosVariantesScreen({super.key});

  @override
  State<TamanosVariantesScreen> createState() =>
      _TamanosVariantesScreenState();
}

class _TamanosVariantesScreenState extends State<TamanosVariantesScreen> {
  bool _loading = true;
  bool _habilitado = false;
  List<String> _tamanos = [];
  List<ConjuntoOpcion> _conjuntos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final habilitado = await TamanosVariantesConfig.estaHabilitado();
    final tamanos = await TamanosVariantesConfig.obtenerTamanos();
    final conjuntos = await TamanosVariantesConfig.obtenerConjuntos();
    if (mounted) {
      setState(() {
        _habilitado = habilitado;
        _tamanos = tamanos;
        _conjuntos = conjuntos;
        _loading = false;
      });
    }
  }

  Future<void> _cambiarHabilitado(bool valor) async {
    setState(() => _habilitado = valor);
    await TamanosVariantesConfig.guardarHabilitado(valor);
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

  // ---------------------------------------------------------------
  // Tamaños
  // ---------------------------------------------------------------

  Future<void> _agregarTamano() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo tamaño'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej: Familiar, Mediana'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    final valor = nombre.trim();
    if (_tamanos.any((t) => t.toLowerCase() == valor.toLowerCase())) {
      _mostrarAviso('Ese tamaño ya existe', AppTheme.warning);
      return;
    }
    setState(() => _tamanos.add(valor));
    await TamanosVariantesConfig.guardarTamanos(_tamanos);
  }

  Future<void> _eliminarTamano(String tamano) async {
    setState(() => _tamanos.remove(tamano));
    await TamanosVariantesConfig.guardarTamanos(_tamanos);
  }

  // ---------------------------------------------------------------
  // Conjuntos
  // ---------------------------------------------------------------

  Future<void> _agregarOEditarConjunto({ConjuntoOpcion? existente}) async {
    final resultado = await mostrarDialogoConjunto(context, existente: existente);
    if (resultado == null) return;
    if (existente == null &&
        _conjuntos.any((c) => c.nombre.toLowerCase() == resultado.nombre.toLowerCase())) {
      _mostrarAviso('Ya existe un conjunto con ese nombre', AppTheme.warning);
      return;
    }
    setState(() {
      if (existente != null) {
        final idx = _conjuntos.indexOf(existente);
        if (idx != -1) _conjuntos[idx] = resultado;
      } else {
        _conjuntos.add(resultado);
      }
    });
    await TamanosVariantesConfig.guardarConjuntos(_conjuntos);
  }

  Future<void> _eliminarConjunto(ConjuntoOpcion conjunto) async {
    setState(() => _conjuntos.remove(conjunto));
    await TamanosVariantesConfig.guardarConjuntos(_conjuntos);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tamaños y variantes')),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.restaurant_rounded, color: AppTheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Usar tamaños y variantes',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Para restaurantes. Al activarlo, en cada producto '
                        'podrás poner tamaños con precio y conjuntos '
                        '(cremas, extras).',
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
                const Text('Tamaños', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'El precio de cada tamaño se pone en el producto '
                  '(ej. pizza Familiar).',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tamano in _tamanos)
                      Chip(
                        label: Text(
                          tamano,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.error),
                        onDeleted: () => _eliminarTamano(tamano),
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
                      onPressed: _agregarTamano,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

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
                const Text('Conjuntos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Cremas, extras u otras opciones. Una o varias, opcional '
                  'u obligatorio, con máximo.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                if (_conjuntos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Aún no hay conjuntos.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  )
                else
                  for (final conjunto in _conjuntos)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(conjunto.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${conjunto.opciones.length} opciones · '
                        '${conjunto.seleccionMultiple ? "Varias" : "Una"}'
                        '${conjunto.obligatorio ? " · Obligatorio" : ""}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                            onPressed: () => _agregarOEditarConjunto(existente: conjunto),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.error),
                            onPressed: () => _eliminarConjunto(conjunto),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _agregarOEditarConjunto(),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir conjunto'),
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
