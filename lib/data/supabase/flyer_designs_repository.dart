import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/coupons/flyer_placement.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

const flyerTemplateBucket = 'flyer-templates';

/// The bucket takes JPEG or PNG up to 5 MB — the web enforces the same.
const flyerTemplateMaxBytes = 5 * 1024 * 1024;

/// One row of `list_flyer_designs`: a picture plus where the code and QR go.
class FlyerDesign {
  const FlyerDesign({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.width,
    required this.height,
    required this.placement,
    required this.mode,
    this.linkBase,
  });

  final String id;
  final String name;
  final String imagePath;

  /// Pixels of the stored picture.
  final int width;
  final int height;
  final FlyerPlacement placement;

  /// `url` (storefront link) or `code` (bare code).
  final String mode;
  final String? linkBase;

  double get ratio => width == 0 ? 1 : height / width;

  static FlyerDesign fromRow(Map<String, dynamic> row) => FlyerDesign(
    id: row['id'] as String,
    name: (row['name'] as String? ?? '').trim(),
    imagePath: row['image_path'] as String? ?? '',
    width: _int(row['width']),
    height: _int(row['height']),
    // A stored placement that fails validation falls back, as on the web.
    placement: parsePlacement(row['placement']) ?? defaultPlacement,
    mode: row['mode'] == 'code' ? 'code' : 'url',
    linkBase: (row['link_base'] as String?)?.trim().isEmpty ?? true
        ? null
        : (row['link_base'] as String).trim(),
  );
}

int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

/// A picture the user just picked, before it is stored.
class FlyerPicture {
  const FlyerPicture({
    required this.bytes,
    required this.width,
    required this.height,
    required this.isPng,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final bool isPng;
}

/// Saved designs and their pictures: `list_flyer_designs` (view),
/// `save_flyer_design` / `delete_flyer_design` (manage) and the private
/// `flyer-templates` bucket — the same ones the web's Flyers studio uses.
class FlyerDesignsRepository {
  const FlyerDesignsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<List<FlyerDesign>> list() => _guard(() async {
    final res = await _client.rpc<dynamic>(
      'list_flyer_designs',
      params: {'_tenant': _tenantId},
    );
    return (res as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FlyerDesign.fromRow)
        .toList();
  }, "Couldn't load the designs.");

  /// Short-lived (1 h) links for thumbnails, keyed by storage path.
  Future<Map<String, String>> thumbnails(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final signed = await _client.storage
          .from(flyerTemplateBucket)
          .createSignedUrlsResult(paths, 3600);
      return {
        for (final s in signed)
          if (s is SignedUrlSuccess) s.path: s.signedUrl,
      };
    } catch (_) {
      return const {}; // tiles fall back to an icon
    }
  }

  /// The stored picture, as uploaded. The bucket is private; the user's own
  /// session reads it under the `coupons.view` storage policy.
  Future<Uint8List> template(String imagePath) => _guard(
    () => _client.storage.from(flyerTemplateBucket).download(imagePath),
    "Couldn't load the flyer picture.",
  );

  /// Create (id null) or edit. [picture] null keeps the stored picture on an
  /// edit. Mirrors the web's `saveFlyerDesign`: upload under a fresh name,
  /// save the row, then remove whichever picture is no longer referenced —
  /// so a failure part-way leaves the previous design working. [batchId]
  /// points that run at the design.
  Future<String> save({
    String? id,
    required String name,
    FlyerPicture? picture,
    String? previousPath,
    required int width,
    required int height,
    required FlyerPlacement placement,
    required String mode,
    String? linkBase,
    String? batchId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw const PosFailure('Name the design (up to 80 characters).');
    }
    if (width < 1 || height < 1) {
      throw const PosFailure("Couldn't read that picture's size.");
    }
    if (id == null && picture == null) {
      throw const PosFailure('Pick a picture first.');
    }
    if (picture != null && picture.bytes.length > flyerTemplateMaxBytes) {
      throw const PosFailure('That picture is over 5 MB. Pick a smaller one.');
    }

    String? uploaded;
    try {
      if (picture != null) {
        final ext = picture.isPng ? 'png' : 'jpg';
        uploaded = '$_tenantId/${_uuid()}.$ext';
        await _client.storage
            .from(flyerTemplateBucket)
            .uploadBinary(
              uploaded,
              picture.bytes,
              fileOptions: FileOptions(
                contentType: picture.isPng ? 'image/png' : 'image/jpeg',
              ),
            );
      }
      final res = await _client.rpc<dynamic>(
        'save_flyer_design',
        params: {
          '_tenant': _tenantId,
          '_id': id,
          '_name': trimmed,
          '_image_path': uploaded,
          '_width': width,
          '_height': height,
          '_placement': placement.toJson(),
          '_mode': mode,
          '_link_base': mode == 'url' ? (linkBase ?? '') : '',
          '_batch': batchId,
        },
      );
      if (uploaded != null && previousPath != null) {
        await _removeQuietly(previousPath);
      }
      return res is String ? res : id ?? '';
    } on PostgrestException catch (e) {
      if (uploaded != null) await _removeQuietly(uploaded);
      throw PosFailure(_friendly(e.message));
    } on StorageException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      if (uploaded != null) await _removeQuietly(uploaded);
      throw const PosTransientFailure("Couldn't save the design.");
    }
  }

  /// Runs on the design keep existing; they just lose their design.
  Future<void> delete(String id) async {
    try {
      final path = await _client.rpc<dynamic>(
        'delete_flyer_design',
        params: {'_id': id},
      );
      if (path is String && path.isNotEmpty) await _removeQuietly(path);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't delete the design.");
    }
  }

  Future<void> _removeQuietly(String path) async {
    try {
      await _client.storage.from(flyerTemplateBucket).remove([path]);
    } catch (_) {
      // An orphaned picture is harmless; the save already succeeded or failed.
    }
  }

  Future<T> _guard<T>(Future<T> Function() work, String fallback) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } on StorageException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw PosTransientFailure(fallback);
    }
  }

  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('permission denied') ||
        m.contains('not authorized') ||
        m.contains('row-level security') ||
        m.contains('not permitted')) {
      return "You don't have permission to do that.";
    }
    return message.split('\n').first;
  }
}

/// A v4 UUID without a package: the path only needs to be unique.
String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

final flyerDesignsRepositoryProvider =
    Provider.family<FlyerDesignsRepository, String>(
      (ref, tenantId) =>
          FlyerDesignsRepository(ref.watch(supabaseProvider), tenantId),
    );
