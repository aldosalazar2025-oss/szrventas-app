import 'dart:math';
import 'package:barcode/barcode.dart';

/// Genera códigos de barras EAN-13 válidos (con dígito verificador correcto)
/// para productos que no traen su propio código de fábrica.
///
/// Usa el prefijo "20", reservado internacionalmente para uso interno de
/// comercios (no corresponde a ningún fabricante real), evitando así choques
/// con códigos de productos de marca.
class BarcodeGenerator {
  BarcodeGenerator._();

  static final _random = Random();

  /// Genera un código EAN-13 de 13 dígitos, listo para imprimir y escanear.
  static String generarEAN13() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final tsPart = timestamp.substring(timestamp.length - 8);
    final rndPart = List.generate(2, (_) => _random.nextInt(10)).join();
    final base12 = '20$tsPart$rndPart'; // 2 + 8 + 2 = 12 dígitos
    return '$base12${_digitoVerificadorEAN13(base12)}';
  }

  /// Calcula el dígito verificador estándar EAN-13 a partir de los primeros
  /// 12 dígitos.
  static int _digitoVerificadorEAN13(String doce) {
    final digitos = doce.split('').map(int.parse).toList();
    var suma = 0;
    for (var i = 0; i < 12; i++) {
      suma += digitos[i] * (i.isEven ? 1 : 3);
    }
    return (10 - (suma % 10)) % 10;
  }

  /// Valida si un texto es un EAN-13 numéricamente correcto (13 dígitos y
  /// checksum válido). Útil para decidir qué tipo de barra dibujar.
  static bool esEAN13Valido(String codigo) {
    if (!RegExp(r'^\d{13}$').hasMatch(codigo)) return false;
    final base12 = codigo.substring(0, 12);
    final checkEsperado = _digitoVerificadorEAN13(base12);
    return int.parse(codigo[12]) == checkEsperado;
  }

  /// Elige el tipo de símbolo de barra más apropiado según el formato del
  /// código (EAN-13, UPC-A, o Code128 para cualquier otro texto/número).
  /// Se usa tanto para dibujar en pantalla como para exportar a PNG o PDF,
  /// así todas las representaciones del mismo código quedan consistentes.
  static Barcode tipoParaCodigo(String codigo) {
    if (esEAN13Valido(codigo)) return Barcode.ean13();
    if (RegExp(r'^\d{12}$').hasMatch(codigo)) return Barcode.upcA();
    return Barcode.code128();
  }
}
