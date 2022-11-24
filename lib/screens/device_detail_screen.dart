import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import '/helpers/ble_facade/ble_device_connector.dart';
import '/helpers/constants.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceDetailScreen({required this.device, super.key});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<Map<String, QualifiedCharacteristic>?> _characteristics;

  bool _isProcessingRequest = false;
  late Function() _connectCallback;
  late Function() _disconnectCallback;

  late String writeOutput;
  late TextEditingController textEditingController;
  late StreamSubscription<List<int>>? subscribeStream;

  @override
  void initState() {
    super.initState();

    _setCallbacks();
    _characteristics = _findCharacteristics();

    writeOutput = '';
    textEditingController = TextEditingController();
  }

  @override
  void dispose() {
    subscribeStream?.cancel();
    super.dispose();
  }

  void _setCallbacks() {
    final deviceConnector =
        Provider.of<BleDeviceConnector>(context, listen: false);
    _connectCallback = () => deviceConnector.connect(widget.device.id);
    _disconnectCallback = () => deviceConnector.disconnect(widget.device.id);
  }

  Future<Map<String, QualifiedCharacteristic>?> _findCharacteristics() async {
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);

    await _connectCallback();
    final services = await ble.discoverServices(widget.device.id);
    await _disconnectCallback();

    // Find the main service
    late final DiscoveredCharacteristic txCharacteristic;
    late final DiscoveredCharacteristic rxCharacteristic;
    try {
      final service = services.firstWhere(
          (e) => e.serviceId.toString() == ThermalDevice.mainServiceUuid);
      txCharacteristic = service.characteristics.firstWhere(
          (e) => e.characteristicId.toString() == ThermalDevice.txServiceUuid);
      rxCharacteristic = service.characteristics.firstWhere(
          (e) => e.characteristicId.toString() == ThermalDevice.rxServiceUuid);
    } on StateError {
      return null;
    }

    return {
      'tx': QualifiedCharacteristic(
          characteristicId: txCharacteristic.characteristicId,
          serviceId: txCharacteristic.serviceId,
          deviceId: widget.device.id),
      'rx': QualifiedCharacteristic(
          characteristicId: rxCharacteristic.characteristicId,
          serviceId: rxCharacteristic.serviceId,
          deviceId: widget.device.id),
    };
  }

  List<int> _parseInput() =>
      textEditingController.text.split(',').map(int.parse).toList();

  void _showSnackbarError(String text) {
    final snackBar = SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _processRequest(Function request) async {
    setState(() => _isProcessingRequest = true);
    await request();
    setState(() => _isProcessingRequest = false);
  }

  Future<void> _read(QualifiedCharacteristic rxCharacteristic) async {
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);

    late final List<int> results;
    try {
      await _connectCallback();
      results = await ble.readCharacteristic(rxCharacteristic);
      await _disconnectCallback();
    } on Exception catch (e) {
      results = [];
      _showSnackbarError('Error while reading :\n$e');
    }

    setState(() {
      writeOutput =
          results.isNotEmpty ? results[0].toString() : 'None received';
    });
  }

  Future<void> _transmit(QualifiedCharacteristic txCharacteristic,
      {required bool requestResponse}) async {
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);

    try {
      await _connectCallback();
      requestResponse
          ? await ble.writeCharacteristicWithResponse(txCharacteristic,
              value: _parseInput())
          : await ble.writeCharacteristicWithoutResponse(txCharacteristic,
              value: _parseInput());
      await _disconnectCallback();
    } on Exception catch (e) {
      _showSnackbarError('Error while reading :\n$e');
    }

    setState(() {
      writeOutput = requestResponse ? 'Ok' : 'Done';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, QualifiedCharacteristic>?>(
        future: _characteristics,
        builder: (context, characteristics) {
          if (characteristics.hasData) {
            final charac = characteristics.data!;
            return WillPopScope(
              onWillPop: () async {
                _disconnectCallback();
                return true;
              },
              child: Scaffold(
                appBar: AppBar(title: Text(widget.device.name)),
                body: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _isProcessingRequest
                      ? [
                          const Center(child: CircularProgressIndicator()),
                          const Text('Processing request'),
                        ]
                      : [
                          const Text('Write characteristic',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextField(
                              controller: textEditingController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Value',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: false,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _read(charac['rx']!),
                            child: const Text('Read'),
                          ),
                          ElevatedButton(
                            onPressed: () => _processRequest(() => _transmit(
                                charac['tx']!,
                                requestResponse: true)),
                            child: const Text('With response'),
                          ),
                          ElevatedButton(
                            onPressed: () => _processRequest(() => _transmit(
                                charac['tx']!,
                                requestResponse: false)),
                            child: const Text('Without response'),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(top: 8.0),
                            child: Text('Output: $writeOutput'),
                          ),
                        ],
                ),
              ),
            );
          } else {
            return Scaffold(
                appBar: AppBar(title: Text(widget.device.name)),
                body: const Center(child: CircularProgressIndicator()));
          }
        });
  }
}
