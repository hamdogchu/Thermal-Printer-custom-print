import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  img.Image image = img.Image(width: 10, height: 10);
  final pixel = image.getPixel(0, 0);
  pixel.r = 120.0; // test assignment
  print('Pixel class: ${pixel.runtimeType}');
  print('pixel.r = ${pixel.r}');
}
