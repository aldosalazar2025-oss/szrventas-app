import 'dart:io';
import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:barcode_image/barcode_image.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'barcode_generator.dart';

/// Dibuja el código de barras directamente como una imagen PNG (sin
/// necesidad de mostrar nada en pantalla) y la deja guardada, lista para
/// compartir o abrir con el panel de "Guardar / Compartir" del teléfono.
class BarcodeImageExporter {
  BarcodeImageExporter._();

  /// Elige el tipo de símbolo de barra más apropiado según el formato del
  /// código (EAN-13, UPC-A, o Code128 para cualquier otro texto/número).
  static Barcode _tipoParaCodigo(String codigo) => BarcodeGenerator.tipoParaCodigo(codigo);

  /// Dibuja el código de barras (con el nombre del producto encima) y
  /// devuelve los bytes PNG en memoria, sin tocar el almacenamiento. Es la
  /// base que usan tanto [generarPng] (una etiqueta suelta) como la
  /// exportación en PDF de varias etiquetas juntas.
  static Uint8List generarPngBytes({
    required String codigo,
    required String nombreProducto,
  }) {
    const ancho = 700;
    const alto = 320;
    final image = img.Image(width: ancho, height: alto);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Nombre del producto arriba, como una etiqueta lista para imprimir.
    if (nombreProducto.trim().isNotEmpty) {
      img.drawString(
        image,
        nombreProducto.trim(),
        font: img.arial24,
        x: (ancho / 2 - nombreProducto.trim().length * 6).round().clamp(4, ancho),
        y: 10,
        color: img.ColorRgb8(0, 0, 0),
      );
    }

    drawBarcode(
      image,
      _tipoParaCodigo(codigo),
      codigo,
      font: img.arial24,
      x: 16,
      y: 42,
      width: ancho - 32,
      height: alto - 58,
    );

    return img.encodePng(image);
  }

  /// Genera la imagen del código de barras y la guarda en el almacenamiento
  /// de la app. Devuelve la ruta del archivo PNG generado.
  static Future<String> generarPng({
    required String codigo,
    required String nombreProducto,
  }) async {
    final bytes = generarPngBytes(codigo: codigo, nombreProducto: nombreProducto);
    final dir = await getApplicationDocumentsDirectory();
    final base = nombreProducto.trim().isEmpty ? codigo : nombreProducto.trim();
    final nombreLimpio = base.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final path = '${dir.path}/codigo_barras_$nombreLimpio.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }
}
