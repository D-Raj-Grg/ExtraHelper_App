import 'dart:math' as math;

import 'package:zxing2/qrcode.dart';

import 'coupon_status.dart' show couponQrPayload;

/// Where the code and the QR sit on a flyer picture, as fractions of the
/// picture with the origin top-left. Same shape, names and defaults as the
/// web's `FlyerPlacement` (`lib/flyer.ts`), so a design saved on either side
/// opens on the other.
class FlyerBox {
  const FlyerBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;

  /// Fraction of the picture's width / height.
  final double w;
  final double h;

  FlyerBox copyWith({double? x, double? y, double? w, double? h}) =>
      FlyerBox(x: x ?? this.x, y: y ?? this.y, w: w ?? this.w, h: h ?? this.h);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

class FlyerQrBox {
  const FlyerQrBox({required this.x, required this.y, required this.s});

  final double x;
  final double y;

  /// The square's side as a fraction of the picture's **width**.
  final double s;

  FlyerQrBox copyWith({double? x, double? y, double? s}) =>
      FlyerQrBox(x: x ?? this.x, y: y ?? this.y, s: s ?? this.s);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 's': s};
}

class FlyerPlacement {
  const FlyerPlacement({
    required this.code,
    required this.qr,
    this.codeColor = '#7a2a12',
    this.qrColor = '#000000',
    this.codeScale = 0.85,
    this.qrInset = 0.06,
  });

  final FlyerBox code;
  final FlyerQrBox qr;
  final String codeColor;
  final String qrColor;

  /// 0.3 – 1: how much of the code box's height the letters fill.
  final double codeScale;

  /// 0 – 0.15: blank margin inside the QR square.
  final double qrInset;

  FlyerPlacement copyWith({
    FlyerBox? code,
    FlyerQrBox? qr,
    String? codeColor,
    String? qrColor,
    double? codeScale,
    double? qrInset,
  }) => FlyerPlacement(
    code: code ?? this.code,
    qr: qr ?? this.qr,
    codeColor: codeColor ?? this.codeColor,
    qrColor: qrColor ?? this.qrColor,
    codeScale: codeScale ?? this.codeScale,
    qrInset: qrInset ?? this.qrInset,
  );

  Map<String, dynamic> toJson() => {
    'code': code.toJson(),
    'qr': qr.toJson(),
    'codeColor': codeColor,
    'qrColor': qrColor,
    'codeScale': codeScale,
    'qrInset': qrInset,
  };
}

/// The web's starting layout for a freshly uploaded picture.
const defaultPlacement = FlyerPlacement(
  code: FlyerBox(x: 0.3, y: 0.756, w: 0.4, h: 0.032),
  qr: FlyerQrBox(x: 0.784, y: 0.703, s: 0.126),
);

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// The stored jsonb as a placement, or null when any field is missing or
/// malformed (the caller falls back to [defaultPlacement], as the web does).
FlyerPlacement? parsePlacement(Object? raw) {
  if (raw is! Map) return null;
  final code = raw['code'];
  final qr = raw['qr'];
  if (code is! Map || qr is! Map) return null;
  final cx = _num(code['x']);
  final cy = _num(code['y']);
  final cw = _num(code['w']);
  final ch = _num(code['h']);
  final qx = _num(qr['x']);
  final qy = _num(qr['y']);
  final qs = _num(qr['s']);
  final scale = _num(raw['codeScale']);
  final inset = _num(raw['qrInset']);
  final codeColor = raw['codeColor'];
  final qrColor = raw['qrColor'];
  if ([cx, cy, cw, ch, qx, qy, qs, scale, inset].contains(null)) return null;
  if (codeColor is! String || !_hex.hasMatch(codeColor)) return null;
  if (qrColor is! String || !_hex.hasMatch(qrColor)) return null;
  return FlyerPlacement(
    code: FlyerBox(x: cx!, y: cy!, w: cw!, h: ch!),
    qr: FlyerQrBox(x: qx!, y: qy!, s: qs!),
    codeColor: codeColor,
    qrColor: qrColor,
    codeScale: scale!,
    qrInset: inset!,
  );
}

double _clamp(double v, double lo, double hi) =>
    hi < lo ? lo : math.min(math.max(v, lo), hi);

// --- Editor geometry (clamps copied from the web's `flyer-editor.tsx`) ------

/// [ratio] is picture height ÷ width.
FlyerPlacement moveCode(FlyerPlacement p, double dx, double dy) {
  final c = p.code;
  return p.copyWith(
    code: c.copyWith(
      x: _clamp(c.x + dx, 0, 1 - c.w),
      y: _clamp(c.y + dy, 0, 1 - c.h),
    ),
  );
}

FlyerPlacement resizeCode(FlyerPlacement p, double dw, double dh) {
  final c = p.code;
  return p.copyWith(
    code: c.copyWith(
      w: _clamp(c.w + dw, 0.05, 1 - c.x),
      h: _clamp(c.h + dh, 0.01, 1 - c.y),
    ),
  );
}

FlyerPlacement moveQr(FlyerPlacement p, double dx, double dy, double ratio) {
  final q = p.qr;
  return p.copyWith(
    qr: q.copyWith(
      x: _clamp(q.x + dx, 0, 1 - q.s),
      y: _clamp(q.y + dy, 0, 1 - q.s * ratio),
    ),
  );
}

/// The side follows whichever of the horizontal drag and the (width-scaled)
/// vertical drag is larger, so a diagonal pull feels natural.
FlyerPlacement resizeQr(FlyerPlacement p, double dx, double dy, double ratio) {
  final q = p.qr;
  final delta = dx.abs() >= (dy / ratio).abs() ? dx : dy / ratio;
  final maxS = math.min(1 - q.x, (1 - q.y) / ratio);
  return p.copyWith(qr: q.copyWith(s: _clamp(q.s + delta, 0.04, maxS)));
}

// --- What the QR carries ----------------------------------------------------

/// `url`: the storefront link with the code pre-filled (bare code when the
/// app or restaurant has no address); `code`: the bare code.
String flyerPayload({
  required String mode,
  required String origin,
  required String slug,
  required String code,
}) => mode == 'code'
    ? code
    : couponQrPayload(origin: origin, slug: slug, code: code);

/// Dark modules, row by row; empty when the encoder declines.
List<List<bool>> flyerQrGrid(String payload) {
  final matrix = Encoder.encode(payload, ErrorCorrectionLevel.m).matrix;
  if (matrix == null) return const [];
  return [
    for (var y = 0; y < matrix.height; y++)
      [for (var x = 0; x < matrix.width; x++) matrix.get(x, y) == 1],
  ];
}

/// Horizontal runs of dark modules `(row, col, length)` — one rectangle each
/// instead of one per module, which keeps a 500-page PDF small.
List<(int, int, int)> qrRuns(List<List<bool>> grid) {
  final runs = <(int, int, int)>[];
  for (var r = 0; r < grid.length; r++) {
    var c = 0;
    final row = grid[r];
    while (c < row.length) {
      if (!row[c]) {
        c++;
        continue;
      }
      final start = c;
      while (c < row.length && row[c]) {
        c++;
      }
      runs.add((r, start, c - start));
    }
  }
  return runs;
}

/// "Dashain flyers" → `dashain-flyers`; `flyers` when nothing is left.
String slugify(String s) {
  final t = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return t.isEmpty ? 'flyers' : t;
}
