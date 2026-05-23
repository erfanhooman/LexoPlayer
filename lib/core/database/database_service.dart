import 'dart:io';

// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: unused_import — ensures native SQLite libs are bundled on all platforms.
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Cross-platform SQLite database service.
///
/// Handles platform-specific initialization (FFI for desktop, default for
/// mobile) and provides cached [Database] accessors keyed by name or path.
///
/// Supports runtime database switching via [getDatabaseByPath] and
/// [closeDatabase] for the dynamic dictionary selection system.
class DatabaseService {
  /// Internal cache of open [Database] instances, keyed by cache key
  /// (either a filename or absolute path).
  final Map<String, Database> _databases = {};

  /// Initializes the SQLite backend for the current platform.
  ///
  /// On desktop targets (Windows, Linux, macOS) this switches to the FFI-based
  /// database factory. On mobile (Android / iOS) the default sqflite factory is
  /// used and no extra setup is required.
  ///
  /// **Must** be called once before any database access, typically in `main()`.
  static Future<void> initialize() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// Returns a cached, open [Database] for the given [dbName].
  ///
  /// The database is looked up in the application documents directory.
  /// Use [getDatabaseByPath] for dictionaries stored in custom locations.
  Future<Database> getDatabase(String dbName) async {
    if (_databases.containsKey(dbName) && _databases[dbName]!.isOpen) {
      return _databases[dbName]!;
    }

    final path = await getDatabasePath(dbName);
    final db = await openDatabase(path, readOnly: true);
    _databases[dbName] = db;
    return db;
  }

  /// Returns a cached, open [Database] at the given [absolutePath].
  ///
  /// Unlike [getDatabase], this accepts a full filesystem path, making it
  /// suitable for dictionaries stored in the `dicts/` subdirectory.
  /// The path is used as both the open target and the cache key.
  Future<Database> getDatabaseByPath(String absolutePath) async {
    if (_databases.containsKey(absolutePath) &&
        _databases[absolutePath]!.isOpen) {
      return _databases[absolutePath]!;
    }

    final db = await openDatabase(absolutePath, readOnly: true);
    _databases[absolutePath] = db;
    return db;
  }

  /// Closes and removes a single cached [Database] identified by [key].
  ///
  /// The [key] can be either a filename (for [getDatabase]) or an absolute
  /// path (for [getDatabaseByPath]). This enables hot-swapping dictionaries
  /// without restarting the app.
  ///
  /// No-op if [key] is not in the cache.
  Future<void> closeDatabase(String key) async {
    final db = _databases.remove(key);
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// Resolves the full filesystem path for a database named [dbName]
  /// in the application documents directory.
  Future<String> getDatabasePath(String dbName) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, dbName);
  }

  /// Closes every cached [Database] and clears the cache.
  ///
  /// Call this during app shutdown or when the databases are no longer needed.
  Future<void> closeAll() async {
    for (final db in _databases.values) {
      if (db.isOpen) {
        await db.close();
      }
    }
    _databases.clear();
  }
}
