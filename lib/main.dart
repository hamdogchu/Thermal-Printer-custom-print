import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image_picker/image_picker.dart';
import 'print_service.dart';
import 'logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger().init();
  
  FlutterError.onError = (details) {
    AppLogger().logError("Flutter Error: ${details.exception}", details.exception, details.stack);
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger().logError("Platform Error", error, stack);
    return true;
  };
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thermal Printer',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PrintService _printService = PrintService();
  final ImagePicker _picker = ImagePicker();
  
  List<PrinterDevice> _devices = [];
  bool _isScanning = false;
  double _brightness = 1.2;
  
  final List<String> _premadeImages = [
    'assets/images/cafe_logo.jpg',
    'assets/images/receipt_header.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _scanPrinters();
  }

  void _scanPrinters() {
    setState(() {
      _isScanning = true;
    });
    _printService.scanPrinters((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          _isScanning = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _printService.stopScan();
    super.dispose();
  }

  void _connectDevice(PrinterDevice device) async {
    AppLogger().log("UI: Connecting to ${device.name}");
    bool connected = await _printService.connectDevice(device);
    AppLogger().log("UI: Connection result: $connected");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(connected ? 'Connected to ${device.name}' : 'Failed to connect')),
      );
      if (connected) {
        setState(() {}); 
      }
    }
  }

  void _disconnectDevice() async {
    bool disconnected = await _printService.disconnectDevice();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disconnected ? 'Disconnected' : 'Failed to disconnect')),
      );
      if (disconnected) {
        setState(() {});
      }
    }
  }

  void _printImageData(ByteData data, {double brightness = 1.0}) async {
    if (_printService.selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }
    
    try {
      bool success = await _printService.printImageBytes(data, brightness: brightness);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'Printed successfully' : 'Failed to print')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing image: $e')),
        );
      }
    }
  }

  void _pickAndPrintImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final Uint8List bytes = await image.readAsBytes();
      final ByteData data = bytes.buffer.asByteData();
      _showCustomImagePrintPreview(bytes, data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermal Image Printer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Logs',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanPrinters,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndPrintImage,
        child: const Icon(Icons.add_photo_alternate),
        tooltip: 'Pick custom image',
      ),
      body: Column(
        children: [
          // Printer Selection Area
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.deepPurple.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Printers (USB)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    if (_isScanning) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 8),
                if (_printService.selectedPrinter != null)
                  ListTile(
                    leading: const Icon(Icons.print, color: Colors.green),
                    title: Text(_printService.selectedPrinter!.name),
                    subtitle: const Text('Connected'),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off, color: Colors.red),
                      onPressed: _disconnectDevice,
                    ),
                  )
                else if (_devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No printers found. Connect a USB OTG printer and refresh.'),
                  )
                else
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return ListTile(
                          leading: const Icon(Icons.usb),
                          title: Text(device.name),
                          subtitle: Text('VID: ${device.vendorId} PID: ${device.productId}'),
                          trailing: ElevatedButton(
                            onPressed: () => _connectDevice(device),
                            child: const Text('Connect'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Image Selection Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Premade Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  
                  // Brightness Slider
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.brightness_medium),
                      const SizedBox(width: 8),
                      const Text('Brightness:'),
                      Expanded(
                        child: Slider(
                          value: _brightness,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: _brightness.toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() {
                              _brightness = value;
                            });
                          },
                        ),
                      ),
                      Text('${(_brightness * 100).toInt()}%'),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _premadeImages.length,
                      itemBuilder: (context, index) {
                        final imagePath = _premadeImages[index];
                        return Card(
                          elevation: 4,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _showAssetPrintPreview(imagePath),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Image.asset(
                                    imagePath,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  color: Colors.deepPurple,
                                  width: double.infinity,
                                  child: const Icon(Icons.print, color: Colors.white),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showAssetPrintPreview(String imagePath) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Print Preview'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(imagePath, height: 200, fit: BoxFit.contain),
              const SizedBox(height: 16),
              const Text('Print this image to the connected thermal printer?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final ByteData data = await rootBundle.load(imagePath);
                _printImageData(data, brightness: _brightness);
              },
              child: const Text('Print'),
            ),
          ],
        );
      }
    );
  }

  void _showCustomImagePrintPreview(Uint8List imageBytes, ByteData data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Print Preview'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(imageBytes, height: 200, fit: BoxFit.contain),
              const SizedBox(height: 16),
              const Text('Print your custom image?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _printImageData(data, brightness: _brightness);
              },
              child: const Text('Print'),
            ),
          ],
        );
      }
    );
  }
}

class LogsScreen extends StatelessWidget {
  const LogsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all logs',
            onPressed: () {
              final logs = AppLogger().logsNotifier.value.join('\n');
              Clipboard.setData(ClipboardData(text: logs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear logs',
            onPressed: () {
              AppLogger().clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: AppLogger().logsNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty) {
            return const Center(child: Text('No logs yet.'));
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final logMsg = logs[index];
              final isError = logMsg.contains('ERROR:');
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: SelectableText(
                  logMsg,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: isError ? Colors.red : Colors.black87,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
