import 'package:flutter/material.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/sync_queue.dart';

/// A thin banner shown while offline or while there are operations pending sync (RNF-6).
///
/// Listens to [ConnectivityService] (interface state) and the [SyncQueue] (pending count),
/// so the user always knows whether their actions are queued or live.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final ConnectivityService _connectivity = ConnectivityService.instance;
  late bool _online = _connectivity.isOnline;

  @override
  void initState() {
    super.initState();
    _connectivity.onStatusChange.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncQueue.instance,
      builder: (context, _) {
        final pending = SyncQueue.instance.pendingCount;
        final flushing = SyncQueue.instance.isFlushing;
        if (_online && pending == 0) return const SizedBox.shrink();

        final (color, icon, text) = _online
            ? (
                Colors.blue.shade700,
                flushing ? Icons.sync : Icons.cloud_upload,
                flushing
                    ? 'Sincronizando $pending operación(es)…'
                    : '$pending operación(es) pendientes de sincronizar',
              )
            : (
                Colors.orange.shade800,
                Icons.cloud_off,
                pending == 0
                    ? 'Sin conexión — mostrando datos guardados'
                    : 'Sin conexión — $pending operación(es) en cola',
              );

        return Material(
          color: color,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  if (_online && pending > 0 && !flushing)
                    TextButton(
                      onPressed: () => SyncQueue.instance.flush(),
                      child: const Text('Sincronizar',
                          style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
