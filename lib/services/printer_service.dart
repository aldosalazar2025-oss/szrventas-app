import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/venta.dart';
import '../utils/currency_formatter.dart';
import '../utils/peso_formatter.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._();
  PrinterService._();

  String _monedaSimbolo = 'S/';
  String _nombreNegocio = 'SZR VENTAS';
  String _direccion = '';
  String _telefono = '';
  String _ruc = '';
  String? _logoPath;
  String _mensajePie = '¡Gracias por su compra!';
  double _anchoPapel = 58.0;
  String? _impresoraMac;
  String? _impresoraNombre;
  String? _vendedor;

  int get _chars => _anchoPapel == 80.0 ? 48 : 32;

  String _stripAccents(String str) {
    return str
        .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u')
        .replaceAll('Á', 'A').replaceAll('É', 'E').replaceAll('Í', 'I').replaceAll('Ó', 'O').replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n').replaceAll('Ñ', 'N');
  }

  String _formatMoney(double amount) =>
      CurrencyFormatter.format(amount, _monedaSimbolo);

  void configurar({
    String? nombre,
    String? direccion,
    String? telefono,
    String? ruc,
    String? logoPath,
    String? mensaje,
    double? anchoPapel,
    String? mac,
    String? printerName,
    String? moneda,
    String? vendedor,
  }) {
    if (nombre != null) _nombreNegocio = nombre;
    if (direccion != null) _direccion = direccion;
    if (telefono != null) _telefono = telefono;
    if (ruc != null) _ruc = ruc;
    _logoPath = logoPath;
    if (mensaje != null) _mensajePie = mensaje;
    if (anchoPapel != null) _anchoPapel = anchoPapel;
    if (mac != null) _impresoraMac = mac;
    if (printerName != null) _impresoraNombre = printerName;
    if (moneda != null) _monedaSimbolo = moneda;
    if (vendedor != null) _vendedor = vendedor;
  }

  Future<void> cargarDesdePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    configurar(
      nombre: prefs.getString('negocio_nombre') ?? _nombreNegocio,
      direccion: prefs.getString('negocio_direccion') ?? '',
      telefono: prefs.getString('negocio_telefono') ?? '',
      ruc: prefs.getString('negocio_ruc') ?? '',
      logoPath: prefs.getString('negocio_logo_path'),
      mensaje: prefs.getString('negocio_mensaje') ?? _mensajePie,
      anchoPapel: prefs.getDouble('impresora_ancho') ?? 58.0,
      mac: prefs.getString('impresora_mac'),
      printerName: prefs.getString('impresora_nombre'),
      moneda: prefs.getString('moneda_simbolo') ?? 'S/',
      vendedor: prefs.getString('vendedor_activo'),
    );
  }

  String? get impresoraNombre => _impresoraNombre;
  String? get impresoraMac => _impresoraMac;

  // Getters usados para generar el ticket como imagen (compartir por
  // WhatsApp con el logo incluido, ya que el texto plano no puede
  // llevar imágenes).
  String get nombreNegocio => _nombreNegocio;
  String get ruc => _ruc;
  String get direccion => _direccion;
  String get telefono => _telefono;
  String get mensajePie => _mensajePie;
  String get monedaSimbolo => _monedaSimbolo;
  String? get logoPath => _logoPath;

  String _hr() => '-' * _chars;

  String _lr(String left, String right) {
    if (right.length >= _chars) return right.substring(0, _chars);
    final maxLeft = _chars - right.length - 1;
    var l = left;
    if (l.length > maxLeft) l = l.substring(0, maxLeft);
    final spaces = _chars - l.length - right.length;
    return '$l${' ' * spaces}$right';
  }

  String _metodoPagoLabel(String metodo) {
    switch (metodo) {
      case 'efectivo':
        return 'Efectivo';
      case 'yape':
        return 'Yape';
      case 'plin':
        return 'Plin';
      case 'tarjeta':
        return 'Tarjeta';
      default:
        return metodo;
    }
  }

  List<String> _lineasCuerpo(Venta venta) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final lines = <String>[];
    lines.add(_hr());
    lines.add(_lr(
      'TICKET DE VENTA',
      '#${venta.id.substring(0, 8).toUpperCase()}',
    ));
    lines.add(_lr('Fecha:', dateFormat.format(venta.fecha)));
    if (_vendedor != null && _vendedor!.isNotEmpty) {
      lines.add(_lr('Atendido por:', _vendedor!));
    }
    lines.add(_hr());
    lines.add(_lr('Cant  Producto', 'Total'));
    lines.add(_hr());

    for (final item in venta.items) {
      final cant = item.esPeso
          ? PesoFormatter.formatTicket(item.cantidad)
          : '${item.cantidad}';
      final nombre = item.productoNombre;
      final total = _formatMoney(item.subtotal);
      final left = '$cant  $nombre';
      if (left.length + 1 + total.length <= _chars) {
        lines.add(_lr(left, total));
      } else {
        lines.add(_lr(
          '$cant  ${nombre.length > 18 ? nombre.substring(0, 18) : nombre}',
          total,
        ));
      }
      if (item.tieneVariante) {
        final partes = [item.varianteTalla, item.varianteColor]
            .where((e) => e != null && e.trim().isNotEmpty)
            .join(' / ');
        if (partes.isNotEmpty) {
          final linea = '      $partes';
          lines.add(
            linea.length > _chars ? linea.substring(0, _chars) : linea,
          );
        }
      }
      if (item.tieneTamano || item.conjuntosElegidos.isNotEmpty) {
        final partes = [
          if (item.tieneTamano) item.tamanoNombre!,
          if (item.conjuntosElegidos.isNotEmpty) item.etiquetaExtras,
        ].join(' / ');
        if (partes.isNotEmpty) {
          final linea = '      $partes';
          lines.add(
            linea.length > _chars ? linea.substring(0, _chars) : linea,
          );
        }
      }
    }

    lines.add(_hr());
    if (venta.descuento > 0) {
      lines.add(_lr('Subtotal:', _formatMoney(venta.subtotal)));
      lines.add(_lr('Descuento:', '-${_formatMoney(venta.descuento)}'));
    }
    lines.add(_lr('TOTAL:', _formatMoney(venta.total)));
    lines.add(_lr('Pago:', _metodoPagoLabel(venta.metodoPago)));
    if (venta.montoPagado != null) {
      lines.add(_lr('Pago con:', _formatMoney(venta.montoPagado!)));
    }
    if (venta.vuelto != null && venta.vuelto! > 0) {
      lines.add(_lr('Vuelto:', _formatMoney(venta.vuelto!)));
    }
    if (venta.nota != null && venta.nota!.trim().isNotEmpty) {
      lines.add(_hr());
      lines.add('Nota: ${venta.nota!.trim()}');
    }
    lines.add(_hr());
    return lines;
  }

  /// Texto plano de respaldo para WhatsApp: solo se usa si por algún
  /// error no se pudo generar la imagen del ticket. No alinea columnas
  /// con espacios (como sí hace la impresora térmica), porque WhatsApp
  /// no garantiza una fuente monoespaciada y esos espacios se
  /// desalinean de forma distinta en cada celular. Aquí cada dato va
  /// en su propia línea como "Etiqueta: valor", que se ve igual sin
  /// importar la fuente.
  Future<String> textoTicket(Venta venta) async {
    await cargarDesdePrefs();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final buf = StringBuffer();
    buf.writeln('*${_nombreNegocio.toUpperCase()}*');
    if (_ruc.isNotEmpty) buf.writeln('RUC: $_ruc');
    if (_direccion.isNotEmpty) buf.writeln(_direccion);
    if (_telefono.isNotEmpty) buf.writeln('Tel: $_telefono');
    buf.writeln('');
    buf.writeln('*TICKET DE VENTA* #${venta.id.substring(0, 8).toUpperCase()}');
    buf.writeln('Fecha: ${dateFormat.format(venta.fecha)}');
    if (_vendedor != null && _vendedor!.isNotEmpty) {
      buf.writeln('Atendido por: $_vendedor');
    }
    buf.writeln('');
    for (final item in venta.items) {
      final cant = item.esPeso
          ? PesoFormatter.formatTicket(item.cantidad)
          : '${item.cantidad}';
      buf.writeln('$cant  ${item.productoNombre} — ${_formatMoney(item.subtotal)}');
      if (item.tieneVariante) {
        final partes = [item.varianteTalla, item.varianteColor]
            .where((e) => e != null && e.trim().isNotEmpty)
            .join(' / ');
        if (partes.isNotEmpty) buf.writeln('   $partes');
      }
      if (item.tieneTamano || item.conjuntosElegidos.isNotEmpty) {
        final partes = [
          if (item.tieneTamano) item.tamanoNombre!,
          if (item.conjuntosElegidos.isNotEmpty) item.etiquetaExtras,
        ].join(' / ');
        if (partes.isNotEmpty) buf.writeln('   $partes');
      }
    }
    buf.writeln('');
    if (venta.descuento > 0) {
      buf.writeln('Subtotal: ${_formatMoney(venta.subtotal)}');
      buf.writeln('Descuento: -${_formatMoney(venta.descuento)}');
    }
    buf.writeln('*TOTAL: ${_formatMoney(venta.total)}*');
    buf.writeln('Pago: ${_metodoPagoLabel(venta.metodoPago)}');
    if (venta.montoPagado != null) {
      buf.writeln('Pago con: ${_formatMoney(venta.montoPagado!)}');
    }
    if (venta.vuelto != null && venta.vuelto! > 0) {
      buf.writeln('Vuelto: ${_formatMoney(venta.vuelto!)}');
    }
    if (venta.nota != null && venta.nota!.trim().isNotEmpty) {
      buf.writeln('');
      buf.writeln('Nota: ${venta.nota!.trim()}');
    }
    buf.writeln('');
    buf.writeln(_mensajePie);
    buf.writeln('Szr Ventas');
    return buf.toString().trim();
  }

  /// Centrado real (ESC a 1). No usa espacios: esos empujan el texto a la derecha.
  List<int> _bytesCentrado(
    String texto, {
    bool grande = false,
    bool negrita = false,
  }) {
    final t = _stripAccents(texto);
    final bytes = <int>[
      0x1B, 0x61, 0x01, // ESC a 1 = centrar
    ];
    if (negrita) bytes.addAll([0x1B, 0x45, 0x01]);
    if (grande) bytes.addAll([0x1D, 0x21, 0x11]); // ancho y alto x2
    bytes.addAll(latin1.encode(t));
    bytes.add(0x0A);
    if (grande) bytes.addAll([0x1D, 0x21, 0x00]);
    if (negrita) bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll([0x1B, 0x61, 0x00]); // volver a la izquierda
    return bytes;
  }

  /// Convierte la imagen del logo en bytes ESC/POS listos para imprimir,
  /// redimensionada al ancho del papel y en blanco y negro.
  Future<List<int>> _bytesLogo(Generator generator) async {
    if (_logoPath == null || _logoPath!.isEmpty) return [];
    try {
      final file = File(_logoPath!);
      if (!await file.exists()) return [];
      final bytes = await file.readAsBytes();
      var decodificada = img.decodeImage(bytes);
      if (decodificada == null) return [];

      final anchoMax = _anchoPapel == 80.0 ? 380 : 300;
      if (decodificada.width > anchoMax) {
        decodificada = img.copyResize(decodificada, width: anchoMax);
      }
      decodificada = img.grayscale(decodificada);

      return generator.image(decodificada);
    } catch (_) {
      // Si el logo no se puede leer o procesar, se omite sin afectar
      // el resto del ticket.
      return [];
    }
  }

  Future<void> imprimirTicket(Venta venta, {String? macOverride}) async {
    await cargarDesdePrefs();
    final mac = macOverride ?? _impresoraMac;
    if (mac == null || mac.isEmpty) {
      throw Exception('No hay impresora configurada');
    }

    final conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      final res = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!res) throw Exception('No se pudo conectar a la impresora');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      _anchoPapel == 80.0 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.setGlobalFont(PosFontType.fontA);

    bytes += await _bytesLogo(generator);

    bytes += _bytesCentrado(
      _nombreNegocio.toUpperCase(),
      grande: true,
      negrita: true,
    );
    if (_ruc.isNotEmpty) {
      bytes += _bytesCentrado('RUC: $_ruc');
    }
    if (_direccion.isNotEmpty) {
      bytes += _bytesCentrado(_direccion);
    }
    if (_telefono.isNotEmpty) {
      bytes += _bytesCentrado('Tel: $_telefono');
    }

    const izquierda = PosStyles(align: PosAlign.left);
    for (final line in _lineasCuerpo(venta)) {
      bytes += generator.text(_stripAccents(line), styles: izquierda);
    }

    bytes += _bytesCentrado(_mensajePie);
    bytes += _bytesCentrado('Szr Ventas');

    bytes += generator.feed(2);
    bytes += generator.cut();

    await PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<List<BluetoothInfo>> obtenerImpresoras() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }
}
