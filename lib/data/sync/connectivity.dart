import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Is there a network at all?
///
/// Deliberately shallow: this answers "is there an interface up", not "can we
/// reach Postgres". The real answer to the second question is the write either
/// succeeding or throwing, which the outbox already handles — a captive-portal
/// wifi that resolves nothing looks online here and fails as a transient, which
/// is exactly right.
class ConnectivityWatcher {
  ConnectivityWatcher({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> isOnline() async =>
      _isOnline(await _connectivity.checkConnectivity());

  /// Fires on every change. Coverage returning is the moment to drain the
  /// outbox, so this is what the sync loop listens to.
  Stream<bool> get onChange =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();
}
