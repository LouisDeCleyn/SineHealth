import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:flutter_web_bluetooth/js_web_bluetooth.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const SineHealthApp());
}

class SineHealthApp extends StatelessWidget {
  const SineHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sine Health',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BluetoothDevice? _device;
  // Use the correct type from the JS package
  WebBluetoothRemoteGATTCharacteristic? _heartRateChar;
  StreamSubscription? _heartRateSub;
  int? _currentHeartRate;
  List<int> _heartRateHistory = [];
  String? _error;

  static const String heartRateService = "0000180d-0000-1000-8000-00805f9b34fb";
  static const String heartRateMeasurement = "00002a37-0000-1000-8000-00805f9b34fb";

  @override
  void dispose() {
    _heartRateSub?.cancel();
    _device?.gatt?.disconnect();
    super.dispose();
  }

  Future<void> _scanAndConnect() async {
    setState(() {
      _error = null;
      _device = null;
      _heartRateChar = null;
      _currentHeartRate = null;
      _heartRateHistory = [];
    });

    final isAvailable = await FlutterWebBluetooth.instance.isAvailable.first;
    if (!isAvailable) {
      setState(() {
        _error = "Web Bluetooth is not supported. Use Chrome or Edge.";
      });
      return;
    }

    try {
      final device = await FlutterWebBluetooth.instance.requestDevice(
        RequestOptionsBuilder(
          [RequestFilterBuilder(services: [heartRateService])],
          optionalServices: [heartRateService],
        ),
      );

      setState(() {
        _device = device;
      });

      await device.gatt!.connect();
      final service = await device.gatt!.getPrimaryService(heartRateService);
      final characteristic = await service.getCharacteristic(heartRateMeasurement);
      _heartRateChar = characteristic;

      await _subscribeToHeartRate(characteristic);
    } catch (e) {
      setState(() {
        _error = "Connection failed: $e";
      });
    }
  }

  // Use the correct parameter type from the JS package
  Future<void> _subscribeToHeartRate(WebBluetoothRemoteGATTCharacteristic char) async {
    try {
      await char.startNotifications();
      
      // Set up periodic reading of the characteristic value
      _heartRateSub = Stream.periodic(const Duration(milliseconds: 1000)).listen((_) async {
        try {
          final byteData = await char.readValue();
          // Convert ByteData to Uint8List
          final buffer = byteData.buffer;
          final uint8List = Uint8List.view(buffer, byteData.offsetInBytes, byteData.lengthInBytes);
          
          final parsed = _parseHeartRate(uint8List);
          if (parsed != null) {
            setState(() {
              _currentHeartRate = parsed;
              _heartRateHistory.add(parsed);
              if (_heartRateHistory.length > 30) {
                _heartRateHistory.removeAt(0);
              }
            });
          }
        } catch (e) {
          print('Error reading heart rate: $e');
        }
      });
    } catch (e) {
      setState(() {
        _error = "Failed to subscribe to notifications: $e";
      });
    }
  }

  int? _parseHeartRate(Uint8List data) {
    if (data.isEmpty) return null;
    final flags = data[0];
    final is16Bit = (flags & 0x01) != 0;
    if (is16Bit && data.length >= 3) {
      return data[1] | (data[2] << 8);
    } else if (data.length >= 2) {
      return data[1];
    }
    return null;
  }

  Future<void> _disconnect() async {
    await _heartRateSub?.cancel();
    _device?.gatt?.disconnect();
    setState(() {
      _device = null;
      _heartRateChar = null;
      _currentHeartRate = null;
      _heartRateHistory = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sine Health')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? _buildError()
              : _device == null
                  ? _buildScanButton()
                  : _buildDeviceInfo(),
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.favorite, color: Colors.red, size: 80),
        const SizedBox(height: 24),
        const Text('Scan for a BLE Heart Rate Monitor', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Scan for Devices'),
          onPressed: _scanAndConnect,
        ),
      ],
    );
  }

  Widget _buildDeviceInfo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.watch, size: 60),
        const SizedBox(height: 12),
        Text(_device?.name ?? 'Unknown Device', style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 24),
        _currentHeartRate != null
            ? Column(
                children: [
                  const Text('Heart Rate', style: TextStyle(fontSize: 18)),
                  Text(
                    '$_currentHeartRate bpm',
                    style: const TextStyle(fontSize: 48, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(height: 150, child: _buildHeartRateChart()),
                ],
              )
            : const Text('Waiting for heart rate data...', style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
          onPressed: _disconnect,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error, color: Colors.red, size: 60),
        const SizedBox(height: 16),
        Text(_error ?? '', style: const TextStyle(fontSize: 18, color: Colors.red), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
          onPressed: () => setState(() => _error = null),
        ),
      ],
    );
  }

  Widget _buildHeartRateChart() {
    if (_heartRateHistory.isEmpty) {
      return const Center(child: Text('No data yet'));
    }

    return LineChart(
      LineChartData(
        minY: (_heartRateHistory.reduce((a, b) => a < b ? a : b) - 10).toDouble(),
        maxY: (_heartRateHistory.reduce((a, b) => a > b ? a : b) + 10).toDouble(),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              _heartRateHistory.length,
              (i) => FlSpot(i.toDouble(), _heartRateHistory[i].toDouble()),
            ),
            isCurved: true,
            color: Colors.red,
            barWidth: 3,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}