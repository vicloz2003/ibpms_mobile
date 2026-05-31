import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lightweight JSON key–value store persisted to the app documents directory.
///
/// Backs the offline layer (RNF-6): the read cache ([LocalStore] keyed by entity)
/// and the sync queue both serialize plain JSON here, so the app keeps working
/// with no network. Not encrypted — only non-sensitive trámite data is cached;
/// tokens stay in [SecureStorageService].
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  Directory? _dir;

  Future<File> _file(String key) async {
    _dir ??= await getApplicationDocumentsDirectory();
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${_dir!.path}/ibpms_$safe.json');
  }

  /// Read a previously stored JSON value, or `null` if absent/corrupt.
  Future<dynamic> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      if (content.isEmpty) return null;
      return jsonDecode(content);
    } catch (_) {
      return null; // corrupt cache must never crash the app
    }
  }

  /// Persist a JSON-encodable value atomically (write to temp then rename).
  Future<void> write(String key, dynamic value) async {
    final f = await _file(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(String key) async {
    try {
      final f = await _file(key);
      if (await f.exists()) await f.delete();
    } catch (_) {/* best effort */}
  }
}
