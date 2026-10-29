import 'dart:typed_data';

import 'package:image/image.dart' as img;

const memberPhotoMaxBytes = 153600;

Uint8List compressMemberPhoto(Uint8List bytes) {
  if (bytes.length > 12 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 12 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null ||
      ![
        img.ImageFormat.jpg,
        img.ImageFormat.png,
        img.ImageFormat.webp,
      ].contains(decoder.format)) {
    throw const FormatException('Choose a JPEG, PNG or WebP photo.');
  }
  final info = decoder.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) {
    throw const FormatException('Choose a photo smaller than 24 megapixels.');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('Unable to read this photo.');
  }
  var picture = img.bakeOrientation(decoded);
  if (picture.width > 512 || picture.height > 512) {
    picture = img.copyResize(
      picture,
      width: picture.width >= picture.height ? 512 : null,
      height: picture.height > picture.width ? 512 : null,
      interpolation: img.Interpolation.average,
    );
  }
  final clean = img.Image(
    width: picture.width,
    height: picture.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, picture);
  for (final quality in [82, 70, 55, 40]) {
    final result = img.encodeJpg(clean, quality: quality);
    if (result.length <= memberPhotoMaxBytes) return result;
  }
  throw const FormatException(
    'Unable to optimize this photo. Choose another image.',
  );
}
