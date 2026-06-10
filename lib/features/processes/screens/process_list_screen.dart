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

  // Default to the actionable view: trámites in progress.
  InstanceStatus? _filter = InstanceStatus.ACTIVE;

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

  // ── Status visual helpers ──────────────────────────────────────────────────

  ({Color color, IconData icon, String label}) _statusMeta(InstanceStatus s) {
    switch (s) {
      case InstanceStatus.ACTIVE:
        return (color: Colors.orange, icon: Icons.pending, label: 'En proceso');
      case InstanceStatus.COMPLETED:
        return (color: Colors.green, icon: Icons.check_circle, label: 'Completado');
      case InstanceStatus.CANCELLED:
        return (color: Colors.red, icon: Icons.cancel, label: 'Cancelado');
    }
  }

  String _relativeTime(String iso) {
    try {
      final d = DateTime.now().difference(DateTime.parse(iso));
      if (d.inDays >= 30) return 'hace ${d.inDays ~/ 30} mes(es)';
      if (d.inDays >= 1) return 'hace ${d.inDays} día${d.inDays == 1 ? '' : 's'}';
      if (d.inHours >= 1) return 'hace ${d.inHours} h';
      if (d.inMinutes >= 1) return 'hace ${d.inMinutes} min';
      return 'recién';
    } catch (_) {
      return '';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Trámites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
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
                  return _errorState();
                }
                final all = snapshot.data ?? [];
                if (all.isEmpty) {
                  return _emptyAllState();
                }

                // Filter + sort (most recent first)
                final filtered = (_filter == null
                        ? List<ProcessStatus>.from(all)
                        : all.where((p) => p.status == _filter).toList())
                  ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

                return Column(
                  children: [
                    _filterChips(all),
                    Expanded(
                      child: filtered.isEmpty
                          ? _emptyFilterState()
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88, top: 4),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _processCard(filtered[i]),
                            ),
                    ),
                  ],
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
          _load();
        },
        tooltip: 'Iniciar trámite con el asistente',
        icon: const Icon(Icons.smart_toy),
        label: const Text('Nuevo trámite'),
      ),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────────

  Widget _filterChips(List<ProcessStatus> all) {
    int countOf(InstanceStatus? s) =>
        s == null ? all.length : all.where((p) => p.status == s).length;

    Widget chip(String label, InstanceStatus? value, Color? color) {
      final selected = _filter == value;
      final n = countOf(value);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label${n > 0 ? '  $n' : ''}'),
          selected: selected,
          onSelected: (_) => setState(() => _filter = value),
          avatar: color != null
              ? CircleAvatar(backgroundColor: color, radius: 5)
              : null,
          selectedColor: (color ?? Colors.blue).withValues(alpha: 0.18),
          labelStyle: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          chip('En proceso', InstanceStatus.ACTIVE, Colors.orange),
          chip('Completados', InstanceStatus.COMPLETED, Colors.green),
          chip('Cancelados', InstanceStatus.CANCELLED, Colors.red),
          chip('Todos', null, null),
        ],
      ),
    );
  }

  // ── Process card ─────────────────────────────────────────────────────────────

  Widget _processCard(ProcessStatus p) {
    final meta = _statusMeta(p.status);
    final isActive = p.status == InstanceStatus.ACTIVE;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ProcessDetailScreen(process: p)),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: status pill + chevron
              Row(
                children: [
                  _statusPill(meta),
                  const Spacer(),
                  Text(_relativeTime(p.startedAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                p.policyName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              if (isActive) ...[
                Row(
                  children: [
                    Icon(Icons.account_tree_outlined,
                        size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Etapa: ${p.currentNodeLabel}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: p.progressPercent / 100.0,
                          minHeight: 7,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${p.progressPercent}%',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                if (p.pendingClientAction != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      const Icon(Icons.assignment_late, size: 14, color: Colors.deepOrange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.pendingClientAction!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.deepOrange)),
                      ),
                    ]),
                  ),
                ],
              ] else
                Text(
                  '${meta.label} · ${formatDate(p.completedAt ?? p.startedAt)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(({Color color, IconData icon, String label}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(meta.icon, size: 14, color: meta.color),
        const SizedBox(width: 5),
        Text(meta.label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: meta.color)),
      ]),
    );
  }

  // ── Empty / error states ─────────────────────────────────────────────────────

  Widget _emptyFilterState() {
    final label = _filter == null ? '' : _statusMeta(_filter!).label.toLowerCase();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No tienes trámites $label',
              style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _emptyAllState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No tienes trámites asociados'),
          const SizedBox(height: 4),
          Text('Inicia uno con el asistente',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Error al cargar los trámites',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: _load, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
