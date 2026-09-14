import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/printer_service.dart';
import '../models/venta.dart';
import '../utils/safe_area_padding.dart';
import '../utils/currency_formatter.dart';
import '../utils/sound_player.dart';
import '../utils/whatsapp_share.dart';
import '../utils/widget_image_capture.dart';
import '../widgets/variante_chips.dart';
import '../widgets/detalle_chips.dart';
import '../widgets/ticket_receipt_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});
  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _db = DatabaseService.instance;
  final _df = DateFormat('dd/MM/yyyy HH:mm', 'es');
  List<Venta> _ventas = [];
  bool _loading = true;
  String _filtro = 'hoy';
  String _monedaSimbolo = 'S/';
  DateTime _referencia = DateTime.now();
  DateTimeRange? _rangoPersonalizado;

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
    _cargar();
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

  Future<void> _cargar() async {
    setState(() => _loading = true);
    DateTime? desde;
    DateTime? hasta;

    if (_rangoPersonalizado != null) {
      final inicio = _rangoPersonalizado!.start;
      final fin = _rangoPersonalizado!.end;
      desde = DateTime(inicio.year, inicio.month, inicio.day);
      hasta = DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);
    } else {
      switch (_filtro) {
        case 'hoy':
          desde = DateTime(_referencia.year, _referencia.month, _referencia.day);
          hasta = desde
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          break;
        case 'semana':
          final inicioSemana =
              _referencia.subtract(Duration(days: _referencia.weekday - 1));
          desde = DateTime(
              inicioSemana.year, inicioSemana.month, inicioSemana.day);
          hasta = desde
              .add(const Duration(days: 7))
              .subtract(const Duration(milliseconds: 1));
          break;
        case 'mes':
          desde = DateTime(_referencia.year, _referencia.month, 1);
          hasta = DateTime(_referencia.year, _referencia.month + 1, 1)
              .subtract(const Duration(milliseconds: 1));
          break;
        default:
          desde = null;
          hasta = null;
      }
    }

    final ventas = await _db.obtenerVentas(desde: desde, hasta: hasta);
    if (mounted)
      setState(() {
        _ventas = ventas;
        _loading = false;
      });
  }

  bool get _puedeNavegar => _rangoPersonalizado != null || _filtro != 'todo';

  void _desplazarPeriodo(int direccion) {
    setState(() {
      if (_rangoPersonalizado != null) {
        final dias = _rangoPersonalizado!.end
                .difference(_rangoPersonalizado!.start)
                .inDays +
            1;
        final desplazamiento = Duration(days: dias * direccion);
        _rangoPersonalizado = DateTimeRange(
          start: _rangoPersonalizado!.start.add(desplazamiento),
          end: _rangoPersonalizado!.end.add(desplazamiento),
        );
      } else {
        switch (_filtro) {
          case 'hoy':
            _referencia = _referencia.add(Duration(days: direccion));
            break;
          case 'semana':
            _referencia = _referencia.add(Duration(days: 7 * direccion));
            break;
          case 'mes':
            _referencia = DateTime(
              _referencia.year,
              _referencia.month + direccion,
              _referencia.day,
            );
            break;
        }
      }
    });
    _cargar();
  }

  String _etiquetaPeriodo() {
    if (_rangoPersonalizado != null) {
      final ini = _rangoPersonalizado!.start;
      final fin = _rangoPersonalizado!.end;
      final mismoDia =
          ini.year == fin.year && ini.month == fin.month && ini.day == fin.day;
      final corto = DateFormat('d MMM', 'es');
      if (mismoDia) return corto.format(ini);
      final mismoAnio = ini.year == fin.year;
      final conAnio = DateFormat('d MMM yyyy', 'es');
      return mismoAnio
          ? '${corto.format(ini)} - ${corto.format(fin)}'
          : '${conAnio.format(ini)} - ${conAnio.format(fin)}';
    }

    final hoy = DateTime.now();
    switch (_filtro) {
      case 'hoy':
        final esHoy = _referencia.year == hoy.year &&
            _referencia.month == hoy.month &&
            _referencia.day == hoy.day;
        if (esHoy) return 'Hoy';
        final ayer = hoy.subtract(const Duration(days: 1));
        final esAyer = _referencia.year == ayer.year &&
            _referencia.month == ayer.month &&
            _referencia.day == ayer.day;
        if (esAyer) return 'Ayer';
        return DateFormat('d MMM yyyy', 'es').format(_referencia);
      case 'semana':
        final inicioSemana =
            _referencia.subtract(Duration(days: _referencia.weekday - 1));
        final finSemana = inicioSemana.add(const Duration(days: 6));
        return '${DateFormat('d MMM', 'es').format(inicioSemana)} - ${DateFormat('d MMM', 'es').format(finSemana)}';
      case 'mes':
        final texto = DateFormat('MMMM yyyy', 'es').format(_referencia);
        return texto[0].toUpperCase() + texto.substring(1);
      default:
        return 'Todas las ventas';
    }
  }

  Future<void> _elegirRango() async {
    final base = _rangoPersonalizado ??
        DateTimeRange(start: _referencia, end: _referencia);
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(ahora.year + 1, 12, 31),
      initialDateRange: base,
      helpText: 'Elige día o rango',
      saveText: 'Guardar',
      cancelText: 'Cancelar',
      confirmText: 'Guardar',
    );
    if (rango != null) {
      setState(() {
        _rangoPersonalizado = rango;
      });
      _cargar();
    }
  }

  double get _totalVentas => _ventas.fold(0.0, (s, v) => s + v.total);
  double get _totalGanancia => _ventas.fold(0.0, (s, v) => s + v.gananciaTotal);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Ventas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.error),
            onPressed: _eliminarTodasLasVentas,
            tooltip: 'Eliminar todas',
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppTheme.primary),
            onPressed: _exportarExcel,
            tooltip: 'Exportar a Excel',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                _buildFiltro('Día', 'hoy'),
                const SizedBox(width: 8),
                _buildFiltro('Semana', 'semana'),
                const SizedBox(width: 8),
                _buildFiltro('Mes', 'mes'),
                const SizedBox(width: 8),
                _buildFiltro('Todo', 'todo'),
              ],
            ),
          ),
          // Navegador de fecha / rango
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bgWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: _puedeNavegar
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                    onPressed:
                        _puedeNavegar ? () => _desplazarPeriodo(-1) : null,
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _elegirRango,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _etiquetaPeriodo(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Toca para elegir día o rango',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: _puedeNavegar
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                    onPressed:
                        _puedeNavegar ? () => _desplazarPeriodo(1) : null,
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: AppTheme.border,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.calendar_month_rounded,
                      color: AppTheme.primary,
                    ),
                    tooltip: 'Elegir día o rango',
                    onPressed: _elegirRango,
                  ),
                ],
              ),
            ),
          ),
          // Resumen
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${_ventas.length}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Ventas',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatMoney(_totalVentas),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Ingresos',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatMoney(_totalGanancia),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Ganancia',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Lista
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _ventas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: AppTheme.textHint,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sin ventas en este período',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: listBottomPadding(context),
                    itemCount: _ventas.length,
                    itemBuilder: (_, i) => _buildVentaCard(_ventas[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltro(String label, String value) {
    final sel = _filtro == value && _rangoPersonalizado == null;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filtro = value;
            _rangoPersonalizado = null;
            _referencia = DateTime.now();
          });
          _cargar();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppTheme.primary : AppTheme.bgWhite,
            borderRadius: BorderRadius.circular(10),
            border: sel ? null : Border.all(color: AppTheme.border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: sel ? Colors.white : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _eliminarTodasLasVentas() async {
    if (_ventas.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Historial'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar TODAS las ventas registradas? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _db.eliminarTodasLasVentas();
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Historial eliminado correctamente'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _eliminarVentaUnica(Venta v) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Venta'),
        content: Text(
          '¿Eliminar la venta #${v.id.substring(0, 8).toUpperCase()}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _db.eliminarVenta(v.id);
      if (mounted) {
        Navigator.pop(context); // Close the bottom sheet
        _cargar(); // Reload list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta eliminada'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _exportarExcel() async {
    if (_ventas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay ventas para exportar'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generando archivo Excel...')));

    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Historial de Ventas'];
      excel.setDefaultSheet('Historial de Ventas');

      // Títulos de columnas
      const encabezadosVentas = [
        'ID Venta',
        'Fecha',
        'Hora',
        'Método Pago',
        'Artículos Totales',
        'Subtotal',
        'Descuento',
        'Total',
        'Ganancia Neta',
        'Detalle Productos',
      ];
      sheetObject.appendRow([
        TextCellValue('ID Venta'),
        TextCellValue('Fecha'),
        TextCellValue('Hora'),
        TextCellValue('Método Pago'),
        TextCellValue('Artículos Totales'),
        TextCellValue('Subtotal'),
        TextCellValue('Descuento'),
        TextCellValue('Total ($_monedaSimbolo)'),
        TextCellValue('Ganancia Neta'),
        TextCellValue('Detalle Productos'),
      ]);
      final estiloEncabezadoVentas = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#12A100'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      for (var c = 0; c < encabezadosVentas.length; c++) {
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle =
            estiloEncabezadoVentas;
        sheetObject.setColumnWidth(c, encabezadosVentas[c].length < 14 ? 16 : 24);
      }
      sheetObject.setRowHeight(0, 22);

      // Filas de datos
      for (var v in _ventas) {
        final date = DateFormat('dd/MM/yyyy').format(v.fecha);
        final time = DateFormat('HH:mm').format(v.fecha);
        final detalles = v.items
            .map((i) {
              final base = '${i.formatoCantidad} ${i.productoNombre}';
              final extras = [
                if (i.tieneVariante) i.etiquetaVariante,
                if (i.tieneTamano) i.tamanoNombre!,
                if (i.conjuntosElegidos.isNotEmpty) i.etiquetaExtras,
              ].join(' · ');
              return extras.isEmpty ? base : '$base ($extras)';
            })
            .join(', ');

        sheetObject.appendRow([
          TextCellValue(v.id.substring(0, 8).toUpperCase()),
          TextCellValue(date),
          TextCellValue(time),
          TextCellValue(v.metodoPago.toUpperCase()),
          IntCellValue(v.totalItems),
          DoubleCellValue(v.subtotal),
          DoubleCellValue(v.descuento),
          DoubleCellValue(v.total),
          DoubleCellValue(v.gananciaTotal),
          TextCellValue(detalles),
        ]);
      }

      var fileBytes = excel.save();
      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final path = '${dir.path}/SzrVentas_Ventas_$dateStr.xlsx';
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes!);

      await Share.shareXFiles([
        XFile(path),
      ], text: 'Reporte de Ventas Szr Ventas');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Widget _buildVentaCard(Venta v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _mostrarDetalle(v),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${v.id.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${v.totalItems} prod. • ${_df.format(v.fecha)}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatMoney(v.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildMetodoBadge(v.metodoPago),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetodoBadge(String metodo) {
    Color color;
    String label;
    switch (metodo) {
      case 'yape':
        color = const Color(0xFF6C2DC7);
        label = 'Yape';
        break;
      case 'plin':
        color = const Color(0xFF00BFA5);
        label = 'Plin';
        break;
      case 'tarjeta':
        color = AppTheme.info;
        label = 'Tarjeta';
        break;
      default:
        color = AppTheme.success;
        label = 'Efectivo';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _mostrarDetalle(Venta v) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: const Text(
                'Detalle de Venta',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                '#${v.id.substring(0, 8).toUpperCase()}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            Center(
              child: Text(
                _df.format(v.fecha),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            ...v.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productoNombre,
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (item.tieneVariante) VarianteChips(item: item),
                          DetalleChips(item: item),
                        ],
                      ),
                    ),
                    Text(
                      item.formatoCantidad,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _formatMoney(item.subtotal),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatMoney(v.total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await PrinterService.instance.imprimirTicket(v);
                    HapticFeedback.heavyImpact();
                    SoundPlayer.caja();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No se pudo imprimir: $e'),
                        backgroundColor: AppTheme.warning,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('Reimprimir Ticket'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _enviarWhatsApp(v),
                icon: const Icon(
                  Icons.chat_rounded,
                  color: Color(0xFF25D366),
                ),
                label: const Text('Enviar por WhatsApp'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _enviarWhatsAppCliente(ctx, v),
                icon: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF25D366),
                ),
                label: const Text('WhatsApp del cliente'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _eliminarVentaUnica(v),
                icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                label: const Text(
                  'Eliminar Venta',
                  style: TextStyle(color: AppTheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviarWhatsApp(Venta v) async {
    await PrinterService.instance.cargarDesdePrefs();
    final ps = PrinterService.instance;

    // Precarga el logo ANTES de capturar el ticket, así no queda a
    // medio decodificar cuando se toma la foto en celulares lentos.
    if (ps.logoPath != null && File(ps.logoPath!).existsSync()) {
      await precacheImage(FileImage(File(ps.logoPath!)), context);
      if (!mounted) return;
    }

    final bytes = await WidgetImageCapture.captura(
      context,
      TicketReceiptWidget(
        venta: v,
        nombreNegocio: ps.nombreNegocio,
        ruc: ps.ruc,
        direccion: ps.direccion,
        telefono: ps.telefono,
        mensajePie: ps.mensajePie,
        monedaSimbolo: ps.monedaSimbolo,
        logoPath: ps.logoPath,
      ),
    );

    bool ok;
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ticket_${v.id.substring(0, 8)}.png');
      await file.writeAsBytes(bytes);
      ok = await WhatsAppShare.enviarImagen(imagen: file);
    } else {
      final texto = await PrinterService.instance.textoTicket(v);
      ok = await WhatsAppShare.enviar(texto: texto);
    }

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _enviarWhatsAppCliente(BuildContext sheetContext, Venta v) async {
    final ctrl = TextEditingController();
    final numero = await showDialog<String>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('WhatsApp del cliente'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Número',
            hintText: '987654321',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (numero == null || numero.isEmpty) return;

    final normalizado = WhatsAppShare.normalizarNumero(numero);
    if (normalizado == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Número inválido. Ej: 987654321'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    await PrinterService.instance.cargarDesdePrefs();
    final ps = PrinterService.instance;

    // Precarga el logo ANTES de capturar el ticket, así no queda a
    // medio decodificar cuando se toma la foto en celulares lentos.
    if (ps.logoPath != null && File(ps.logoPath!).existsSync()) {
      await precacheImage(FileImage(File(ps.logoPath!)), context);
      if (!mounted) return;
    }

    // Se genera la MISMA imagen que usan los otros botones de WhatsApp,
    // para que la boleta se vea igual sin importar el celular de quien
    // la recibe (una imagen no se reajusta como el texto).
    final bytes = await WidgetImageCapture.captura(
      context,
      TicketReceiptWidget(
        venta: v,
        nombreNegocio: ps.nombreNegocio,
        ruc: ps.ruc,
        direccion: ps.direccion,
        telefono: ps.telefono,
        mensajePie: ps.mensajePie,
        monedaSimbolo: ps.monedaSimbolo,
        logoPath: ps.logoPath,
      ),
    );

    bool ok;
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ticket_${v.id.substring(0, 8)}.png');
      await file.writeAsBytes(bytes);
      // WhatsApp no permite abrir un chat concreto y adjuntar una foto
      // en un solo paso: primero se abre el chat del cliente...
      await WhatsAppShare.abrirChat(normalizado);
      // ...y luego se abre el selector para enviar la imagen; ese chat
      // aparece primero por haberse usado recién.
      ok = await WhatsAppShare.enviarImagen(imagen: file);
    } else {
      // Solo si la imagen no se pudo generar por algún error.
      final texto = await PrinterService.instance.textoTicket(v);
      ok = await WhatsAppShare.enviar(texto: texto, numero: normalizado);
    }

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}
