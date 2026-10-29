import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gym_saas/features/members/photo_compression.dart';

void main() {
  test('Large profile photo becomes bounded JPEG without metadata', () {
    final original = img.Image(width: 1600, height: 900);
    img.fill(original, color: img.ColorRgb8(80, 120, 200));
    final bytes = compressMemberPhoto(img.encodePng(original));
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, 512);
    expect(decoded.height, 288);
    expect(bytes.length, lessThanOrEqualTo(memberPhotoMaxBytes));
  });
  test('Small transparent photo stays small and becomes white JPEG', () {
    final original = img.Image(width: 50, height: 80, numChannels: 4);
    final decoded = img.decodeJpg(
      compressMemberPhoto(img.encodePng(original)),
    )!;
    expect(decoded.width, 50);
    expect(decoded.height, 80);
    expect(decoded.getPixel(0, 0).r, greaterThan(245));
  });
  test('Rejects invalid and oversized files', () {
    expect(
      () => compressMemberPhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => compressMemberPhoto(Uint8List(12 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
