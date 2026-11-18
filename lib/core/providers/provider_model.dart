import 'package:cloud_firestore/cloud_firestore.dart';

/// Content types a provider can deliver.
enum ContentType { movie, series, episode }

/// Manifest describing a single authorised Stremio-compatible provider.
///
/// This model mirrors the subset of the Stremio add-on manifest that
/// CinemaHub actually consumes — `id`, `version`, `resources`, `types`,
/// `name`, `description`, `behaviorHints`, and `catalogs`. The full manifest
/// is fetched by [StremioAdapter] over HTTP.
class ProviderModel {
  const ProviderModel({
    required this.id,
    required this.name,
    required this.version,
    required this.types,
    required this.resources,
    this.catalogs = const [],
    this.behaviorHints,
    this.enabled = true,
    this.priority = 100,
    this.manifestUrl,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id, also the Stremio add-on id.
  final String id;
  final String name;
  final String version;
  final List<ContentType> types;
  final List<String> resources;
  final List<Map<String, dynamic>> catalogs;
  final Map<String, dynamic>? behaviorHints;
  final bool enabled;
  final int priority;
  final String? manifestUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether this provider can deliver [type].
  bool supports(ContentType type) => types.contains(type);

  /// Whether this provider advertises a `catalog` resource for [type].
  bool hasCatalog(ContentType type) =>
      resources.contains('catalog') &&
      catalogs.any((c) => (c['type'] as String?) == type.name);

  /// Whether this provider is enabled and can be used for playback.
  bool get usable => enabled;

  /// Build from a Firestore document.
  factory ProviderModel.fromFirestore(String id, Map<String, dynamic> data) {
    final types =
        (data['types'] as List?)
            ?.map((t) => ContentType.values.firstWhere(
                  (e) => e.name == t,
                  orElse: () => ContentType.movie,
                ))
            .toList() ??
        [ContentType.movie];

    final resources =
        (data['resources'] as List?)?.cast<String>() ?? ['stream'];

    final catalogs =
        (data['catalogs'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ProviderModel(
      id: id,
      name: data['name'] as String? ?? id,
      version: data['version'] as String? ?? '1.0.0',
      types: types,
      resources: resources,
      catalogs: catalogs,
      behaviorHints: (data['behaviorHints'] as Map?)?.cast(),
      enabled: data['enabled'] as bool? ?? true,
      priority: data['priority'] as int? ?? 100,
      manifestUrl: data['manifestUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Serialise back to Firestore.
  Map<String, dynamic> toFirestore() => {
    'name': name,
    'version': version,
    'types': types.map((t) => t.name).toList(),
    'resources': resources,
    'catalogs': catalogs,
    'behaviorHints': behaviorHints,
    'enabled': enabled,
    'priority': priority,
    'manifestUrl': manifestUrl,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}