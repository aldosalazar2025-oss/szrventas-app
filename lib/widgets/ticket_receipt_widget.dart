import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/venta.dart';
import '../utils/currency_formatter.dart';
import '../utils/peso_formatter.dart';

/// Dibuja el ticket de una venta como una tarjeta blanca con texto
/// estilo "recibo impreso", incluyendo el logo del negocio si hay uno
/// configurado.
///
/// No se muestra en pantalla al usuario: se usa junto a
/// [WidgetImageCapture] para convertirlo en una imagen PNG y compartirlo
/// por WhatsApp u otras apps.
///
/// IMPORTANTE sobre el layout: las columnas (cantidad/producto a la
/// izquierda, precio a la derecha) YA NO se arman rellenando el string
/// con espacios en blanco hasta un ancho fijo de caracteres. Ese truco
/// asumía una fuente monoespaciada real, y en varios fabricantes
/// Android (MIUI, ColorOS, One UI, etc.) la familia 'monospace'
/// genérica se remapea a una fuente proporcional: el mismo texto
/// terminaba ocupando más o menos ancho del esperado, la línea se
/// envolvía y toda la estructura del ticket se descuadraba (eso es lo
/// que se veía en la captura: el guion suelto, "Cant Producto" y
/// "Total" partidos en líneas distintas, etc).
///
/// Ahora cada línea se arma con un Row (columna izquierda en Expanded
/// + columna derecha de ancho natural) y las líneas horizontales con un
/// CustomPainter que dibuja los guiones a lo ancho real del contenedor.
/// La alineación depende del layout de Flutter, no del ancho de
/// carácter de una fuente — por lo tanto se ve igual en cualquier
/// dispositivo, tenga o no una fuente monospace real.
class TicketReceiptWidget extends StatelessWidget {
  const TicketReceiptWidget({
    super.key,
    required this.venta,
    required this.nombreNegocio,
    required this.ruc,
    required this.direccion,
    required this.telefono,
    required this.mensajePie,
    required this.monedaSimbolo,
    this.logoPath,
    this.width = 380,
  });

  final Venta venta;
  final String nombreNegocio;
  final String ruc;
  final String direccion;
  final String telefono;
  final String mensajePie;
  final String monedaSimbolo;
  final String? logoPath;
  final double width;

  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.5,
    color: Colors.black,
  );

  String _formatMoney(double v) => CurrencyFormatter.format(v, monedaSimbolo);

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

  /// Línea de dos columnas: texto a la izquierda (se trunca con "…" si
  /// no cabe) y texto a la derecha, siempre alineado al borde derecho
  /// sin importar el ancho real de los caracteres de la fuente.
  Widget _lr(String left, String right, {TextStyle? style, double indent = 0}) {
    final s = style ?? _mono;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              left,
              style: s,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(right, style: s, maxLines: 1, softWrap: false),
        ],
      ),
    );
  }

  Widget _hr() => const SizedBox(
        height: 12,
        width: double.infinity,
        child: CustomPaint(painter: _DashedLinePainter(), size: Size.infinite),
      );

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final tieneLogo = logoPath != null && File(logoPath!).existsSync();

    return Material(
      color: Colors.white,
      child: Container(
        width: width,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tieneLogo) ...[
              Center(
                child: Image.file(
                  File(logoPath!),
                  height: 90,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              nombreNegocio.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            if (ruc.isNotEmpty)
              Text('RUC: $ruc', textAlign: TextAlign.center, style: _mono),
            if (direccion.isNotEmpty)
              Text(direccion, textAlign: TextAlign.center, style: _mono),
            if (telefono.isNotEmpty)
              Text('Tel: $telefono', textAlign: TextAlign.center, style: _mono),
            const SizedBox(height: 10),
            _hr(),
            _lr('TICKET DE VENTA', '#${venta.id.substring(0, 8).toUpperCase()}'),
            Text('Fecha: ${df.format(venta.fecha)}', style: _mono),
            _hr(),
            _lr('Cant  Producto', 'Total'),
            _hr(),
            for (final item in venta.items) ..._lineasItem(item),
            _hr(),
            if (venta.descuento > 0) ...[
              _lr('Subtotal:', _formatMoney(venta.subtotal)),
              _lr('Descuento:', '-${_formatMoney(venta.descuento)}'),
            ],
            _lr(
              'TOTAL:',
              _formatMoney(venta.total),
              style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _lr('Pago:', _metodoPagoLabel(venta.metodoPago)),
            if (venta.montoPagado != null)
              _lr('Pago con:', _formatMoney(venta.montoPagado!)),
            if (venta.vuelto != null && venta.vuelto! > 0)
              _lr('Vuelto:', _formatMoney(venta.vuelto!)),
            if (venta.nota != null && venta.nota!.trim().isNotEmpty) ...[
              _hr(),
              Text('Nota: ${venta.nota!.trim()}', style: _mono),
            ],
            _hr(),
            const SizedBox(height: 8),
            Text(mensajePie, textAlign: TextAlign.center, style: _mono),
          ],
        ),
      ),
    );
  }

  List<Widget> _lineasItem(ItemVenta item) {
    final cant = item.esPeso
        ? PesoFormatter.formatTicket(item.cantidad)
        : '${item.cantidad}';
    final nombre = item.productoNombre;
    final total = _formatMoney(item.subtotal);
    final left = '$cant  $nombre';

    final widgets = <Widget>[_lr(left, total)];

    if (item.tieneVariante) {
      final partes = [item.varianteTalla, item.varianteColor]
          .where((e) => e != null && e.trim().isNotEmpty)
          .join(' / ');
      if (partes.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(partes, style: _mono, maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
    }
    if (item.tieneTamano || item.conjuntosElegidos.isNotEmpty) {
      final partes = [
        if (item.tieneTamano) item.tamanoNombre!,
        if (item.conjuntosElegidos.isNotEmpty) item.etiquetaExtras,
      ].join(' / ');
      if (partes.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(partes, style: _mono, maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
    }
    return widgets;
  }
}

/// Dibuja una línea punteada horizontal que siempre ocupa el ancho real
/// del widget, sin depender de que ningún carácter de texto sea
/// monoespaciado.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.2;
    final y = size.height / 2;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
