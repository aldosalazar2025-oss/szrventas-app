/// Conversión y formato de peso: internamente siempre gramos enteros.
class PesoFormatter {
  static int kgToGrams(double kg) => (kg * 1000).round();

  static double gramsToKg(int grams) => grams / 1000.0;

  static String _trimKg(double kg) {
    if (kg == kg.roundToDouble()) return kg.toInt().toString();
    var s = kg.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// Stock o cantidad: `12.5 kg` o `300 g`.
  static String formatGrams(int grams) {
    if (grams >= 1000) return '${_trimKg(gramsToKg(grams))} kg';
    return '$grams g';
  }

  /// Carrito y resumen: siempre en kg (`0.300 kg`).
  static String formatKg(int grams) => '${_trimKg(gramsToKg(grams))} kg';

  /// Ticket térmico corto: `0.3kg` / `2kg`.
  static String formatTicket(int grams) => '${_trimKg(gramsToKg(grams))}kg';

  static double subtotal({required int gramos, required double precioPorKg}) {
    return (gramos / 1000.0 * precioPorKg * 100).round() / 100.0;
  }

  static int parseToGrams(String input, {required bool enKg}) {
    final v = double.tryParse(input.replaceAll(',', '.').trim());
    if (v == null || v < 0) return 0;
    return enKg ? kgToGrams(v) : v.round();
  }

  static String kgInputFromGrams(int grams) => _trimKg(gramsToKg(grams));
}
