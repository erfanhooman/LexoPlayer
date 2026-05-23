/// Data models for the remote dictionary manifest.
///
/// The application fetches a `manifest.json` from a remote server that
/// describes all available dictionaries (both monolingual and bilingual).
/// These models provide typed Dart representations of that JSON structure.
library;

/// Categorises a dictionary as either monolingual (target-to-target) or
/// bilingual (target-to-native).
enum DictionaryType {
  /// Target language definitions (e.g. English-English, German-German).
  monolingual,

  /// Target-to-native translations (e.g. English-Persian, German-English).
  bilingual,
}

/// A single dictionary entry from the remote manifest.
///
/// Each entry describes one downloadable dictionary pack with its metadata,
/// download URL, file size, and integrity checksum.
class DictionaryEntry {
  /// Unique identifier used for storage paths and preference keys.
  /// Example: `"eng_oxford"`, `"eng_to_pes"`.
  final String id;

  /// ISO 639-1 code of the source (target) language.
  /// Example: `"en"`, `"de"`.
  final String sourceLanguage;

  /// ISO 639-1 code of the native translation language.
  /// Only present for [DictionaryType.bilingual] entries.
  /// Example: `"fa"` (Persian), `"en"` (English).
  final String? nativeLanguage;

  /// Human-readable name shown in the UI.
  /// Example: `"Oxford Advanced Dictionary"`.
  final String displayName;

  /// Short description of the dictionary's contents.
  final String description;

  /// Full URL to the downloadable `.zip` archive.
  final String remoteUrl;

  /// Expected file size of the `.zip` download in bytes.
  final int fileSizeBytes;

  /// MD5 hex-digest of the `.zip` file for integrity verification.
  final String md5Checksum;

  /// Whether this is a monolingual or bilingual dictionary.
  final DictionaryType type;

  const DictionaryEntry({
    required this.id,
    required this.sourceLanguage,
    this.nativeLanguage,
    required this.displayName,
    required this.description,
    required this.remoteUrl,
    required this.fileSizeBytes,
    required this.md5Checksum,
    required this.type,
  });

  /// Parses a single dictionary entry from a JSON map.
  ///
  /// The [type] parameter determines whether `native_language` is expected.
  factory DictionaryEntry.fromJson(
    Map<String, dynamic> json,
    DictionaryType type,
  ) {
    return DictionaryEntry(
      id: json['id'] as String,
      sourceLanguage: json['source_language'] as String,
      nativeLanguage: json['native_language'] as String?,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      remoteUrl: json['remote_url'] as String,
      fileSizeBytes: json['file_size_bytes'] as int,
      md5Checksum: json['md5_checksum'] as String,
      type: type,
    );
  }

  /// Serialises this entry back to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_language': sourceLanguage,
      if (nativeLanguage != null) 'native_language': nativeLanguage,
      'display_name': displayName,
      'description': description,
      'remote_url': remoteUrl,
      'file_size_bytes': fileSizeBytes,
      'md5_checksum': md5Checksum,
    };
  }

  /// Returns a human-readable file size string (e.g. "43.0 MB").
  String get formattedFileSize {
    if (fileSizeBytes >= 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (fileSizeBytes >= 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (fileSizeBytes >= 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$fileSizeBytes B';
  }

  @override
  String toString() => 'DictionaryEntry($id: $displayName [$type])';
}

/// The top-level manifest structure returned by the remote server.
///
/// Contains metadata about the manifest itself plus two categorised lists
/// of available dictionaries.
class ManifestData {
  /// ISO 8601 timestamp of the last manifest update.
  final DateTime lastUpdated;

  /// Manifest schema version for forward compatibility.
  final int version;

  /// Available monolingual (target-to-target) dictionaries.
  final List<DictionaryEntry> monolingual;

  /// Available bilingual (target-to-native) dictionaries.
  final List<DictionaryEntry> bilingual;

  const ManifestData({
    required this.lastUpdated,
    required this.version,
    required this.monolingual,
    required this.bilingual,
  });

  /// All dictionaries combined into a single flat list.
  List<DictionaryEntry> get all => [...monolingual, ...bilingual];

  /// Finds a dictionary entry by its [id], or `null` if not found.
  DictionaryEntry? findById(String id) {
    for (final entry in all) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Parses the full manifest from a decoded JSON map.
  factory ManifestData.fromJson(Map<String, dynamic> json) {
    final dictionaries = json['dictionaries'] as Map<String, dynamic>;

    final monoList = (dictionaries['monolingual'] as List<dynamic>? ?? [])
        .map((e) => DictionaryEntry.fromJson(
              e as Map<String, dynamic>,
              DictionaryType.monolingual,
            ))
        .toList();

    final biList = (dictionaries['bilingual'] as List<dynamic>? ?? [])
        .map((e) => DictionaryEntry.fromJson(
              e as Map<String, dynamic>,
              DictionaryType.bilingual,
            ))
        .toList();

    return ManifestData(
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      version: json['version'] as int,
      monolingual: monoList,
      bilingual: biList,
    );
  }

  /// Serialises this manifest back to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'last_updated': lastUpdated.toIso8601String(),
      'version': version,
      'dictionaries': {
        'monolingual': monolingual.map((e) => e.toJson()).toList(),
        'bilingual': bilingual.map((e) => e.toJson()).toList(),
      },
    };
  }
}
