import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../utils/distance_utils.dart';

/// Draws bounding boxes and labels for each detection on the camera preview.
///
/// [imageWidth] / [imageHeight] are the dimensions returned by the backend.
/// The painter uses **fitted scaling** (uniform scale + offset) so that
/// bounding boxes stay accurate even when the preview widget has a different
/// aspect ratio than the captured image.
class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;

  DetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == 0 || imageHeight == 0) return;

    // ── Fitted scaling ──
    // We want to map backend image coords → preview widget coords.
    // The camera preview typically fills the widget using BoxFit.cover,
    // but the Stack's CustomPaint has the same size as the preview widget.
    //
    // Use a uniform scale (the LARGER of scaleX/scaleY when the preview
    // covers the widget, or the SMALLER when it's contained).
    //
    // For CameraPreview which fills the widget (similar to BoxFit.cover):
    //   scale = max(widgetW/imgW, widgetH/imgH)
    //   offsetX = (widgetW - imgW*scale) / 2
    //   offsetY = (widgetH - imgH*scale) / 2
    //
    // If the aspect ratios happen to match, offset is 0 and this is
    // identical to the old simple scaleX/scaleY approach.

    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;
    final double scale = math.max(scaleX, scaleY); // cover
    final double offsetX = (size.width - imageWidth * scale) / 2;
    final double offsetY = (size.height - imageHeight * scale) / 2;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final bgPaint = Paint()..style = PaintingStyle.fill;

    for (final det in detections) {
      final color = _colorForClass(det.classId);
      boxPaint.color = color;
      bgPaint.color = color.withOpacity(0.75);

      // Map bbox from image coords → widget coords
      final rect = Rect.fromLTRB(
        det.xMin * scale + offsetX,
        det.yMin * scale + offsetY,
        det.xMax * scale + offsetX,
        det.yMax * scale + offsetY,
      );

      // Clamp to visible area so labels don't paint offscreen
      final clampedRect = Rect.fromLTRB(
        rect.left.clamp(0, size.width),
        rect.top.clamp(0, size.height),
        rect.right.clamp(0, size.width),
        rect.bottom.clamp(0, size.height),
      );

      // Draw bounding box
      canvas.drawRect(clampedRect, boxPaint);

      // Build label lines: object name, distance (if available), confidence.
      final confidenceText =
          'confidence ${(det.confidence * 100).toStringAsFixed(0)}%';
      final distanceText = DistanceUtils.buildDisplayDistanceLabel(det);
      final label = distanceText == null
          ? '${det.label}\n$confidenceText'
          : '${det.label}\n$distanceText\n$confidenceText';

      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: math.min(220, size.width * 0.55));

      // Position label above top-left of box; if it would go off-screen,
      // push it down inside the box instead.
      double labelY = clampedRect.top - textPainter.height - 4;
      if (labelY < 0) labelY = clampedRect.top + 2;

      final labelWidth = textPainter.width + 10;
      final labelHeight = textPainter.height + 6;
        final labelX = clampedRect.left
          .clamp(0.0, math.max(0.0, size.width - labelWidth))
          .toDouble();

      final labelRect = Rect.fromLTWH(
        labelX,
        labelY,
        labelWidth,
        labelHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        bgPaint,
      );

      textPainter.paint(canvas, Offset(labelX + 5, labelY + 3));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }

  /// Returns a consistent colour per COCO class-id.
  static Color _colorForClass(int classId) {
    const palette = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
      Colors.lime,
      Colors.deepOrange,
    ];
    return palette[classId % palette.length];
  }
}
