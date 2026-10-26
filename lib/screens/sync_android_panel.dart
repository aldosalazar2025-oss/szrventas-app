import 'dart:async';
import 'package:flutter/material.dart';
import '../sync/cliente_sync.dart';
import '../sync/orquestador.dart';
import '../sync/protocolo.dart';
import '../sync/servicio_android.dart';
import '../theme/app_theme.dart';

/// Sección "Sincronización" de Ajustes (Android): conecta con la PC por Wi-Fi local.
class SincronizacionAndroidPanel extends StatefulWidget {
  const SincronizacionAndroidPanel({super.key});

  @override
  State<SincronizacionAndroidPanel> createState() => _SincronizacionAndroidPanelState();
}

class _SincronizacionAndroidPanelState extends State<SincronizacionAndroidPanel> {
  final _srv = ServicioSyncAndroid.instance;
  final _ipCtrl = TextEditingController();
  final _puertoCtrl = TextEditingController(text: '$puertoPredeterminado');
  final _codigoCtrl = TextEditingController();

  bool _ocupado = false;
  bool _conectada = false;
  String _ultima = 'nunca';
  String? _error;
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
    _srv.cambios.addListener(_cargar);
  }

  @override
  void dispose() {
    _srv.cambios.removeListener(_cargar);
    _ipCtrl.dispose();
    _puertoCtrl.dispose();
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final s = await _srv.servicio();
    final st = await _srv.store();
    final cfg = await s.cargarConfig();
    final ultima = await s.config.leer(ServicioSync.kUltima);
    final error = await s.config.leer(ServicioSync.kError);
    final pendientes = await st.contarPendientes();
    if (!mounted) return;
    setState(() {
      if (cfg != null && _ipCtrl.text.isEmpty) {
        _ipCtrl.text = cfg.host;
        _puertoCtrl.text = '${cfg.puerto}';
      }
      _conectada = cfg != null;
      _ultima = _formato(ultima);
      _error = error;
      _pendientes = pendientes;
    });
  }

  static String _formato(String? iso) {
    final f = DateTime.tryParse(iso ?? '');
    if (f == null) return 'nunca';
    String d(int n) => n.toString().padLeft(2, '0');
    return '${d(f.day)}/${d(f.month)}/${f.year} ${d(f.hour)}:${d(f.minute)}';
  }

  void _aviso(String texto, {Color color = AppTheme.success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: color,
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
    } on ErrorSync catch (e) {
      _aviso(e.mensaje, color: AppTheme.error);
    } catch (e) {
      _aviso('Error inesperado: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _ocupado = false);
      await _cargar();
    }
  }

  Future<void> _conectar() => _ejecutar(() async {
        final host = _ipCtrl.text.trim();
        final puerto = int.tryParse(_puertoCtrl.text.trim()) ?? puertoPredeterminado;
        final codigo = _codigoCtrl.text.trim();
        if (host.isEmpty || codigo.length < 4) {
          throw ErrorSync('Escribe la dirección IP de la PC y el código que muestra el panel');
        }
        final s = await _srv.servicio();
        await s.conectar(
          host: host,
          puerto: puerto,
          codigo: codigo,
          nombreDispositivo: 'Celular Android',
        );
        _codigoCtrl.clear();
        s.iniciarAutoSync(alCambiar: (_) => _srv.cambios.value++);
        _aviso('✓ Conectado con la PC y autorizado');
      });

  Future<void> _actualizar() => _ejecutar(() async {
        final s = await _srv.servicio();
        final r = await s.actualizarProductos();
        _srv.cambios.value++;
        _aviso('Productos: ${r.creados} nuevos, ${r.actualizados} actualizados, '
            '${r.retirados} retirados, ${r.imagenes} fotos'
            '${r.imagenesFallidas > 0 ? ' (${r.imagenesFallidas} fotos fallaron)' : ''}');
      });

  Future<void> _enviar() => _ejecutar(() async {
        final s = await _srv.servicio();
        final r = await s.enviarVentas();
        await _resumenEnvio(r);
      });

  Future<void> _todo() => _ejecutar(() async {
        final s = await _srv.servicio();
        final r = await s.sincronizarTodo();
        _srv.cambios.value++;
        await _resumenEnvio(r.ventas, catalogo: r.catalogo);
      });

  Future<void> _resumenEnvio(ResultadoEnvio v, {ResultadoCatalogo? catalogo}) async {
    final lineas = <String>[
      'Ventas enviadas: ${v.enviadas}',
      if (v.duplicadas > 0) 'Ya estaban en la PC: ${v.duplicadas}',
      if (v.conConflicto > 0) 'Con aviso de inventario: ${v.conConflicto}',
      if (v.conError > 0) 'Con error (siguen pendientes): ${v.conError}',
      'Pendientes ahora: ${v.pendientes}',
      if (catalogo != null)
        'Productos: ${catalogo.creados} nuevos, ${catalogo.actualizados} actualizados, '
            '${catalogo.retirados} retirados',
    ];
    if (v.mensajes.isEmpty) {
      _aviso(lineas.join('\n'),
          color: v.conError > 0 ? AppTheme.warning : AppTheme.success);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resultado'),
        content: SingleChildScrollView(
          child: Text('${lineas.join('\n')}\n\nDetalle:\n${v.mensajes.map((m) => '• $m').join('\n')}'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aceptar')),
        ],
      ),
    );
  }

  Future<void> _verPendientes() => _ejecutar(() async {
        final st = await _srv.store();
        final lista = await st.listarPendientes();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Ventas pendientes (${lista.length})'),
            content: SizedBox(
              width: double.maxFinite,
              child: lista.isEmpty
                  ? const Text('No hay ventas pendientes de envío.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final v in lista)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${_formato('${v['fecha']}')} · '
                              '${((v['total'] as num?) ?? 0).toStringAsFixed(2)}',
                            ),
                            subtitle: Text(
                              v['sync_estado'] == 'error'
                                  ? 'Error (${v['sync_intentos']} intentos): ${v['sync_error']}'
                                  : 'Pendiente de envío',
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            ],
          ),
        );
      });

  Future<void> _verEstado() => _ejecutar(() async {
        final s = await _srv.servicio();
        final cfg = await s.cargarConfig();
        String pc;
        if (cfg == null) {
          pc = 'Sin emparejar. Usa "Conectar con la PC".';
        } else {
          try {
            await ClienteSync(cfg).getJson('/api/estado');
            pc = 'PC conectada ✓ (${cfg.host}:${cfg.puerto})';
          } on ErrorSync catch (e) {
            pc = 'PC no disponible (${cfg.host}:${cfg.puerto})\n${e.mensaje}';
          }
        }
        final st = await _srv.store();
        final pendientes = await st.contarPendientes();
        final error = await s.config.leer(ServicioSync.kError);
        final ultima = await s.config.leer(ServicioSync.kUltima);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Estado de conexión'),
            content: Text(
              '$pc\n\nÚltima sincronización: ${_formato(ultima)}\n'
              'Ventas pendientes: $pendientes'
              '${error != null ? '\n\nÚltimo error:\n$error' : ''}',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            ],
          ),
        );
      });

  Future<void> _desconectar() => _ejecutar(() async {
        final s = await _srv.servicio();
        await s.desconectar();
        _aviso('Se desvinculó de la PC. Tus ventas y productos no se borraron.');
      });

  Widget _caja(List<Widget> hijos) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
        ),
      );

  Widget _boton(IconData icono, String texto, VoidCallback? accion, {bool relleno = true}) {
    final hijo = Text(texto);
    final icon = Icon(icono, size: 20);
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: relleno
          ? FilledButton.icon(onPressed: _ocupado ? null : accion, icon: icon, label: hijo)
          : OutlinedButton.icon(onPressed: _ocupado ? null : accion, icon: icon, label: hijo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _caja([
          Row(
            children: [
              Icon(_conectada ? Icons.link : Icons.link_off,
                  color: _conectada ? AppTheme.success : AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _conectada ? 'Emparejado con la PC' : 'Sin conectar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_ocupado)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Última sincronización: $_ultima · Pendientes: $_pendientes',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Último error: $_error',
                  style: const TextStyle(fontSize: 12, color: AppTheme.error)),
            ),
        ]),
        _caja([
          const Text('Conectar con la PC', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'En la PC abre Ajustes → Sincronización → Iniciar conexión y escribe aquí '
            'la dirección y el código que muestra. Deben estar en la misma red Wi-Fi.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'IP de la PC', hintText: '192.168.1.10'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _puertoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Puerto'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codigoCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Código de emparejamiento'),
          ),
          const SizedBox(height: 12),
          _boton(Icons.wifi, 'Conectar con la PC', _conectar),
        ]),
        _caja([
          _boton(Icons.sync, 'Sincronizar todo', _todo),
          const SizedBox(height: 8),
          _boton(Icons.download, 'Actualizar productos', _actualizar),
          const SizedBox(height: 8),
          _boton(Icons.upload, 'Enviar ventas a la PC', _enviar),
          const SizedBox(height: 8),
          _boton(Icons.pending_actions, 'Ver ventas pendientes', _verPendientes, relleno: false),
          const SizedBox(height: 8),
          _boton(Icons.network_check, 'Ver estado de conexión', _verEstado, relleno: false),
          if (_conectada) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _ocupado ? null : _desconectar, child: const Text('Desvincular de la PC')),
          ],
        ]),
      ],
    );
  }
}
