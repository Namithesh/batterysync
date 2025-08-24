import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:network_info_plus/network_info_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const BatteryHomePage(),
    );
  }
}

class BatteryHomePage extends StatefulWidget {
  const BatteryHomePage({super.key});

  @override
  State<BatteryHomePage> createState() => _BatteryHomePageState();
}

class _BatteryHomePageState extends State<BatteryHomePage> {

  final Battery _battery = Battery();
  final TextEditingController _remoteIpController = TextEditingController();

  int _localBatteryLevel = -1;
  String? _localIpAddress;

  int _remoteBatteryLevel = -1;
  String _remoteStatus = "Enter IP and start syncing";

  Timer? _localBatteryTimer;
  Timer? _remoteBatteryTimer;
  HttpServer? _server;


  @override
  void initState() {
    super.initState();
    // Start monitoring local battery immediately
    _startLocalBatteryMonitoring();
    // Get the device's IP address to display it
    _getDeviceIp();
    // Start the server to share our battery status
    _startServer();
  }

  @override
  void dispose() {
    // Clean up 
    _localBatteryTimer?.cancel();
    _remoteBatteryTimer?.cancel();
    _remoteIpController.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  /// Fetches the local IP address of the device.
  Future<void> _getDeviceIp() async {
    final ip = await NetworkInfo().getWifiIP();
    setState(() {
      _localIpAddress = ip;
    });
  }

  /// Sets up a periodic timer to check the local battery level.
  void _startLocalBatteryMonitoring() {
    _localBatteryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          _localBatteryLevel = level;
        });
      }
    });
    // Get initial value right away
    _battery.batteryLevel.then((level) => setState(() => _localBatteryLevel = level));
  }

  /// Starts the background web server to serve the local battery level.
  Future<void> _startServer() async {
    final router = shelf_router.Router();
    
    // Define an endpoint '/battery' that returns the current battery level
    router.get('/battery', (shelf.Request request) {
      return shelf.Response.ok('$_localBatteryLevel');
    });

    // Start the server on all available network interfaces on port 8080
    try {
      _server = await io.serve(router, '0.0.0.0', 8080);
    } catch (e) {
      // Handle server start error
      if (mounted) {
        setState(() {
          _remoteStatus = "Server error: $e";
        });
      }
    }
  }

  /// Starts a timer
  void _startRemoteBatterySync() {
    final remoteIp = _remoteIpController.text.trim();
    if (remoteIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the remote IP address.')),
      );
      return;
    }

    // Cancel  existing timer 
    _remoteBatteryTimer?.cancel();
    
    setState(() {
      _remoteStatus = "Connecting...";
    });

    _remoteBatteryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _fetchRemoteBattery(remoteIp);
    });
    // Fetch immediately on start
    _fetchRemoteBattery(remoteIp);
  }
  
  /// Makes an HTTP request to the remote device to get its battery level.
  Future<void> _fetchRemoteBattery(String ip) async {
    try {
      final url = Uri.parse('http://$ip:8080/battery');
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final level = int.tryParse(response.body);
        if (level != null) {
          setState(() {
            _remoteBatteryLevel = level;
            _remoteStatus = "Connected";
          });
        } else {
          setState(() => _remoteStatus = "Invalid response");
        }
      } else {
        setState(() => _remoteStatus = "Connection failed (Status: ${response.statusCode})");
      }
    } on TimeoutException {
       setState(() => _remoteStatus = "Connection timed out");
    } catch (e) {
      setState(() => _remoteStatus = "Connection error");
    }
  }

  // --- UI Widget Build Method ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Sync'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section for this device's info
            _buildInfoCard(
              title: 'This Device',
              ipAddress: _localIpAddress,
              batteryLevel: _localBatteryLevel,
              isLocal: true,
            ),
            const SizedBox(height: 20),

            // Section for remote device's info
            _buildInfoCard(
              title: 'Remote Device',
              status: _remoteStatus,
              batteryLevel: _remoteBatteryLevel,
            ),
            const SizedBox(height: 24),

            // Input and connection controls
            _buildControlSection(),
          ],
        ),
      ),
    );
  }

  // --- UI Helper Widgets ---

  Widget _buildInfoCard({
    required String title,
    String? ipAddress,
    String? status,
    required int batteryLevel,
    bool isLocal = false,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (isLocal)
              Text('My IP: ${_localIpAddress ?? "Loading..."}', style: Theme.of(context).textTheme.bodyLarge)
            else
              Text('Status: $status', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            _BatteryIndicator(level: batteryLevel),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _remoteIpController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Remote Device IP Address',
            hintText: 'e.g., 192.168.43.1',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _startRemoteBatterySync,
          icon: const Icon(Icons.sync),
          label: const Text('Start Syncing'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

/// A custom widget to display a battery level indicator.
class _BatteryIndicator extends StatelessWidget {
  final int level;

  const _BatteryIndicator({required this.level});

  Color _getBatteryColor(int level) {
    if (level < 0) return Colors.grey;
    if (level <= 15) return Colors.red;
    if (level <= 40) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: level < 0 ? 0 : level / 100,
              minHeight: 25,
              backgroundColor: Colors.grey.shade700,
              color: _getBatteryColor(level),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          level < 0 ? '--%' : '$level%',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
