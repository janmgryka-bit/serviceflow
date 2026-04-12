import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_board_research_result.dart';
import '../models/diagnostic_chat_snapshot.dart';
import '../models/indexed_web_source.dart';
import '../models/knowledge_index_result.dart';
import 'knowledge_pdf_extractor.dart';
import 'knowledge_url_fetcher.dart';
import '../models/diagnostic_session_state.dart';
import '../models/measurement_log_entry.dart';
import '../models/repair_project.dart';
import '../models/repair_status.dart';
import '../models/repair_summary.dart';

Future<void> _createBoardLookupCacheTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS board_lookup_cache (
      model_key TEXT NOT NULL,
      cached_on TEXT NOT NULL,
      payload TEXT NOT NULL,
      PRIMARY KEY (model_key, cached_on)
    )
  ''');
}

Future<void> _createDiagnosticSessionsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS diagnostic_sessions (
      repair_id TEXT PRIMARY KEY,
      updated_at INTEGER NOT NULL,
      payload TEXT NOT NULL
    )
  ''');
}

Future<void> _createDiagnosticChatTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS diagnostic_chat (
      repair_id TEXT PRIMARY KEY,
      updated_at INTEGER NOT NULL,
      payload TEXT NOT NULL
    )
  ''');
}

Future<void> _createMeasurementLogsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS measurement_logs (
      id TEXT PRIMARY KEY,
      repair_id TEXT NOT NULL,
      measured_at INTEGER NOT NULL,
      kind TEXT NOT NULL,
      value REAL NOT NULL,
      unit TEXT NOT NULL,
      net_label TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_measurement_repair_time ON measurement_logs(repair_id, measured_at)',
  );
}

Future<void> _createKnowledgeTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS knowledge_meta (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      source_path TEXT NOT NULL,
      indexed_at INTEGER NOT NULL,
      chunk_count INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
      body,
      chunk_id UNINDEXED,
      source_kind UNINDEXED,
      source_ref UNINDEXED,
      tokenize = 'unicode61'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS indexed_web_sources (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL DEFAULT '',
      indexed_at INTEGER NOT NULL,
      chunk_count INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

/// v7 → v8: FTS z typem źródła (pdf/web) + tabela linków WWW.
Future<void> _migrateKnowledgeV8(Database db) async {
  var pdfPath = '';
  List<Map<String, Object?>> oldRows = [];
  try {
    final meta = await db.query('knowledge_meta', where: 'id = ?', whereArgs: [1]);
    if (meta.isNotEmpty) {
      pdfPath = meta.first['source_path'] as String? ?? '';
    }
    oldRows = await db.rawQuery('SELECT body, chunk_id FROM knowledge_fts');
  } catch (_) {}
  await db.execute('DROP TABLE IF EXISTS knowledge_fts');
  await db.execute('''
    CREATE VIRTUAL TABLE knowledge_fts USING fts5(
      body,
      chunk_id UNINDEXED,
      source_kind UNINDEXED,
      source_ref UNINDEXED,
      tokenize = 'unicode61'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS indexed_web_sources (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL DEFAULT '',
      indexed_at INTEGER NOT NULL,
      chunk_count INTEGER NOT NULL DEFAULT 0
    )
  ''');
  if (oldRows.isEmpty) return;
  final ref = pdfPath.isNotEmpty ? pdfPath : 'pdf';
  final batch = db.batch();
  for (final r in oldRows) {
    batch.insert('knowledge_fts', {
      'body': r['body'] as String,
      'chunk_id': r['chunk_id'] as String,
      'source_kind': 'pdf',
      'source_ref': ref,
    });
  }
  await batch.commit(noResult: true);
}

const _prefsLegacyKey = 'repair_projects_v1';
const _migrationDoneKey = 'repair_db_migrated_v2';

class RepairStorage {
  RepairStorage._();
  static final RepairStorage instance = RepairStorage._();

  static const _uuid = Uuid();

  Database? _db;

  /// Generates a new unique repair id (UUID v4).
  String newRepairId() => _uuid.v4();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'service_flow_repairs.db');
    _db = await openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE repairs (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            board_id TEXT,
            device_label TEXT,
            repair_status TEXT NOT NULL DEFAULT 'inDiagnosis',
            board_confirmed INTEGER NOT NULL DEFAULT 1,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_created ON repairs(created_at)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_board ON repairs(board_id)',
        );
        await _createBoardLookupCacheTable(db);
        await _createDiagnosticSessionsTable(db);
        await _createDiagnosticChatTable(db);
        await _createMeasurementLogsTable(db);
        await _createKnowledgeTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBoardLookupCacheTable(db);
        }
        if (oldVersion < 3) {
          await _createDiagnosticSessionsTable(db);
        }
        if (oldVersion < 4) {
          await _createDiagnosticChatTable(db);
        }
        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN board_id TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN device_label TEXT');
          } catch (_) {}
          final rows = await db.query('repairs');
          final batch = db.batch();
          for (final row in rows) {
            try {
              final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
              final project = RepairProject.fromJson(payload);
              batch.update(
                'repairs',
                {
                  'board_id': project.boardModelCode,
                  'device_label': project.displayTitle,
                },
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            } catch (_) {}
          }
          await batch.commit(noResult: true);
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_repairs_created ON repairs(created_at)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_repairs_board ON repairs(board_id)',
          );
          await _createMeasurementLogsTable(db);
        }
        if (oldVersion < 6) {
          try {
            await db.execute(
              "ALTER TABLE repairs ADD COLUMN repair_status TEXT DEFAULT 'inDiagnosis'",
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN board_confirmed INTEGER DEFAULT 1',
            );
          } catch (_) {}
          final rows = await db.query('repairs', columns: ['id', 'payload']);
          for (final row in rows) {
            try {
              final project = RepairProject.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              );
              await db.update(
                'repairs',
                {
                  'repair_status': project.repairStatus.name,
                  'board_confirmed': project.boardIdentityConfirmed ? 1 : 0,
                },
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            } catch (_) {}
          }
        }
        if (oldVersion < 7) {
          await _createKnowledgeTables(db);
        }
        if (oldVersion < 8) {
          await _migrateKnowledgeV8(db);
        }
      },
    );
    await _migrateFromPrefsOnce(_db!);
    return _db!;
  }

  Future<void> _migrateFromPrefsOnce(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationDoneKey) == true) return;

    final raw = prefs.getString(_prefsLegacyKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setBool(_migrationDoneKey, true);
      return;
    }

    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final batch = db.batch();
      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map);
        final project = RepairProject.fromJson(map);
        batch.insert(
          'repairs',
          {
            'id': project.id,
            'created_at': project.createdAt.millisecondsSinceEpoch,
            'board_id': project.boardModelCode,
            'device_label': project.displayTitle,
            'repair_status': project.repairStatus.name,
            'board_confirmed': project.boardIdentityConfirmed ? 1 : 0,
            'payload': jsonEncode(project.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {}
    await prefs.remove(_prefsLegacyKey);
    await prefs.setBool(_migrationDoneKey, true);
  }

  /// Szybka lista bez dekodowania pełnego JSON payload — użyj zamiast [loadRepairs] na ekranie głównym.
  Future<List<RepairSummary>> loadRepairSummaries() async {
    final db = await _database;
    final rows = await db.query(
      'repairs',
      columns: [
        'id',
        'created_at',
        'board_id',
        'device_label',
        'repair_status',
        'board_confirmed',
        'payload',
      ],
      orderBy: 'created_at DESC',
    );
    final out = <RepairSummary>[];
    for (final r in rows) {
      final id = r['id'] as String;
      final created = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int);
      var boardId = r['board_id'] as String?;
      var label = r['device_label'] as String?;
      RepairStatus rs = RepairStatus.inDiagnosis;
      var bic = true;
      final rsRaw = r['repair_status'] as String?;
      final parsed = repairStatusFromStorage(rsRaw);
      if (parsed != null) rs = parsed;
      final bcRaw = r['board_confirmed'];
      if (bcRaw is int) bic = bcRaw != 0;
      if (boardId == null || boardId.isEmpty) {
        try {
          final project = RepairProject.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          );
          boardId = project.boardModelCode;
          label = project.displayTitle;
          rs = project.repairStatus;
          bic = project.boardIdentityConfirmed;
        } catch (_) {
          boardId = '';
          label = '';
        }
      }
      label ??= '';
      out.add(
        RepairSummary(
          id: id,
          boardId: boardId,
          deviceLabel: label,
          createdAt: created,
          repairStatus: rs,
          boardIdentityConfirmed: bic,
        ),
      );
    }
    return out;
  }

  /// Pełny projekt po id (jeden odczyt JSON).
  Future<RepairProject?> getRepairById(String id) async {
    final db = await _database;
    final rows = await db.query(
      'repairs',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return RepairProject.fromJson(
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Kompatybilność wsteczna — wolniejsze; preferuj [loadRepairSummaries].
  Future<List<RepairProject>> loadRepairs() async {
    final db = await _database;
    final rows = await db.query('repairs', orderBy: 'created_at DESC');
    return rows
        .map(
          (r) => RepairProject.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> saveRepair(RepairProject project) async {
    final db = await _database;
    await db.insert(
      'repairs',
      {
        'id': project.id,
        'created_at': project.createdAt.millisecondsSinceEpoch,
        'board_id': project.boardModelCode,
        'device_label': project.displayTitle,
        'repair_status': project.repairStatus.name,
        'board_confirmed': project.boardIdentityConfirmed ? 1 : 0,
        'payload': jsonEncode(project.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertMeasurement(MeasurementLogEntry entry) async {
    final db = await _database;
    await db.insert(
      'measurement_logs',
      {
        'id': entry.id,
        'repair_id': entry.repairId,
        'measured_at': entry.measuredAt.millisecondsSinceEpoch,
        'kind': entry.kind.name,
        'value': entry.value,
        'unit': entry.unit,
        'net_label': entry.netLabel,
        'note': entry.note,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MeasurementLogEntry>> listMeasurements(
    String repairId, {
    int limit = 100,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'measurement_logs',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return rows.map(_rowToMeasurement).toList();
  }

  MeasurementLogEntry _rowToMeasurement(Map<String, Object?> r) {
    return MeasurementLogEntry(
      id: r['id'] as String,
      repairId: r['repair_id'] as String,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(r['measured_at'] as int),
      kind: MeasurementKind.values.firstWhere(
        (k) => k.name == r['kind'],
        orElse: () => MeasurementKind.voltage,
      ),
      value: (r['value'] as num).toDouble(),
      unit: r['unit'] as String? ?? '',
      netLabel: r['net_label'] as String? ?? '',
      note: r['note'] as String? ?? '',
    );
  }

  /// Cached Gemini board lookup for [modelKey] on local calendar day [cachedOn] (YYYY-MM-DD).
  Future<AiBoardResearchResult?> getBoardLookupCache(
    String modelKey,
    String cachedOn,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'board_lookup_cache',
      columns: ['payload'],
      where: 'model_key = ? AND cached_on = ?',
      whereArgs: [modelKey, cachedOn],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      return AiBoardResearchResult.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBoardLookupCache(
    String modelKey,
    String cachedOn,
    AiBoardResearchResult result,
  ) async {
    final db = await _database;
    await db.insert(
      'board_lookup_cache',
      {
        'model_key': modelKey,
        'cached_on': cachedOn,
        'payload': jsonEncode(result.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Saved diagnostic workspace (measurements, notes) for a repair.
  Future<DiagnosticSessionState?> getDiagnosticSession(String repairId) async {
    final db = await _database;
    final rows = await db.query(
      'diagnostic_sessions',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DiagnosticSessionState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDiagnosticSession(
    String repairId,
    DiagnosticSessionState state,
  ) async {
    final db = await _database;
    await db.insert(
      'diagnostic_sessions',
      {
        'repair_id': repairId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'payload': jsonEncode(state.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Interactive diagnostic chat (Groq) state for a repair.
  Future<DiagnosticChatSnapshot?> getDiagnosticChatSnapshot(
    String repairId,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'diagnostic_chat',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DiagnosticChatSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDiagnosticChatSnapshot(
    String repairId,
    DiagnosticChatSnapshot snapshot,
  ) async {
    final db = await _database;
    await db.insert(
      'diagnostic_chat',
      {
        'repair_id': repairId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'payload': jsonEncode(snapshot.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ostatnio zindeksowany PDF (ścieżka + liczba fragmentów), albo null.
  Future<KnowledgeSourceMeta?> getKnowledgeSourceMeta() async {
    final db = await _database;
    final rows = await db.query('knowledge_meta', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final path = r['source_path'] as String? ?? '';
    if (path.isEmpty) return null;
    final count = (r['chunk_count'] as int?) ?? 0;
    final at = (r['indexed_at'] as int?) ?? 0;
    return KnowledgeSourceMeta(
      sourcePath: path,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(at),
      chunkCount: count,
    );
  }

  /// Indeksuje PDF: czyści poprzedni indeks, zapisuje chunki w FTS5.
  Future<KnowledgeIndexResult> indexKnowledgePdf(String absolutePath) async {
    final trimmed = absolutePath.trim();
    if (trimmed.isEmpty) {
      return const KnowledgeIndexResult(success: false, message: 'Brak ścieżki do pliku.');
    }
    String plain;
    try {
      plain = await extractPdfPlainText(trimmed);
    } catch (e, st) {
      debugPrint('indexKnowledgePdf extract: $e\n$st');
      return KnowledgeIndexResult(
        success: false,
        message: 'Nie udało się odczytać PDF: $e',
      );
    }
    final chunks = chunkPlainText(plain);
    if (chunks.isEmpty) {
      return const KnowledgeIndexResult(
        success: false,
        message: 'Brak tekstu w PDF (np. skan bez warstwy tekstu).',
      );
    }
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.execute("DELETE FROM knowledge_fts WHERE source_kind = 'pdf'");
        await txn.delete('knowledge_meta');
        final batch = txn.batch();
        for (final body in chunks) {
          batch.insert('knowledge_fts', {
            'body': body,
            'chunk_id': _uuid.v4(),
            'source_kind': 'pdf',
            'source_ref': trimmed,
          });
        }
        await batch.commit(noResult: true);
        await txn.insert('knowledge_meta', {
          'id': 1,
          'source_path': trimmed,
          'indexed_at': DateTime.now().millisecondsSinceEpoch,
          'chunk_count': chunks.length,
        });
      });
    } catch (e, st) {
      debugPrint('indexKnowledgePdf db: $e\n$st');
      return KnowledgeIndexResult(
        success: false,
        message: 'Błąd zapisu indeksu: $e',
      );
    }
    return KnowledgeIndexResult(success: true, chunkCount: chunks.length);
  }

  /// Wyszukuje fragmenty pasujące do zapytania (ostatnia wiadomość użytkownika / kontekst).
  Future<List<String>> searchKnowledgeForPrompt(
    String queryText, {
    int limit = 6,
  }) async {
    final q = _ftsQueryFromUserInput(queryText);
    if (q == null) return [];
    final db = await _database;
    try {
      final rows = await db.rawQuery(
        'SELECT body FROM knowledge_fts WHERE knowledge_fts MATCH ? LIMIT ?',
        [q, limit],
      );
      return rows.map((r) => r['body'] as String).toList();
    } catch (e, st) {
      debugPrint('searchKnowledgeForPrompt: $e\n$st');
      return [];
    }
  }

  /// Usuwa lokalny indeks (meta + FTS + linki WWW).
  Future<void> clearKnowledgeBase() async {
    final db = await _database;
    await db.execute('DELETE FROM knowledge_fts');
    await db.delete('knowledge_meta');
    await db.delete('indexed_web_sources');
  }

  /// Usuwa tylko fragmenty z PDF (linki WWW zostają).
  Future<void> clearKnowledgePdfOnly() async {
    final db = await _database;
    await db.execute("DELETE FROM knowledge_fts WHERE source_kind = 'pdf'");
    await db.delete('knowledge_meta');
  }

  Future<List<IndexedWebSource>> listIndexedWebSources() async {
    final db = await _database;
    final rows = await db.query('indexed_web_sources', orderBy: 'indexed_at DESC');
    return rows
        .map(
          (r) => IndexedWebSource(
            id: r['id'] as String,
            url: r['url'] as String,
            title: r['title'] as String? ?? '',
            indexedAt: DateTime.fromMillisecondsSinceEpoch(r['indexed_at'] as int),
            chunkCount: (r['chunk_count'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Pobiera HTML, wycina tekst, zapisuje chunki pod wyszukiwanie RAG.
  Future<KnowledgeIndexResult> indexKnowledgeUrl(String rawUrl) async {
    final normalized = _normalizeKnowledgeUrl(rawUrl);
    if (normalized == null) {
      return const KnowledgeIndexResult(
        success: false,
        message: 'Nieprawidłowy adres URL (dodaj https://).',
      );
    }
    String plain;
    String title;
    try {
      final fetched = await fetchUrlPlainText(normalized);
      plain = fetched.text;
      title = fetched.title;
    } catch (e, st) {
      debugPrint('indexKnowledgeUrl fetch: $e\n$st');
      return KnowledgeIndexResult(
        success: false,
        message: 'Nie udało się pobrać strony: $e',
      );
    }
    final chunks = chunkPlainText(plain);
    if (chunks.isEmpty) {
      return const KnowledgeIndexResult(
        success: false,
        message: 'Brak tekstu do indeksu (pusta strona lub wyłącznie skrypty).',
      );
    }
    final id = _uuid.v4();
    final db = await _database;
    try {
      await db.transaction((txn) async {
        await txn.execute(
          'DELETE FROM knowledge_fts WHERE source_kind = ? AND source_ref = ?',
          ['web', normalized],
        );
        await txn.delete(
          'indexed_web_sources',
          where: 'url = ?',
          whereArgs: [normalized],
        );
        final batch = txn.batch();
        for (final body in chunks) {
          batch.insert('knowledge_fts', {
            'body': body,
            'chunk_id': _uuid.v4(),
            'source_kind': 'web',
            'source_ref': normalized,
          });
        }
        await batch.commit(noResult: true);
        await txn.insert('indexed_web_sources', {
          'id': id,
          'url': normalized,
          'title': title,
          'indexed_at': DateTime.now().millisecondsSinceEpoch,
          'chunk_count': chunks.length,
        });
      });
    } catch (e, st) {
      debugPrint('indexKnowledgeUrl db: $e\n$st');
      return KnowledgeIndexResult(
        success: false,
        message: 'Błąd zapisu indeksu: $e',
      );
    }
    return KnowledgeIndexResult(success: true, chunkCount: chunks.length);
  }

  Future<void> deleteIndexedWebSource(String id) async {
    final db = await _database;
    final rows = await db.query(
      'indexed_web_sources',
      columns: ['url'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final url = rows.first['url'] as String;
    await db.transaction((txn) async {
      await txn.execute(
        'DELETE FROM knowledge_fts WHERE source_kind = ? AND source_ref = ?',
        ['web', url],
      );
      await txn.delete('indexed_web_sources', where: 'id = ?', whereArgs: [id]);
    });
  }

  String? _normalizeKnowledgeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || !u.hasScheme || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return u.toString();
  }

  /// Usuwa naprawę i powiązane sesje / pomiary / czat.
  Future<void> deleteRepair(String id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('measurement_logs', where: 'repair_id = ?', whereArgs: [id]);
      await txn.delete('diagnostic_sessions', where: 'repair_id = ?', whereArgs: [id]);
      await txn.delete('diagnostic_chat', where: 'repair_id = ?', whereArgs: [id]);
      await txn.delete('repairs', where: 'id = ?', whereArgs: [id]);
    });
  }

  static String? _ftsQueryFromUserInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final re = RegExp(r'[\w\u0100-\u017F]+', unicode: true);
    final words = re
        .allMatches(trimmed)
        .map((m) => m.group(0)!)
        .where((w) => w.length >= 2)
        .take(12)
        .toList();
    if (words.isEmpty) return null;
    return words.map((w) {
      final escaped = w.replaceAll('"', '""');
      return '"$escaped"';
    }).join(' AND ');
  }
}
