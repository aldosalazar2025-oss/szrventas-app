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
  // true = imprime ñ y tildes (página de códigos PC850); false = cambia a n/a/e/i/o/u.
  bool _tildes = true;

  int get _chars => _anchoPapel == 80.0 ? 48 : 32;

  String _stripAccents(String str) {
    final base = str
        .replaceAll('¡', '')
        .replaceAll('¿', '')
        .replaceAll('—', '-')
        .replaceAll('–', '-');
    final sinAcentos = _quitarAcentos(base);
    // La impresora solo entiende ASCII básico: cualquier otro símbolo
    // (emojis, etc.) se cambia por '?' para que no falle la impresión.
    return String.fromCharCodes(
      sinAcentos.runes.map((c) => (c >= 32 && c <= 126) ? c : (c == 9 ? 32 : 63)),
    );
  }

  // Equivalencias PC850 (ESC t 2) para el español.
  static const Map<String, int> _cp850 = {
    'á': 0xA0, 'é': 0x82, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3,
    'ñ': 0xA4, 'Ñ': 0xA5, '¿': 0xA8, '¡': 0xAD, 'ü': 0x81, 'Ü': 0x9A,
    'Á': 0xB5, 'É': 0x90, 'Í': 0xD6, 'Ó': 0xE0, 'Ú': 0xE9,
    'º': 0xA7, 'ª': 0xA6,
  };

  /// Comando para elegir la página de códigos según la opción de ajustes.
  List<int> get comandoCodepage => [0x1B, 0x74, _tildes ? 0x02 : 0x00];

  /// Convierte el texto a bytes para la impresora. Con tildes activadas usa
  /// PC850; si no, deja solo ASCII (ñ -> n, á -> a, etc.).
  List<int> codificar(String texto) {
    if (!_tildes) return latin1.encode(_stripAccents(texto));
    final out = <int>[];
    for (final r in texto.runes) {
      final ch = String.fromCharCode(r);
      if (r >= 32 && r <= 126) {
        out.add(r);
      } else if (_cp850.containsKey(ch)) {
        out.add(_cp850[ch]!);
      } else if (r == 9) {
        out.add(32);
      } else {
        final alt = _stripAccents(ch);
        out.add(alt.isNotEmpty ? alt.codeUnitAt(0) : 63);
      }
    }
    return out;
  }

  String _quitarAcentos(String str) {
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
    bool? tildes,
  }) {
    if (tildes != null) _tildes = tildes;
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
      moneda: (prefs.getString('moneda_simbolo')?.trim().isNotEmpty ?? false) ? prefs.getString('moneda_simbolo')!.trim() : 'S/',
      vendedor: prefs.getString('vendedor_activo'),
      tildes: prefs.getBool('imprimir_tildes') ?? true,
    );
  }

  bool get imprimirTildes => _tildes;

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

  /// Parte [text] en líneas SIN cortar palabras. [firstW] es el ancho de la
  /// primera línea y [restW] el de las siguientes. Una palabra más larga que
  /// el ancho disponible se parte solo como último recurso.
  List<String> _wrap(String text, int firstW, int restW) {
    if (firstW < 1) firstW = 1;
    if (restW < 1) restW = 1;
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var cur = '';
    var width = firstW;
    for (var w in words) {
      if (cur.isEmpty) {
        while (w.length > width) {
          lines.add(w.substring(0, width));
          w = w.substring(width);
          width = restW;
        }
        cur = w;
      } else if (cur.length + 1 + w.length <= width) {
        cur = '$cur $w';
      } else {
        lines.add(cur);
        width = restW;
        cur = '';
        while (w.length > width) {
          lines.add(w.substring(0, width));
          w = w.substring(width);
        }
        cur = w;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

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
    final bytes = <int>[
      0x1B, 0x61, 0x01, // ESC a 1 = centrar
    ];
    if (negrita) bytes.addAll([0x1B, 0x45, 0x01]);
    if (grande) bytes.addAll([0x1D, 0x21, 0x11]); // ancho y alto x2
    bytes.addAll(codificar(texto));
    bytes.add(0x0A);
    if (grande) bytes.addAll([0x1D, 0x21, 0x00]);
    if (negrita) bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll([0x1B, 0x61, 0x00]); // volver a la izquierda
    return bytes;
  }

  /// Centrado con salto de línea por palabras (sin cortar palabras).
  /// En tamaño grande entran la mitad de caracteres por línea.
  List<int> _bytesCentradoWrap(
    String texto, {
    bool grande = false,
    bool negrita = false,
  }) {
    final ancho = grande ? _chars ~/ 2 : _chars;
    final out = <int>[];
    for (final l in _wrap(texto, ancho, ancho)) {
      out.addAll(_bytesCentrado(l, grande: grande, negrita: negrita));
    }
    return out;
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

    var conectado = false;
    try {
      conectado = await PrintBluetoothThermal.connectionStatus;
    } catch (_) {}
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
    bytes += comandoCodepage;

    bytes += await _bytesLogo(generator);

    bytes += _bytesCentradoWrap(
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

    for (final line in _lineasCuerpo(venta)) {
      bytes.addAll([0x1B, 0x61, 0x00]);
      bytes.addAll(codificar(line));
      bytes.add(0x0A);
    }

    bytes += _bytesCentrado(_mensajePie);
    bytes += _bytesCentrado('Szr Ventas');

    bytes += generator.feed(2);
    bytes += generator.cut();

    var ok = false;
    try {
      ok = await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {}
    if (!ok) {
      // La conexión pudo quedar vieja (impresora apagada/reconectada):
      // se reconecta una vez y se reintenta.
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
      final res = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!res) throw Exception('No se pudo conectar a la impresora');
      ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw Exception('No se pudo imprimir el ticket');
    }
  }

  Future<List<BluetoothInfo>> obtenerImpresoras() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }
}
