import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A receipt photo ready to upload.
class ReceiptPhoto {
  const ReceiptPhoto({
    required this.bytes,
    required this.contentType,
    required this.ext,
  });

  final List<int> bytes;
  final String contentType;
  final String ext;
}

const _types = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Camera or gallery, then a photo small enough to send over a poor
/// connection. Downscaled on the phone: a receipt needs to be readable, not
/// print-quality, and the bucket refuses anything over 5 MB.
Future<ReceiptPhoto?> pickReceiptPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
          ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 70,
    requestFullMetadata: false,
  );
  if (picked == null) return null;

  final name = picked.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  var ext = dot >= 0 ? name.substring(dot + 1) : 'jpg';
  if (!_types.containsKey(ext)) ext = 'jpg';
  if (ext == 'jpeg') ext = 'jpg';
  final bytes = await picked.readAsBytes();
  return ReceiptPhoto(
    bytes: bytes,
    contentType: picked.mimeType ?? _types[ext]!,
    ext: ext,
  );
}

/// Full-screen look at a signed receipt URL, pinch to zoom.
Future<void> showReceiptViewer(
  BuildContext context,
  String url,
) => showDialog<void>(
  context: context,
  builder: (dialog) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(dialog).pop(),
        ),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Couldn't load the photo. Check the connection and try again.",
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
