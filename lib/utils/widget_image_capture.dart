import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Convierte un widget en una imagen PNG sin mostrarlo al usuario.
///
/// Se inserta temporalmente en un [OverlayEntry] fuera de la pantalla
/// visible, se espera a que se pinte, se captura como imagen y luego se
/// retira. Se usa para generar el ticket de venta como foto (con el logo
/// del negocio) para compartir por WhatsApp.
///
/// La imagen es la única forma de que el ticket se vea igual en
/// cualquier celular (el texto plano de respaldo sí se puede desalinear
/// según la fuente/ancho de pantalla de quien lo recibe). Por eso aquí no
/// se depende de una sola espera fija de milisegundos: se reintenta la
/// captura en varios frames hasta que dos capturas seguidas son
/// idénticas, lo que indica que el widget (incluido el logo, que se
/// decodifica de forma asíncrona) ya terminó de pintarse por completo.
/// Antes esa espera fija alcanzaba en celulares rápidos pero fallaba en
/// otros más lentos o con la app ocupada justo tras cobrar, devolviendo
/// `null` y cayendo al texto plano que se desalinea.
class WidgetImageCapture {
  static Future<Uint8List?> captura(
    BuildContext context,
    Widget widget, {
    double pixelRatio = 2.5,
    int maxIntentos = 10,
  }) async {
    final repaintKey = GlobalKey();
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -9999,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(key: repaintKey, child: widget),
        ),
      ),
    );

    overlay.insert(entry);

    try {
      Uint8List? anterior;

      for (var intento = 0; intento < maxIntentos; intento++) {
        // Espera a que Flutter termine de pintar el frame actual.
        await WidgetsBinding.instance.endOfFrame;
        // Pequeño margen extra para dar tiempo a decodificar imágenes
        // (el logo) o terminar layouts en dispositivos más lentos.
        await Future.delayed(const Duration(milliseconds: 40));

        final boundary = repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) continue;

        final actual = await _capturarBoundary(boundary, pixelRatio);
        if (actual == null) continue;

        // Dos capturas consecutivas idénticas ⇒ el widget ya se
        // estabilizó (logo cargado, layout final). Se devuelve esa.
        if (anterior != null && _sonIguales(anterior, actual)) {
          return actual;
        }
        anterior = actual;
      }

      // No se confirmó estabilidad en maxIntentos frames, pero si se
      // obtuvo al menos una captura válida se usa esa antes de caer al
      // texto plano de respaldo.
      return anterior;
    } catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }

  static Future<Uint8List?> _capturarBoundary(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static bool _sonIguales(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
