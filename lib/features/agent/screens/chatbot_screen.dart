import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/models/agent_models.dart';
import '../../../core/services/agent_service.dart';
import '../../processes/screens/process_list_screen.dart';

/// RF-2: Conversational agent. The client describes their problem by voice or
/// text; the agent classifies the matching policy, requests mandatory documents,
/// and starts the trámite.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatMessage {
  final bool isUser;
  final String text;
  const _ChatMessage(this.isUser, this.text);
}

class _DocState {
  String status; // PENDING, UPLOADING, CONFIRMED
  String? documentId;
  String? error;
  _DocState({this.status = 'PENDING', this.documentId, this.error});
}

const _mimeByExt = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _agent = AgentService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _recorder = AudioRecorder();

  final List<_ChatMessage> _messages = [
    const _ChatMessage(false,
        'Hola, soy tu asistente. Cuéntame qué trámite necesitas — puedes escribir o usar el micrófono.'),
  ];

  AgentClassifyResult? _result;
  final Map<String, _DocState> _docStates = {};

  bool _classifying = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _starting = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _addMessage(bool isUser, String text) {
    setState(() => _messages.add(_ChatMessage(isUser, text)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ── Voice ────────────────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path != null) await _transcribe(path);
      return;
    }
    if (!await _recorder.hasPermission()) {
      _snack('Permiso de micrófono denegado');
      return;
    }
    final dir = await getTemporaryDirectory();
    final filePath =
        '${dir.path}${Platform.pathSeparator}agent_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: filePath);
    setState(() => _recording = true);
  }

  Future<void> _transcribe(String path) async {
    setState(() => _transcribing = true);
    try {
      final text = await _agent.transcribe(path);
      _textCtrl.text = text;
      if (text.trim().isNotEmpty) {
        await _send(); // auto-send the transcription
      }
    } catch (_) {
      _snack('No se pudo transcribir el audio');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  // ── Classify ───────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    _addMessage(true, text);
    setState(() {
      _classifying = true;
      _result = null;
      _docStates.clear();
    });

    try {
      final result = await _agent.classify(text);
      _addMessage(false, result.message);
      setState(() {
        _result = result;
        for (final d in result.requiredDocuments.where((r) => r.mandatory)) {
          _docStates[d.id] = _DocState();
        }
      });
    } catch (_) {
      _addMessage(false, 'Ocurrió un error al procesar tu solicitud. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  // ── Documents ───────────────────────────────────────────────────────────────
  Future<void> _pickAndUpload(AgentDocRequirement req) async {
    final allowed = req.allowedMimeTypes
        .map((m) => m.split('/').last)
        .where((e) => e.isNotEmpty)
        .toList();
    final picked = await FilePicker.platform.pickFiles(
      type: allowed.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowed.isEmpty ? null : allowed,
    );
    if (picked == null || picked.files.single.path == null) return;

    final file = File(picked.files.single.path!);
    final ext = file.path.split('.').last.toLowerCase();
    final mime = _mimeByExt[ext] ?? 'application/octet-stream';

    setState(() => _docStates[req.id] = _DocState(status: 'UPLOADING'));
    try {
      final docId = await _agent.uploadRequiredDocument(
        policyId: _result!.policyId!,
        requirementId: req.id,
        file: file,
        mimeType: mime,
      );
      setState(() =>
          _docStates[req.id] = _DocState(status: 'CONFIRMED', documentId: docId));
    } catch (_) {
      setState(() => _docStates[req.id] =
          _DocState(status: 'PENDING', error: 'Error al subir. Reintenta.'));
    }
  }

  bool get _allMandatoryUploaded {
    final mandatory =
        _result?.requiredDocuments.where((r) => r.mandatory).toList() ?? [];
    return mandatory.every((r) => _docStates[r.id]?.status == 'CONFIRMED');
  }

  // ── Start ───────────────────────────────────────────────────────────────────
  Future<void> _startProcess() async {
    if (_result?.policyId == null) return;
    setState(() => _starting = true);
    try {
      final ids = _docStates.values
          .where((d) => d.documentId != null)
          .map((d) => d.documentId!)
          .toList();
      await _agent.startProcess(
          policyId: _result!.policyId!, confirmedDocumentIds: ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Trámite iniciado correctamente!')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ProcessListScreen()),
        (_) => false,
      );
    } catch (_) {
      _snack('No se pudo iniciar el trámite');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente de Trámites'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                ..._messages.map(_bubble),
                if (_classifying)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                if (_result != null && _result!.confident) _recommendationCard(),
              ],
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _bubble(_ChatMessage m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: m.isUser
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          m.text,
          style: TextStyle(color: m.isUser ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _recommendationCard() {
    final r = _result!;
    final mandatoryDocs =
        r.requiredDocuments.where((d) => d.mandatory).toList();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.policyName ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Confianza: ${(r.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),

            if (mandatoryDocs.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Documentos requeridos',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...mandatoryDocs.map(_docRow),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_starting || !_allMandatoryUploaded)
                    ? null
                    : _startProcess,
                icon: _starting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_allMandatoryUploaded
                    ? 'Iniciar este trámite'
                    : 'Carga los documentos obligatorios'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docRow(AgentDocRequirement req) {
    final state = _docStates[req.id] ?? _DocState();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (state.status == 'CONFIRMED')
            const Icon(Icons.check_circle, color: Colors.green, size: 22)
          else if (state.status == 'UPLOADING')
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.error_outline, color: Colors.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (state.error != null)
                  Text(state.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
          ),
          if (state.status == 'CONFIRMED')
            const Text('Cargado',
                style: TextStyle(color: Colors.green, fontSize: 12))
          else if (state.status != 'UPLOADING')
            TextButton.icon(
              onPressed: () => _pickAndUpload(req),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Cargar'),
            ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(_recording ? Icons.stop_circle : Icons.mic,
                  color: _recording ? Colors.red : Theme.of(context).colorScheme.primary),
              tooltip: _recording ? 'Detener' : 'Hablar',
              onPressed: _transcribing ? null : _toggleRecording,
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: _recording
                      ? 'Grabando…'
                      : _transcribing
                          ? 'Transcribiendo…'
                          : 'Escribe tu solicitud…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              color: Theme.of(context).colorScheme.primary,
              onPressed: _classifying ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
