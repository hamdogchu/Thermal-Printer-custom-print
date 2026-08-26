import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'logger.dart';

class PrinterDevice {
  final String name;
  final int vendorId;
  final int productId;

  PrinterDevice({required this.name, required this.vendorId, required this.productId});
}

class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();

  final FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();
  
  // List of discovered USB printers
  List<PrinterDevice> devices = [];
  PrinterDevice? selectedPrinter;

  Future<void> scanPrinters(Function(List<PrinterDevice>) onDevicesUpdated) async {
    devices.clear();
    onDevicesUpdated(devices);
    
    try {
      List<Map<String, dynamic>> results = await FlutterUsbPrinter.getUSBDeviceList();
      for (var device in results) {
        String name = device['productName'] ?? device['manufacturer'] ?? 'Unknown USB Printer';
        int vendorId = int.tryParse(device['vendorId'].toString()) ?? 0;
        int productId = int.tryParse(device['productId'].toString()) ?? 0;
        
        devices.add(PrinterDevice(name: name, vendorId: vendorId, productId: productId));
      }
      onDevicesUpdated(List.from(devices));
    } catch (e, stackTrace) {
      AppLogger().logError("Error scanning USB devices", e, stackTrace);
    }
  }

  void stopScan() {
    // flutter_usb_printer does not use a continuous stream for scanning, 
    // so no action is required to stop it.
  }

  Future<bool> connectDevice(PrinterDevice device) async {
    AppLogger().log("Attempting to connect to device: ${device.name}");
    selectedPrinter = device;
    try {
      bool? connected = await flutterUsbPrinter.connect(device.vendorId, device.productId);
      AppLogger().log("Connection attempt returned: $connected");
      return connected ?? false;
    } catch (e, stacktrace) {
      AppLogger().logError("Exception while connecting", e, stacktrace);
      return false;
    }
  }

  Future<bool> disconnectDevice() async {
    if (selectedPrinter != null) {
      try {
        await flutterUsbPrinter.close();
        selectedPrinter = null;
        return true;
      } catch (e) {
        AppLogger().logError("Error disconnecting", e);
        return false;
      }
    }
    return true;
  }

  Future<bool> printImageBytes(ByteData imageData) async {
    if (selectedPrinter == null) return false;

    try {
      final profile = await CapabilityProfile.load();
      // T80A is an 80mm printer
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Decode the image using the image package
      final Uint8List list = imageData.buffer.asUint8List();
      final img.Image? decodedImage = img.decodeImage(list);
      
      if (decodedImage == null) return false;

      // Resize the image to fit 80mm printer width (576 dots max for 80mm)
      // We'll scale down to 576 if it's wider, keeping aspect ratio.
      img.Image resizedImage = decodedImage;
      if (decodedImage.width > 576) {
        resizedImage = img.copyResize(decodedImage, width: 576);
      }

      // Apply Floyd-Steinberg dithering for grayscale illusion
      img.Image dithered = img.copyCrop(resizedImage, x: 0, y: 0, width: resizedImage.width, height: resizedImage.height);
      img.grayscale(dithered);

      for (int y = 0; y < dithered.height; y++) {
        for (int x = 0; x < dithered.width; x++) {
          final pixel = dithered.getPixel(x, y);
          num oldPixel = pixel.r;
          num newPixel = oldPixel < 128 ? 0 : 255;
          
          pixel.r = newPixel;
          pixel.g = newPixel;
          pixel.b = newPixel;

          num quantError = oldPixel - newPixel;

          if (x + 1 < dithered.width) {
            final p = dithered.getPixel(x + 1, y);
            p.r = (p.r + quantError * 7 / 16).clamp(0, 255);
            p.g = p.r;
            p.b = p.r;
          }
          if (x - 1 >= 0 && y + 1 < dithered.height) {
            final p = dithered.getPixel(x - 1, y + 1);
            p.r = (p.r + quantError * 3 / 16).clamp(0, 255);
            p.g = p.r;
            p.b = p.r;
          }
          if (y + 1 < dithered.height) {
            final p = dithered.getPixel(x, y + 1);
            p.r = (p.r + quantError * 5 / 16).clamp(0, 255);
            p.g = p.r;
            p.b = p.r;
          }
          if (x + 1 < dithered.width && y + 1 < dithered.height) {
            final p = dithered.getPixel(x + 1, y + 1);
            p.r = (p.r + quantError * 1 / 16).clamp(0, 255);
            p.g = p.r;
            p.b = p.r;
          }
        }
      }

      // Convert image to ESC/POS bytes (it handles dithering if we use the image command)
      bytes += generator.image(dithered);
      
      // Feed paper and cut
      bytes += generator.feed(2);
      bytes += generator.cut();

      // Send to printer
      AppLogger().log("Sending bytes to printer...");
      await flutterUsbPrinter.write(Uint8List.fromList(bytes));
      AppLogger().log("Print write successful.");
      return true;
    } catch (e, stacktrace) {
      AppLogger().logError("Exception during print Image", e, stacktrace);
      return false;
    }
  }
}
