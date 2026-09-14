import 'package:shared_preferences/shared_preferences.dart';
import 'printer_service.dart';

class OnboardingService {
  static const _keyCompletado = 'onboarding_completado';
  static const keyNombre = 'negocio_nombre';
  static const keyDireccion = 'negocio_direccion';
  static const keyTelefono = 'negocio_telefono';

  static Future<bool> needsSetup() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyCompletado) == true) return false;

    final nombre = prefs.getString(keyNombre)?.trim() ?? '';
    final direccion = prefs.getString(keyDireccion)?.trim() ?? '';
    final telefono = prefs.getString(keyTelefono)?.trim() ?? '';

    return nombre.isEmpty || direccion.isEmpty || telefono.isEmpty;
  }

  static Future<void> completeSetup({
    required String nombre,
    required String direccion,
    required String telefono,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNombre, nombre.trim());
    await prefs.setString(keyDireccion, direccion.trim());
    await prefs.setString(keyTelefono, telefono.trim());
    await prefs.setBool(_keyCompletado, true);

    PrinterService.instance.configurar(
      nombre: nombre.trim(),
      direccion: direccion.trim(),
      telefono: telefono.trim(),
    );
  }
}
