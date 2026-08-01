import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../supabase/pos_repository.dart' show PosFailure, PosTransientFailure;
import 'print_models.dart';

/// Turns a claimed job into bytes by asking the web app.
///
/// The ESC/POS builder, the receipt template and every tax line live in
/// TypeScript (`lib/print/docs.ts`), and rendering happens *after* the claim so
/// a ticket amended between queueing and printing comes out amended. Rendering
/// here as well would be a second implementation of the same paper, and the two
/// would drift — the till's copy and the phone's copy have to be identical.
///
/// Authentication is the signed-in user's own access token: no service role, no
/// shared secret. The route reads it, checks membership under RLS, and refuses
/// a token for another restaurant.
class RenderClient {
  RenderClient(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _timeout = Duration(seconds: 15);

  Future<PreparedPrintJob> render(String jobId) async {
    if (!Env.canPrint) {
      throw const PosFailure(
        'This build has no APP_URL, so it cannot render tickets. '
        'Rebuild with APP_URL set to the ExtraHelper web address.',
      );
    }

    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw const PosFailure('Sign in first.');

    final uri = Uri.parse(
      '${Env.appUrl.replaceAll(RegExp(r'/+$'), '')}/api/print/render',
    );

    final http = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await http.postUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(
        utf8.encode(jsonEncode({'jobId': jobId, 'tenantId': _tenantId})),
      );

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const PosTransientFailure('The print server answered oddly.');
      }

      if (response.statusCode >= 400 || decoded['error'] != null) {
        // A 401 or 404 is the server's verdict on this job and will say the
        // same thing next time; it is not worth a retry loop.
        throw PosFailure(
          (decoded['error'] as String?) ??
              'The print server refused (${response.statusCode}).',
        );
      }
      return PreparedPrintJob.fromJson(decoded);
      // Covers `PosTransientFailure` too — it is a subtype.
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the print server to build the ticket.",
      );
    } finally {
      http.close(force: true);
    }
  }
}
