import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

class UsbRecord {
  final String id;
  final String deviceName;
  final String devicePath;
  final int deviceSize;
  final String deviceSerial;
  final String isoName;
  final String isoPath;
  final String status;
  final String createdAt;
  final String? completedAt;

  const UsbRecord({
    required this.id,
    required this.deviceName,
    required this.devicePath,
    required this.deviceSize,
    this.deviceSerial = '',
    required this.isoName,
    this.isoPath = '',
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'device_name': deviceName,
    'device_path': devicePath,
    'device_size': deviceSize,
    'device_serial': deviceSerial,
    'iso_name': isoName,
    'iso_path': isoPath,
    'status': status,
    'created_at': createdAt,
    'completed_at': completedAt,
  };

  factory UsbRecord.fromMap(Map<String, dynamic> map) {
    return UsbRecord(
      id: map['id'] as String,
      deviceName: map['device_name'] as String,
      devicePath: map['device_path'] as String,
      deviceSize: map['device_size'] as int,
      deviceSerial: map['device_serial'] as String? ?? '',
      isoName: map['iso_name'] as String,
      isoPath: map['iso_path'] as String? ?? '',
      status: map['status'] as String,
      createdAt: map['created_at'] as String,
      completedAt: map['completed_at'] as String?,
    );
  }
}

class DatabaseService {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, 'windeploy_studio.db');

    return await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usb_history (
        id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        device_path TEXT NOT NULL,
        device_size INTEGER NOT NULL,
        device_serial TEXT DEFAULT '',
        iso_name TEXT NOT NULL,
        iso_path TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
  }

  Future<void> insertUsbHistory(UsbRecord record) async {
    final db = await database;
    await db.insert(
      'usb_history',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUsbStatus(
    String id,
    String status, {
    String? completedAt,
  }) async {
    final db = await database;
    final values = {'status': status};
    if (completedAt != null) {
      values['completed_at'] = completedAt;
    }
    await db.update('usb_history', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<UsbRecord>> getUsbHistory({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'usb_history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(UsbRecord.fromMap).toList();
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
