import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/models/process_models.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/process_service.dart';
import '../../../core/utils/format_utils.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../agent/screens/chatbot_screen.dart';
import '../../auth/screens/login_screen.dart';
import 'process_detail_screen.dart';

class ProcessListScreen extends StatefulWidget {
  const ProcessListScreen({super.key});

  @override
  State<ProcessListScreen> createState() => _ProcessListScreenState();
}

class _ProcessListScreenState extends State<ProcessListScreen> {
  late Future<List<ProcessStatus>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = ProcessService().getMyProcesses().catchError((error) {
        final status = error is DioException ? error.response?.statusCode : null;
        if (status == 401 || status == 403) {
          _goToLogin();
        }
        return Future<List<ProcessStatus>>.error(error);
      });
    });
  }

  void _goToLogin() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Icon _statusIcon(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return const Icon(Icons.pending, color: Colors.orange);
      case InstanceStatus.COMPLETED:
        return const Icon(Icons.check_circle, color: Colors.green);
      case InstanceStatus.CANCELLED:
        return const Icon(Icons.cancel, color: Colors.red);
    }
  }

  String _statusLabel(InstanceStatus status) {
    switch (status) {
      case InstanceStatus.ACTIVE:
        return 'En proceso';
      case InstanceStatus.COMPLETED:
        return 'Completado';
      case InstanceStatus.CANCELLED:
        return 'Cancelado';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Tramites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: FutureBuilder<List<ProcessStatus>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Error al cargar los tramites',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }
          final processes = snapshot.data ?? [];
          if (processes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inbox, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No tienes tramites asociados'),
                  const SizedBox(height: 4),
                  Text(
                    'Solicita un tramite en nuestras oficinas',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: processes.length,
            itemBuilder: (context, index) {
              final process = processes[index];
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: _statusIcon(process.status),
                  title: Text(process.policyName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDate(process.startedAt)),
                      Text(_statusLabel(process.status)),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProcessDetailScreen(process: process),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChatbotScreen()),
          );
          _load(); // refresh in case a new trámite was started
        },
        tooltip: 'Iniciar trámite con el asistente',
        icon: const Icon(Icons.smart_toy),
        label: const Text('Nuevo trámite'),
      ),
    );
  }
}
