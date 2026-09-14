import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/producto.dart';
import 'producto_form_screen.dart';
import '../utils/safe_area_padding.dart';
import '../utils/currency_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scanner_screen.dart';

class InventarioScreen extends StatefulWidget {
  final String? codigoInicial;
  const InventarioScreen({super.key, this.codigoInicial});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _db = DatabaseService.instance;
  final _searchCtrl = TextEditingController();
  List<Producto> _productos = [];
  List<Producto> _filtrados = [];
  bool _loading = true;
  String _filtroCategoria = 'Todos';
  List<String> _categorias = ['Todos'];
  String _monedaSimbolo = 'S/';

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
    _cargar();
    if (widget.codigoInicial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProductoFormScreen(codigoBarras: widget.codigoInicial),
          ),
        ).then((_) => _cargar());
      });
    }
  }

  Future<void> _cargarAjustes() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _monedaSimbolo = prefs.getString('moneda_simbolo') ?? 'S/';
      });
    }
  }

  String _formatMoney(double amount) {
    return CurrencyFormatter.format(amount, _monedaSimbolo);
  }

  Future<void> _cargar() async {
    final productos = await _db.obtenerProductos();
    final cats = await _db.obtenerCategorias();
    if (mounted) {
      setState(() {
        _productos = productos;
        _filtrados = productos;
        _categorias = ['Todos', ...cats];
        _loading = false;
      });
    }
  }

  void _filtrar(String query) {
    setState(() {
      _filtrados = _productos.where((p) {
        final matchQ =
            query.isEmpty ||
            p.nombre.toLowerCase().contains(query.toLowerCase()) ||
            p.codigoBarras.contains(query);
        final matchC =
            _filtroCategoria == 'Todos' || p.categoria == _filtroCategoria;
        return matchQ && matchC;
      }).toList();
    });
  }

  Future<void> _escanearAgregar() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(titulo: 'Escanear Producto'),
      ),
    );
    if (codigo == null || !mounted) return;
    final existe = await _db.buscarPorCodigoBarras(codigo);
    if (existe != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${existe.nombre} ya existe en inventario')),
      );
      return;
    }
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductoFormScreen(codigoBarras: codigo),
        ),
      );
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _escanearAgregar,
            tooltip: 'Escanear código',
          ),
        ],
      ),
      body: Column(
        children: [
          // Búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filtrar,
              decoration: InputDecoration(
                hintText: 'Buscar producto o código...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.textSecondary,
                ),
                filled: true,
                fillColor: AppTheme.bgWhite,
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filtrar('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Categorías
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categorias.length,
              itemBuilder: (_, i) {
                final cat = _categorias[i];
                final sel = cat == _filtroCategoria;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        color: sel ? Colors.white : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    selected: sel,
                    onSelected: (_) {
                      setState(() => _filtroCategoria = cat);
                      _filtrar(_searchCtrl.text);
                    },
                    backgroundColor: AppTheme.bgWhite,
                    selectedColor: AppTheme.primary,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: sel ? AppTheme.primary : AppTheme.border,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtrados.length} productos',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Lista
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _filtrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: AppTheme.textHint,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No hay productos',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Toca + para agregar',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: listBottomPadding(context, bottomExtra: 80),
                    itemCount: _filtrados.length,
                    itemBuilder: (_, i) => _buildProductoCard(_filtrados[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductoFormScreen()),
          );
          _cargar();
        },
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _buildProductoCard(Producto p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.stockBajo
              ? AppTheme.error.withValues(alpha: 0.3)
              : AppTheme.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProductoFormScreen(producto: p)),
          );
          _cargar();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.agotado
                      ? AppTheme.error.withValues(alpha: 0.08)
                      : AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  image: p.imagenUrl != null
                      ? DecorationImage(
                          image: FileImage(File(p.imagenUrl!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: p.imagenUrl == null
                    ? Icon(
                        Icons.inventory_2_rounded,
                        color: p.agotado ? AppTheme.error : AppTheme.primary,
                        size: 22,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 12,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          p.codigoBarras,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        if (p.categoria != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.categoria!,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatMoney(p.precioVenta) + (p.esPeso ? '/kg' : ''),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.agotado
                          ? AppTheme.error.withValues(alpha: 0.08)
                          : p.stockBajo
                          ? AppTheme.warning.withValues(alpha: 0.08)
                          : AppTheme.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.formatoStock,
                      style: TextStyle(
                        color: p.agotado
                            ? AppTheme.error
                            : p.stockBajo
                            ? AppTheme.warning
                            : AppTheme.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
