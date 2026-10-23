import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:async';

/// Utility to apply predefined photo filters to images.
/// Returns PNG bytes for consistency (preserves transparency if present).
class PhotoFilterService {
  PhotoFilterService._();

  /// Applies a "Brannan"-style filter.
  /// Updated: cooler, brighter tone for drug photos (reduced warmth, lifted exposure).
  static Future<Uint8List> applyBrannan(Uint8List input) async {
    debugPrint('PhotoFilterService.applyBrannan: start (web=$kIsWeb, bytes=${input.length})');
    ui.Codec? codec;
    ui.Image? src;
    ui.Picture? picture;
    ui.Image? rendered;
    try {
      final res = await (() async {
        codec = await ui.instantiateImageCodec(input);
        final frame = await codec!.getNextFrame();
        src = frame.image;

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final paint = ui.Paint()
          ..isAntiAlias = true
          ..filterQuality = ui.FilterQuality.high
          ..colorFilter = ui.ColorFilter.matrix(_brannanMatrix());

        final rect = ui.Rect.fromLTWH(0, 0, src!.width.toDouble(), src!.height.toDouble());
        canvas.drawImageRect(src!, rect, rect, paint);
        picture = recorder.endRecording();
        rendered = await picture!.toImage(src!.width, src!.height);
        final data = await rendered!.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw Exception('PNG encoding returned null');
        return data.buffer.asUint8List();
      })().timeout(Duration(seconds: kIsWeb ? 8 : 20), onTimeout: () {
        throw TimeoutException('PhotoFilterService.applyBrannan timed out');
      });
      debugPrint('PhotoFilterService.applyBrannan: done, outBytes=${res.length}');
      return res;
    } catch (e, st) {
      debugPrint('PhotoFilterService.applyBrannan failed: $e\n$st');
      return input;
    } finally {
      try { codec?.dispose(); } catch (_) {}
      try { src?.dispose(); } catch (_) {}
      try { rendered?.dispose(); } catch (_) {}
      try { picture?.dispose(); } catch (_) {}
    }
  }

  /// Color matrix tuned for a cooler + brighter look (less warm than before).
  /// Red bias reduced, blue slightly boosted, small positive lift on all channels.
  static List<double> _brannanMatrix() {
    // Cooling: decrease red scale slightly, increase blue scale.
    // Brightness: add a small positive offset to RGB rows equally.
    const rScale = 0.98;
    const gScale = 1.02;
    const bScale = 1.10;

    // Reduce cross-channel warmth contributions into red; add subtle cool mix into green/blue.
    const crossRG = -0.02; // remove green from red a bit
    const crossRB = -0.02; // remove blue from red a bit (keeps reds controlled)
    const crossGR = 0.00;  // keep green neutral wrt red
    const crossGB = 0.01;  // slight blue into green for cooler mids
    const crossBR = -0.01; // less red into blue
    const crossBG = 0.02;  // a touch of green into blue to avoid magenta shift

    // Positive lift across channels to increase brightness/exposure.
    const lift = 0.04; // ~10/255

    return <double>[
      // R row
      rScale, crossRG, crossRB, 0, lift,
      // G row
      crossGR, gScale, crossGB, 0, lift,
      // B row
      crossBR, crossBG, bScale, 0, lift,
      // A row
      0, 0, 0, 1, 0,
    ];
  }
}
