import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_board_research_result.dart';
import '../models/diagnostic_chat_snapshot.dart';
import '../models/diagnostic_session_state.dart';
import '../models/measurement_log_entry.dart';
import '../models/repair_project.dart';
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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE repairs (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            board_id TEXT,
            device_label TEXT,
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
      columns: ['id', 'created_at', 'board_id', 'device_label', 'payload'],
      orderBy: 'created_at DESC',
    );
    final out = <RepairSummary>[];
    for (final r in rows) {
      final id = r['id'] as String;
      final created = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int);
      var boardId = r['board_id'] as String?;
      var label = r['device_label'] as String?;
      if (boardId == null || boardId.isEmpty) {
        try {
          final project = RepairProject.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          );
          boardId = project.boardModelCode;
          label = project.displayTitle;
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
}
