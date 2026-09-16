import 'package:document_processing/document_processing.dart';

DocumentRect normalizeMlKitRect({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required int imageWidth,
  required int imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw const FormatException('image dimensions must be positive');
  }
  final normalizedLeft = (left / imageWidth).clamp(0.0, 1.0).toDouble();
  final normalizedTop = (top / imageHeight).clamp(0.0, 1.0).toDouble();
  final normalizedRight =
      (right / imageWidth).clamp(normalizedLeft, 1.0).toDouble();
  final normalizedBottom =
      (bottom / imageHeight).clamp(normalizedTop, 1.0).toDouble();
  return DocumentRect(
    left: normalizedLeft,
    top: normalizedTop,
    width: normalizedRight - normalizedLeft,
    height: normalizedBottom - normalizedTop,
  );
}
