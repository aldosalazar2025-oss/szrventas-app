import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  final String titulo;
  const ScannerScreen({super.key, this.titulo = 'Escanear'});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _scanned = false;
  late AnimationController _animCtrl;
  late Animation<double> _lineAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _lineAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      _scanned = true;
      Navigator.pop(context, barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.titulo),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, state, _) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
                color: state.torchState == TorchState.on
                    ? AppTheme.warning
                    : Colors.white,
              ),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Cámara
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Overlay con recorte
          CustomPaint(painter: _ScanOverlayPainter(), size: Size.infinite),

          // Línea de escaneo animada
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              height: MediaQuery.of(context).size.width * 0.7,
              child: AnimatedBuilder(
                listenable: _lineAnim,
                builder: (_, w) =>
                    CustomPaint(painter: _ScanLinePainter(_lineAnim.value)),
              ),
            ),
          ),

          // Controles inferiores
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Apunta al código de barras',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _mostrarInputManual(),
                      icon: const Icon(Icons.keyboard, color: AppTheme.accent),
                      label: const Text(
                        'Ingresar manualmente',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarInputManual() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código Manual'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ingresa el código de barras',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.pop(context, ctrl.text.trim());
              }
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _animCtrl.dispose();
    super.dispose();
  }
}

// Animated builder helper
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) => builder(context, null);
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.width * 0.7,
    );
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      bgPath,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // Esquinas
    final cornerPaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const cLen = 30.0;
    final r = scanArea;
    // Top-left
    canvas.drawLine(
      Offset(r.left, r.top + 16),
      Offset(r.left, r.top + cLen + 16),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.left, r.top + 16),
      Offset(r.left + cLen, r.top + 16),
      cornerPaint,
    );
    // Top-right
    canvas.drawLine(
      Offset(r.right, r.top + 16),
      Offset(r.right, r.top + cLen + 16),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.right, r.top + 16),
      Offset(r.right - cLen, r.top + 16),
      cornerPaint,
    );
    // Bottom-left
    canvas.drawLine(
      Offset(r.left, r.bottom - 16),
      Offset(r.left, r.bottom - cLen - 16),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.left, r.bottom - 16),
      Offset(r.left + cLen, r.bottom - 16),
      cornerPaint,
    );
    // Bottom-right
    canvas.drawLine(
      Offset(r.right, r.bottom - 16),
      Offset(r.right, r.bottom - cLen - 16),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.right, r.bottom - 16),
      Offset(r.right - cLen, r.bottom - 16),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  _ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.primary.withValues(alpha: 0),
          AppTheme.primary,
          AppTheme.primary.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, y, size.width, 2));
    canvas.drawRect(Rect.fromLTWH(16, y, size.width - 32, 2), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter old) =>
      old.progress != progress;
}
