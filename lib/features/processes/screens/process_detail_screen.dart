import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/process_models.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/process_service.dart';
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

  List<DocumentModel> _documents = [];
  bool _loadingDocs = false;

  final ProcessService _processService = ProcessService();

  @override
  void initState() {
    super.initState();
    _process = widget.process;
    _connectWebSocket();
    _loadDocuments();
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    super.dispose();
  }

  /// Refetch the full status after a WebSocket change-ping and refresh documents.
  Future<void> _refreshStatus() async {
    try {
      final updated = await _processService.getStatus(_process.processInstanceId);
      if (mounted) setState(() => _process = updated);
    } catch (_) {
      // non-critical — keep showing the last known state
    }
    await _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loadingDocs = true);
    try {
      final docs = await _processService.getDocuments(_process.processInstanceId);
      if (mounted) setState(() => _documents = docs);
    } catch (_) {
      // non-critical — show empty state
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await SecureStorageService.getAccessToken();
    // Same host as the REST client (production flag or dev default).
    final wsUrl = DioClient.wsUrl;

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: (StompFrame frame) {
          if (mounted) setState(() => _connected = true);
          _stompClient?.subscribe(
            destination: '/topic/process/${widget.process.processInstanceId}',
            callback: (StompFrame message) {
              // The broadcast is a lightweight change-ping (it lacks nodeProgress /
              // progressPercent). Refetch the authoritative full status so the timeline
              // and percent advance correctly instead of resetting to defaults.
              _refreshStatus();
            },
          );
        },
        onDisconnect: (_) {
          if (mounted) setState(() => _connected = false);
        },
        onStompError: (StompFrame frame) {
          debugPrint('STOMP error: ${frame.body}');
        },
      ),
    );
    _stompClient?.activate();
  }

  Future<void> _downloadDocument(DocumentModel doc) async {
    try {
      final result = await _processService.getDownloadUrl(doc.id);
      final url = result['presignedUrl'] as String?;
      if (url != null && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al descargar el documento')),
        );
      }
    }
  }

  String _statusText(InstanceStatus s) => switch (s) {
        InstanceStatus.ACTIVE => 'En proceso',
        InstanceStatus.COMPLETED => 'Completado',
        InstanceStatus.CANCELLED => 'Cancelado',
      };

  Icon _statusIcon(InstanceStatus s) => switch (s) {
        InstanceStatus.ACTIVE => const Icon(Icons.pending, color: Colors.orange, size: 48),
        InstanceStatus.COMPLETED => const Icon(Icons.check_circle, color: Colors.green, size: 48),
        InstanceStatus.CANCELLED => const Icon(Icons.cancel, color: Colors.red, size: 48),
      };

  Color _statusSurface(InstanceStatus s) => switch (s) {
        InstanceStatus.ACTIVE => Colors.orange.shade50,
        InstanceStatus.COMPLETED => Colors.green.shade50,
        InstanceStatus.CANCELLED => Colors.red.shade50,
      };

  Widget _buildProgressTimeline() {
    if (_process.nodeProgress.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.timeline, size: 18),
                SizedBox(width: 8),
                Text('Progreso del trámite',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ..._process.nodeProgress.map((item) => _progressTile(item)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _progressTile(NodeProgressItem item) {
    final (color, icon) = switch (item.status) {
      'COMPLETED' => (Colors.green, Icons.check_circle),
      'CURRENT' => (Colors.blue, Icons.radio_button_checked),
      _ => (Colors.grey.shade400, Icons.radio_button_unchecked),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, color: color, size: 20),
              if (item != _process.nodeProgress.last)
                Container(width: 2, height: 24, color: Colors.grey.shade300),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nodeLabel,
                    style: TextStyle(
                        fontWeight: item.status == 'CURRENT'
                            ? FontWeight.bold
                            : FontWeight.normal)),
                if (item.departmentName != null)
                  Text(item.departmentName!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (item.assignedToName != null)
                  Row(children: [
                    Icon(Icons.person_outline, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('Responsable: ${item.assignedToName}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ]),
                if (item.completedAt != null)
                  Text('Completado: ${formatDate(item.completedAt!)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (item.documentCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.description_outlined, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text('${item.documentCount} documento${item.documentCount == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 11, color: Colors.blue)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Header card: progress bar (% stages) + elapsed time + pending client action.
  Widget _buildProgressSummary() {
    final pct = _process.progressPercent;
    final done = _process.nodeProgress.where((n) => n.status == 'COMPLETED').length;
    final total = _process.nodeProgress.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.donut_large, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Avance del trámite',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$pct%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct / 100.0,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: _process.status == InstanceStatus.COMPLETED
                    ? Colors.green
                    : Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (total > 0)
                  Text('$done de $total etapas',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                const Spacer(),
                Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(_elapsedText(),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
            if (_process.pendingClientAction != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assignment_late, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Acción requerida',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.deepOrange)),
                          Text(_process.pendingClientAction!,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _elapsedText() {
    try {
      final start = DateTime.parse(_process.startedAt);
      final end = _process.completedAt != null
          ? DateTime.parse(_process.completedAt!)
          : DateTime.now();
      final d = end.difference(start);
      if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
      if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
      return '${d.inMinutes}m';
    } catch (_) {
      return '—';
    }
  }

  Widget _buildDocumentSection() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('Documentos',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadDocuments,
                  tooltip: 'Actualizar',
                ),
              ],
            ),
          ),
          if (_loadingDocs)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_documents.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No hay documentos adjuntos.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._documents.map((doc) => _documentTile(doc)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _documentTile(DocumentModel doc) {
    final isConfirmed = doc.status == DocumentStatus.CONFIRMED;
    return ListTile(
      leading: Icon(
        isConfirmed ? Icons.insert_drive_file : Icons.hourglass_empty,
        color: isConfirmed ? Colors.blue : Colors.orange,
      ),
      title: Text(doc.fileName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        isConfirmed
            ? 'Confirmado ${doc.confirmedAt != null ? formatDate(doc.confirmedAt!) : ''}'
            : 'Pendiente de confirmación',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: isConfirmed
          ? IconButton(
              icon: const Icon(Icons.download, size: 20),
              onPressed: () => _downloadDocument(doc),
              tooltip: 'Descargar',
            )
          : null,
    );
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
                  color: _statusSurface(_process.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _statusIcon(_process.status),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusText(_process.status),
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

            // Progress summary: % + elapsed + pending client action
            _buildProgressSummary(),
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
                  if (_process.currentDepartmentName != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.business),
                      title: const Text('Departamento'),
                      subtitle: Text(_process.currentDepartmentName!),
                    ),
                  ],
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

            // Progress timeline
            _buildProgressTimeline(),
            if (_process.nodeProgress.isNotEmpty) const SizedBox(height: 16),

            // Documents
            _buildDocumentSection(),
            const SizedBox(height: 16),

            // WebSocket connection banner
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
