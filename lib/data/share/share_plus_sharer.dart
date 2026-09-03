import 'package:share_plus/share_plus.dart';

import '../../features/pos/bill_export.dart';

/// The app's **only** import of `share_plus`.
///
/// Everything else goes through [FileSharer] and `fileSharerProvider`, so a
/// widget test can record a share instead of dragging a platform channel — and
/// so a plugin whose API has broken across majors before is touched in exactly
/// one file when it does again.
Future<bool> sharePlusSharer(ShareRequest request) async {
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(request.file.path, mimeType: 'image/png')],
      text: request.text,
      // iPad presents the sheet as a popover; without an anchor it lands in the
      // middle of the screen pointing at nothing.
      sharePositionOrigin: request.origin,
    ),
  );
  // `dismissed` is a decision, not a failure — the caller says nothing when
  // someone changes their mind.
  return result.status == ShareResultStatus.success;
}
