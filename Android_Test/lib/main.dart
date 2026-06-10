import 'package:flutter/material.dart';
import 'ble_tester_screen.dart';
import 'lan_tester_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NyanEyeTesterApp());
}

class NyanEyeTesterApp extends StatelessWidget {
  const NyanEyeTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NyanEye SDK Tester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainTesterScreen(),
    );
  }
}

class MainTesterScreen extends StatefulWidget {
  const MainTesterScreen({super.key});

  @override
  State<MainTesterScreen> createState() => _MainTesterScreenState();
}

class _MainTesterScreenState extends State<MainTesterScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    BleTesterScreen(),
    LanTesterScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NyanEye SDK 极简测试器', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            selectedIcon: Icon(Icons.bluetooth_connected, color: Colors.deepPurpleAccent),
            label: '蓝牙调试器',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi),
            selectedIcon: Icon(Icons.wifi_tethering, color: Colors.deepPurpleAccent),
            label: '局域网调试器',
          ),
        ],
      ),
    );
  }
}
