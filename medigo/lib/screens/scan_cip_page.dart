import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:medigo/services/cip_parser.dart';

class ScanCipPage extends StatefulWidget {
  const ScanCipPage({super.key});

  @override
  State<ScanCipPage> createState() => _ScanCipPageState();
}

class _ScanCipPageState extends State<ScanCipPage> {
  bool _handling = false;
  bool _torchOn = false;
  bool _squareWindow = true; // default to square for tiny QR/DataMatrix
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
      // Reduce duplicate callbacks but keep responsiveness
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: 250,
      // Restrict formats to speed up decoding and focus on pharma labels
      formats: const [
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.ean13,
      ],
      autoStart: true,
      // returnImage off for performance
      returnImage: false,
    );
  }

  @override
  void dispose() {
    try {
      _controller.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handling) return;
    try {
      for (final b in capture.barcodes) {
        final raw = (b.rawValue ?? '').trim();
        if (raw.isEmpty) continue;
        final parsed = CipParser.parse(raw);
        if (parsed.cip13 != null || parsed.cip7 != null) {
          _handling = true;
          debugPrint('mobile_scanner: ${parsed.raw} -> cip13=${parsed.cip13} cip7=${parsed.cip7}');
          if (mounted) Navigator.of(context).pop(parsed);
          return;
        }
        // Some symbologies expose numeric-only in displayValue
        final alt = (b.displayValue ?? '').trim();
        if (alt.isNotEmpty && !_handling) {
          final parsed2 = CipParser.parse(alt);
          if (parsed2.cip13 != null || parsed2.cip7 != null) {
            _handling = true;
            debugPrint('mobile_scanner(display): ${parsed2.raw} -> cip13=${parsed2.cip13} cip7=${parsed2.cip7}');
            if (mounted) Navigator.of(context).pop(parsed2);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Scan handle error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner le code'),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Éteindre la lampe' : 'Allumer la lampe',
            onPressed: () async {
              try {
                await _controller.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              } catch (e) {
                debugPrint('Torch toggle error: $e');
              }
            },
            icon: Icon(_torchOn ? Icons.flashlight_off : Icons.flashlight_on, color: cs.primary),
          ),
          IconButton(
            tooltip: _squareWindow ? 'Fenêtre 1D (EAN-13)' : 'Fenêtre carrée (QR/DataMatrix)',
            onPressed: () {
              setState(() {
                _squareWindow = !_squareWindow;
              });
            },
            icon: Icon(_squareWindow ? Icons.qr_code_2 : Icons.view_week, color: Colors.blue),
          ),
          IconButton(
            tooltip: 'Basculer la caméra',
            onPressed: () async {
              try {
                await _controller.switchCamera();
              } catch (e) {
                debugPrint('Switch camera error: $e');
              }
            },
            icon: const Icon(Icons.cameraswitch, color: Colors.blue),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // Small, centered scan window to boost pixel density on tiny codes.
          final square = math.min(width, height) * 0.46; // ~46% of the shortest side
          final oneDHeight = math.max(72.0, width * 0.16); // slim band for EAN-13
          final winWidth = _squareWindow ? square : width * 0.70;
          final winHeight = _squareWindow ? square : oneDHeight;
          final left = (width - winWidth) / 2;
          final top = (height - winHeight) / 2;

          final scanWindow = Rect.fromLTWH(left, top, winWidth, winHeight);

          return Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _handleCapture,
            scanWindow: scanWindow,
          ),
          // Simple overlay with a square frame
          IgnorePointer(
            child: Center(
              child: Container(
                width: winWidth,
                height: winHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.8), width: 3),
                ),
              ),
            ),
          ),
          // Instructions specific to small codes
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              color: cs.surface,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Alignez le petit QR/DataMatrix dans le cadre. Reculez légèrement (~20–30 cm) pour la mise au point et éclairez bien. Formats: EAN‑13, DataMatrix, QR (GS1).',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        ],
      );
        },
      ),
    );
  }
}
