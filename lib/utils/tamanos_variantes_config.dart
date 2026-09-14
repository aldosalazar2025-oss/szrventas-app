import 'package:shared_preferences/shared_preferences.dart';
import '../models/conjunto_opcion.dart';

/// Configuración de "Tamaños y variantes": si la función está activa,
/// y las listas de tamaños y conjuntos disponibles para armar
/// combinaciones en el formulario de productos (pensado para
/// restaurantes: tamaños de plato/pizza y conjuntos de cremas/extras).
class TamanosVariantesConfig {
  static const prefsKeyHabilitado = 'tamanos_variantes_habilitado';
  static const prefsKeyTamanos = 'tamanos_variantes_tamanos';
  static const prefsKeyConjuntos = 'tamanos_variantes_conjuntos';

  static const List<String> tamanosPorDefecto = [
    'Personal',
    'Mediana',
    'Familiar',
  ];

  static Future<bool> estaHabilitado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKeyHabilitado) ?? false;
  }

  static Future<void> guardarHabilitado(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKeyHabilitado, valor);
  }

  static Future<List<String>> obtenerTamanos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKeyTamanos) ??
        List.from(tamanosPorDefecto);
  }

  static Future<void> guardarTamanos(List<String> tamanos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKeyTamanos, tamanos);
  }

  static Future<List<ConjuntoOpcion>> obtenerConjuntos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(prefsKeyConjuntos);
    if (raw == null) return [];
    return raw.map(ConjuntoOpcion.fromStorage).toList();
  }

  static Future<void> guardarConjuntos(List<ConjuntoOpcion> conjuntos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      prefsKeyConjuntos,
      conjuntos.map((c) => c.toStorage()).toList(),
    );
  }
}
