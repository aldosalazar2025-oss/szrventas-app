import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/producto.dart';
import 'barcode_generator.dart';

/// Una etiqueta lista para imprimir: puede ser el código principal de un
/// producto, o el código propio de una de sus variantes (talla/color).
class _Etiqueta {
  final String titulo;
  final String subtitulo;
  final String codigo;
  final bool esVariante;

  const _Etiqueta({
    required this.titulo,
    required this.subtitulo,
    required this.codigo,
    required this.esVariante,
  });
}

/// Arma un PDF con las etiquetas de código de barras de una lista de
/// productos: título, nombre y categoría (o talla/color si es una variante)
/// arriba de cada código, en 2 columnas, ordenadas alfabéticamente y
/// llenando cada hoja antes de pasar a la siguiente.
class BarcodePdfExporter {
  BarcodePdfExporter._();

  static const _columnas = 2;
  static const _margen = 28.0;
  static const _espacio = 20.0;

  /// Código "principal" a imprimir para un producto: si tiene varios
  /// códigos vinculados (separados por coma), usa el primero.
  static String codigoPrincipal(Producto p) =>
      p.codigoBarras.split(',').first.trim();

  /// Arma la lista de etiquetas a imprimir: el código principal de cada
  /// producto (si tiene) más el código propio de cada variante (talla/
  /// color) que lo tenga, y las ordena alfabéticamente por nombre.
  static List<_Etiqueta> _construirEtiquetas(List<Producto> productos) {
    final etiquetas = <_Etiqueta>[];
    for (final p in productos) {
      final principal = codigoPrincipal(p);
      if (principal.isNotEmpty) {
        etiquetas.add(_Etiqueta(
          titulo: p.nombre,
          subtitulo: p.categoria?.trim().isNotEmpty == true ? p.categoria!.trim() : 'Producto',
          codigo: principal,
          esVariante: false,
        ));
      }
      for (final v in p.variantes) {
        final codigoVariante = v.codigoBarras?.trim() ?? '';
        if (codigoVariante.isNotEmpty) {
          etiquetas.add(_Etiqueta(
            titulo: p.nombre,
            subtitulo: v.etiqueta,
            codigo: codigoVariante,
            esVariante: true,
          ));
        }
      }
    }

    etiquetas.sort((a, b) {
      final porNombre = a.titulo.trim().toLowerCase().compareTo(b.titulo.trim().toLowerCase());
      if (porNombre != 0) return porNombre;
      if (a.esVariante != b.esVariante) return a.esVariante ? 1 : -1;
      return a.subtitulo.toLowerCase().compareTo(b.subtitulo.toLowerCase());
    });
    return etiquetas;
  }

  static Future<pw.Document> generar(List<Producto> productos) async {
    final doc = pw.Document();
    final etiquetas = _construirEtiquetas(productos);

    final anchoItem = (PdfPageFormat.a4.width - _margen * 2 - _espacio) / _columnas;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_margen),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Códigos de barras',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Divider(thickness: 1.2, color: PdfColors.black),
                  pw.SizedBox(height: 8),
                ],
              )
            : pw.SizedBox(),
        build: (context) => [
          pw.Wrap(
            spacing: _espacio,
            runSpacing: 22,
            children: etiquetas
                .map(
                  (e) => pw.Container(
                    width: anchoItem,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          e.titulo,
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          e.subtitulo,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 6),
                        pw.BarcodeWidget(
                          barcode: BarcodeGenerator.tipoParaCodigo(e.codigo),
                          data: e.codigo,
                          drawText: true,
                          width: anchoItem,
                          height: 70,
                          textStyle: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );

    return doc;
  }
}
