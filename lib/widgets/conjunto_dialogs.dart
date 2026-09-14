import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/conjunto_opcion.dart';

void _mostrarAviso(BuildContext context, String mensaje, Color color) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Diálogo "Nueva opción": nombre + precio extra de una opción dentro
/// de un conjunto (ej. "Queso extra", "Mayonesa").
Future<OpcionExtra?> mostrarDialogoOpcion(BuildContext context) {
  final nombreCtrl = TextEditingController();
  final precioCtrl = TextEditingController(text: '0');
  return showDialog<OpcionExtra>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nueva opción'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombreCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: precioCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio extra'),
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
              _mostrarAviso(ctx, 'Ingresa un nombre para la opción', AppTheme.warning);
              return;
            }
            final precio = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
            Navigator.pop(ctx, OpcionExtra(nombre: nombre, precioExtra: precio));
          },
          child: const Text('Agregar'),
        ),
      ],
    ),
  );
}

/// Diálogo "Nuevo conjunto" / "Editar conjunto": nombre, tipo de
/// selección (una/varias), si es obligatorio, máximo de opciones, y
/// la lista de opciones (cada una con su propio precio extra).
Future<ConjuntoOpcion?> mostrarDialogoConjunto(
  BuildContext context, {
  ConjuntoOpcion? existente,
}) {
  final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
  final maximoCtrl = TextEditingController(
    text: existente?.maximo != null ? existente!.maximo.toString() : '',
  );
  bool seleccionMultiple = existente?.seleccionMultiple ?? true;
  bool obligatorio = existente?.obligatorio ?? false;
  List<OpcionExtra> opciones = List.from(existente?.opciones ?? []);

  return showDialog<ConjuntoOpcion>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(existente == null ? 'Nuevo conjunto' : 'Editar conjunto'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      hintText: 'Ej: Cremas, Extras',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Selección', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Una'),
                          selected: !seleccionMultiple,
                          onSelected: (_) => setStateDialog(() => seleccionMultiple = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Varias'),
                          selected: seleccionMultiple,
                          onSelected: (_) => setStateDialog(() => seleccionMultiple = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Obligatorio', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              'Si está apagado, el cliente puede no elegir nada',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: obligatorio,
                        onChanged: (v) => setStateDialog(() => obligatorio = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (seleccionMultiple)
                    TextField(
                      controller: maximoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Máximo (opcional)',
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text('Opciones', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'Agrega cremas, extras u otras opciones.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  for (final op in opciones)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(op.nombre),
                      subtitle: op.precioExtra > 0
                          ? Text('+ S/ ${op.precioExtra.toStringAsFixed(2)}')
                          : const Text('Sin costo extra'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.error),
                        onPressed: () => setStateDialog(() => opciones.remove(op)),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final nueva = await mostrarDialogoOpcion(context);
                        if (nueva != null) {
                          setStateDialog(() => opciones.add(nueva));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir opción'),
                    ),
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
                  if (nombre.isEmpty) {
                    _mostrarAviso(ctx, 'Ingresa un nombre para el conjunto', AppTheme.warning);
                    return;
                  }
                  if (opciones.isEmpty) {
                    _mostrarAviso(ctx, 'Agrega al menos una opción', AppTheme.warning);
                    return;
                  }
                  final maximo = seleccionMultiple
                      ? int.tryParse(maximoCtrl.text.trim())
                      : null;
                  Navigator.pop(
                    ctx,
                    ConjuntoOpcion(
                      nombre: nombre,
                      seleccionMultiple: seleccionMultiple,
                      obligatorio: obligatorio,
                      maximo: maximo,
                      opciones: opciones,
                    ),
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );
}
