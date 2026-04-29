import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import '../../../core/models/process_models.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/format_utils.dart';

class ProcessDetailScreen extends StatefulWidget {
  final ProcessStatus process;

  const ProcessDetailScreen({super.key, required this.process});

  @override
  State<ProcessDetailScreen> createState() => _ProcessDetailScreenState();
}

class _ProcessDetailScreenState extends State<ProcessDetailScreen> {
  late ProcessStatus _process;
  StompClient? _stompClient;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _process = widget.process;
    _connectWebSocket();
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    super.dispose();
  }

  Future<void> _connectWebSocket() async {
    final token = await SecureStorageService.getAccessToken();
    final wsUrl = kIsWeb
      ? 'ws://localhost:3000/ws/websocket'
      : 'ws://34.237.109.152:3000/ws/websocket';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: (StompFrame frame) {
          if (mounted) setState(() => _connected = true);
          _stompClient?.subscribe(
            destination:
                '/topic/process/${widget.process.processInstanceId}',
            callback: (StompFrame message) {
              if (message.body != null) {
                final updated = ProcessStatus.fromJson(
                  json.decode(message.body!) as Map<String, dynamic>,
                );
                if (mounted) setState(() => _process = updated);
              }
            },
          );
        },
        onDisconnect: (_) {
          if (mounted) setState(() => _connected = false);
        },
        onStompError: (StompFrame frame) {
          // ignore: avoid_print
          print('STOMP error: ${frame.body}');
        },
      ),
    );
    _stompClient?.activate();
  }

  String _getStatusText(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return 'En proceso';
      case InstanceStatus.COMPLETED:
        return 'Completado';
      case InstanceStatus.CANCELLED:
        return 'Cancelado';
    }
  }

  Color _getStatusColor(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return Colors.orange;
      case InstanceStatus.COMPLETED:
        return Colors.green;
      case InstanceStatus.CANCELLED:
        return Colors.red;
    }
  }

  Icon _getStatusIcon(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return const Icon(Icons.pending, color: Colors.orange, size: 48);
      case InstanceStatus.COMPLETED:
        return const Icon(Icons.check_circle, color: Colors.green, size: 48);
      case InstanceStatus.CANCELLED:
        return const Icon(Icons.cancel, color: Colors.red, size: 48);
    }
  }

  Color _getStatusSurfaceColor(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return Colors.orange.shade50;
      case InstanceStatus.COMPLETED:
        return Colors.green.shade50;
      case InstanceStatus.CANCELLED:
        return Colors.red.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Trámite'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _connected ? Icons.wifi : Icons.wifi_off,
              color: _connected ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              child: Container(
                decoration: BoxDecoration(
                  color: _getStatusSurfaceColor(_process.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _getStatusIcon(_process.status),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusText(_process.status),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Estado del trámite',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Info card
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.tag),
                    title: const Text('Política'),
                    subtitle: Text(_process.policyName),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: const Text('Nodo actual'),
                    subtitle: Text(_process.currentNodeLabel),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Iniciado'),
                    subtitle: Text(formatDate(_process.startedAt)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('ID'),
                    subtitle: Text(
                      _process.processInstanceId,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Real-time connection banner
            if (_connected)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_tethering, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Conectado — actualizaciones en tiempo real'),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sync, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    const Text('Conectando...'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
