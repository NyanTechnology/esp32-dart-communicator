import 'package:flutter/material.dart';
import 'package:esp32_comm/esp32_comm.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Comm Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _discoveryService = DeviceDiscoveryService();
  List<DeviceInfo> _devices = [];
  bool _isScanning = false;

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    try {
      final devices = await _discoveryService.discoverEsp32DevicesOnLan();
      setState(() => _devices = devices);
    } finally {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 Comm Example')),
      body: _isScanning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final d = _devices[index];
                return ListTile(
                  title: Text(d.staIp ?? 'Unknown IP'),
                  subtitle: Text('Mode: ${d.mode}, FW: ${d.firmware}'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scan,
        tooltip: 'Scan LAN',
        child: const Icon(Icons.search),
      ),
    );
  }
}
