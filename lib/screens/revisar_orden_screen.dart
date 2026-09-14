import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../providers/carrito_provider.dart';
import '../services/printer_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/metodos_pago_config.dart';
import '../utils/sound_player.dart';
import '../utils/whatsapp_share.dart';
import '../utils/widget_image_capture.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/safe_bottom_bar.dart';
import '../widgets/variante_chips.dart';
import '../widgets/detalle_chips.dart';
import '../widgets/ticket_receipt_widget.dart';
import '../models/venta.dart';

class RevisarOrdenScreen extends StatefulWidget {
  const RevisarOrdenScreen({super.key});
  @override
  State<RevisarOrdenScreen> createState() => _RevisarOrdenScreenState();
}

class _RevisarOrdenScreenState extends State<RevisarOrdenScreen> {
  String _metodoPago = 'efectivo';
  final _montoCtrl = TextEditingController();
  final _descuentoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  // 'monto' = S/ , 'porcentaje' = %
  String _modoDescuento = 'monto';
  bool _procesando = false;
  String? _yapeQrPath;
  String? _plinQrPath;
  List<String> _metodosHabilitados = List.from(MetodosPagoConfig.todos);
  String _monedaSimbolo = 'S/';
  Venta? _ventaOk;
  String? _avisoImpresion;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
  }

  Future<void> _cargarAjustes() async {
    final prefs = await SharedPreferences.getInstance();
    final habilitados =
        prefs.getStringList(MetodosPagoConfig.prefsKey) ??
        List.from(MetodosPagoConfig.todos);
    if (mounted) {
      setState(() {
        _yapeQrPath = prefs.getString('yape_qr_path');
        _plinQrPath = prefs.getString('plin_qr_path');
        _metodosHabilitados = habilitados;
        _monedaSimbolo = prefs.getString('moneda_simbolo') ?? 'S/';
        if (!_metodosHabilitados.contains(_metodoPago)) {
          _metodoPago = _metodosHabilitados.first;
        }
      });
    }
  }

  String? _qrPathActual() {
    switch (_metodoPago) {
      case 'yape':
        return _yapeQrPath;
      case 'plin':
        return _plinQrPath;
      default:
        return null;
    }
  }

  Color _colorMetodo(String metodo) =>
      MetodosPagoConfig.colors[metodo] ?? AppTheme.primary;

  String _formatMoney(double amount) {
    return CurrencyFormatter.format(amount, _monedaSimbolo);
  }

  double _getVuelto(double total) {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    return (monto - total).clamp(0, double.infinity);
  }

  void _aplicarDescuento(CarritoProvider carrito) {
    final valor =
        double.tryParse(_descuentoCtrl.text.replaceAll(',', '.')) ?? 0.0;
    double descuentoEnMoneda;
    if (_modoDescuento == 'porcentaje') {
      final double pct = valor.clamp(0.0, 100.0);
      descuentoEnMoneda = carrito.subtotal * (pct / 100.0);
    } else {
      descuentoEnMoneda = valor;
    }
    carrito.setDescuento(descuentoEnMoneda);
  }

  Future<void> _procesar(CarritoProvider carrito) async {
    if (_metodoPago == 'efectivo') {
      final monto = double.tryParse(_montoCtrl.text) ?? 0;
      if (monto < carrito.total) {
        _mostrarAviso('Monto insuficiente', AppTheme.error);
        return;
      }
    }
    setState(() {
      _procesando = true;
      _guardando = true;
    });
    try {
      final venta = await carrito.finalizarVenta(
        metodoPago: _metodoPago,
        montoPagado: _metodoPago == 'efectivo'
            ? double.tryParse(_montoCtrl.text)
            : null,
        nota: _notaCtrl.text,
      );

      if (!mounted) return;
      setState(() {
        _ventaOk = venta;
        _procesando = false;
      });

      HapticFeedback.heavyImpact();
      SoundPlayer.caja();

      try {
        await PrinterService.instance.imprimirTicket(venta);
      } catch (e) {
        if (mounted) {
          setState(() {
            _avisoImpresion =
                'Venta guardada. No se pudo imprimir: $e';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _procesando = false;
          _guardando = false;
        });
        _mostrarAviso('Error: $e', AppTheme.error);
      }
    }
  }

  void _mostrarAviso(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 80),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _seguirVendiendo() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _compartirWhatsApp(Venta venta) async {
    await PrinterService.instance.cargarDesdePrefs();
    final ps = PrinterService.instance;

    // Precarga el logo ANTES de capturar el ticket. Si el logo todavía
    // se está decodificando cuando se toma la foto, esa foto puede salir
    // sin logo o desalineada en celulares más lentos.
    if (ps.logoPath != null && File(ps.logoPath!).existsSync()) {
      await precacheImage(FileImage(File(ps.logoPath!)), context);
      if (!mounted) return;
    }

    final bytes = await WidgetImageCapture.captura(
      context,
      TicketReceiptWidget(
        venta: venta,
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
      final file = File(
        '${dir.path}/ticket_${venta.id.substring(0, 8)}.png',
      );
      await file.writeAsBytes(bytes);
      ok = await WhatsAppShare.enviarImagen(imagen: file);
    } else {
      // Si algo falla al generar la imagen, se envía como texto.
      final texto = await PrinterService.instance.textoTicket(venta);
      ok = await WhatsAppShare.enviar(texto: texto);
    }

    if (!ok && mounted) {
      _mostrarAviso('No se pudo abrir WhatsApp', AppTheme.error);
    }
  }

  Future<void> _reimprimir(Venta venta) async {
    try {
      await PrinterService.instance.imprimirTicket(venta);
      HapticFeedback.heavyImpact();
      SoundPlayer.caja();
    } catch (e) {
      if (mounted) {
        _mostrarAviso('No se pudo imprimir: $e', AppTheme.warning);
      }
    }
  }

  Widget _buildGracias(Venta venta) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 72,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '¡Gracias por su compra!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _formatMoney(venta.total),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              if (venta.vuelto != null && venta.vuelto! > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Vuelto: ${_formatMoney(venta.vuelto!)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ],
              if (_avisoImpresion != null) ...[
                const SizedBox(height: 16),
                Text(
                  _avisoImpresion!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _seguirVendiendo,
                  icon: const Icon(Icons.storefront_rounded),
                  label: const Text(
                    'Seguir vendiendo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _compartirWhatsApp(venta),
                  icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                  label: const Text(
                    'Compartir por WhatsApp',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton.icon(
                  onPressed: () => _reimprimir(venta),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Imprimir de nuevo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ventaOk != null) return _buildGracias(_ventaOk!);

    return Consumer<CarritoProvider>(
      builder: (context, carrito, _) {
        if (_guardando) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (carrito.isEmpty && _ventaOk == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _ventaOk == null) Navigator.pop(context);
          });
          return const Scaffold();
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Revisar Orden'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Resumen de items
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
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${carrito.totalItems} artículos',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...carrito.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
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
                                  if (item.tieneVariante)
                                    VarianteChips(item: item),
                                  DetalleChips(item: item),
                                ],
                              ),
                            ),
                            Text(
                              item.formatoCantidad,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              _formatMoney(item.subtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 24),

                    // Descuento
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _descuentoCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Descuento',
                              prefixIcon: const Icon(
                                Icons.sell_outlined,
                                size: 20,
                                color: AppTheme.textMuted,
                              ),
                              filled: true,
                              fillColor: AppTheme.bgGrey,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) => setState(() {
                              _aplicarDescuento(carrito);
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildToggleDescuento(carrito),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (carrito.descuento > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Subtotal',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            _formatMoney(carrito.subtotal),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Descuento',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '-${_formatMoney(carrito.descuento)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatMoney(carrito.total),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Nota (opcional)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: _notaCtrl,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Nota (opcional)',
                    prefixIcon: Icon(
                      Icons.notes_rounded,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Método de pago
              const Text(
                'Método de Pago',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < _metodosHabilitados.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _buildMetodo(_metodosHabilitados[i]),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              if (MetodosPagoConfig.soportaQr(_metodoPago) &&
                  _qrPathActual() != null) ...[
                Text(
                  'Escanea para pagar con ${MetodosPagoConfig.label(_metodoPago)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _colorMetodo(_metodoPago),
                        width: 2,
                      ),
                    ),
                    child: Image.file(
                      File(_qrPathActual()!),
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Monto recibido (solo efectivo)
              if (_metodoPago == 'efectivo') ...[
                const Text(
                  'Monto Recibido',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '$_monedaSimbolo ',
                    prefixStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    filled: true,
                    fillColor: AppTheme.bgWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                // Montos rápidos
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [5, 10, 20, 50, 100, 200]
                      .map(
                        (m) => ActionChip(
                          label: Text(
                            '$_monedaSimbolo$m',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          backgroundColor: AppTheme.bgWhite,
                          side: const BorderSide(color: AppTheme.border),
                          onPressed: () {
                            _montoCtrl.text = '$m.00';
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                if (_getVuelto(carrito.total) > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.reply, color: AppTheme.warning),
                            SizedBox(width: 8),
                            Text(
                              'Vuelto:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatMoney(_getVuelto(carrito.total)),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 8),
              SafeBottomBar(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _procesando ? null : () => _procesar(carrito),
                    icon: _procesando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 22),
                    label: Text(
                      _procesando ? 'Procesando...' : 'Confirmar Venta',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleDescuento(CarritoProvider carrito) {
    Widget opcion(String modo, String label) {
      final selected = _modoDescuento == modo;
      return GestureDetector(
        onTap: () {
          setState(() {
            _modoDescuento = modo;
            _aplicarDescuento(carrito);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion('monto', _monedaSimbolo),
          opcion('porcentaje', '%'),
        ],
      ),
    );
  }

  Widget _buildMetodo(String value) {
    final selected = _metodoPago == value;
    final color = _colorMetodo(value);
    final icon = MetodosPagoConfig.icons[value] ?? Icons.payment;
    final label = MetodosPagoConfig.label(value);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _metodoPago = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : AppTheme.bgWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? color : AppTheme.textMuted,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _descuentoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }
}
