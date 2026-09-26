import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/app_notification.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// The order-lifecycle feed: `public.notifications`, written by triggers, plus
/// the per-user read cursor in `notification_reads`.
///
/// RLS lets a row through only with `notifications.view`. Kitchen and
/// inventory roles lack it, and for them every read here is simply empty and
/// the socket delivers nothing — callers gate on the key first so they do not
/// open a channel that can never speak.
class NotificationsRepository {
  const NotificationsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _columns =
      'id, tenant_id, kind, order_id, bill_id, order_type, table_label, '
      'amount_cents, title, body, actor_id, created_at';

  /// The newest [limit] events, newest first.
  Future<List<AppNotification>> latest({int limit = 50}) async {
    try {
      final rows = await _client
          .from('notifications')
          .select(_columns)
          .eq('tenant_id', _tenantId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(AppNotification.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load notifications.");
    }
  }

  /// This user's read cursor, or null when they have never marked anything.
  Future<DateTime?> lastReadAt(String userId) async {
    try {
      final row = await _client
          .from('notification_reads')
          .select('last_read_at')
          .eq('tenant_id', _tenantId)
          .eq('user_id', userId)
          .maybeSingle();
      final raw = row?['last_read_at'] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      // An unknown cursor reads as "everything unread", which is the safe
      // direction for a badge: over-telling beats hiding a ready order.
      return null;
    }
  }

  /// Moves the cursor to the server's now and returns it. The server's clock,
  /// not the phone's — a phone a minute slow would otherwise leave the newest
  /// row unread forever.
  Future<DateTime> markAllRead() async {
    try {
      final at = await _client.rpc<dynamic>(
        'mark_notifications_read',
        params: {'_tenant': _tenantId},
      );
      return DateTime.tryParse('$at') ?? DateTime.now().toUtc();
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't mark those as read.");
    }
  }

  /// INSERTs on `notifications` for this tenant, live.
  ///
  /// The channel opens on listen and closes on cancel. The socket must carry
  /// the user's JWT or RLS drops every event and the feed merely looks "not
  /// live" (CLAUDE.md, Known traps) — so the token is set here, and callers
  /// re-listen when auth changes.
  ///
  /// [onRejoin] fires when the channel re-subscribes after a dropped socket —
  /// realtime does not replay what it missed, so the caller refetches.
  Stream<AppNotification> inserts({void Function()? onRejoin}) {
    RealtimeChannel? channel;
    var joined = false;
    late final StreamController<AppNotification> controller;
    controller = StreamController<AppNotification>(
      onListen: () {
        final token = _client.auth.currentSession?.accessToken;
        if (token != null) _client.realtime.setAuth(token);
        channel = _client
            .channel(
              // A fresh topic per listen. Phoenix routes join and leave by
              // topic, so re-subscribing under the same name after a token
              // refresh could have the old channel's late `leave` tear down
              // the new one.
              'notifications_${_tenantId}_${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'tenant_id',
                value: _tenantId,
              ),
              callback: (payload) {
                if (controller.isClosed) return;
                controller.add(AppNotification.fromJson(payload.newRecord));
              },
            )
            .subscribe((status, _) {
              if (status != RealtimeSubscribeStatus.subscribed) return;
              if (joined) onRejoin?.call();
              joined = true;
            });
      },
      onCancel: () async {
        final c = channel;
        channel = null;
        if (c != null) await _client.removeChannel(c);
        // Single-subscription: once cancelled it is never listened again.
        await controller.close();
      },
    );
    return controller.stream;
  }
}

final notificationsRepositoryProvider =
    Provider.family<NotificationsRepository, String>(
      (ref, tenantId) =>
          NotificationsRepository(ref.watch(supabaseProvider), tenantId),
    );
