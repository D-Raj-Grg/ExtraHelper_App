import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/region_options.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// When the trading day may start, and nothing else.
///
/// The same seven options the web's Settings page offers, because the value is
/// validated against that list on the server side too — the phone must not be
/// able to set a cutoff the browser would refuse. The column's own
/// `check (day_cutoff_minutes >= 0 and < 720)` is the backstop.
const dayCutoffOptions = <int, String>{
  0: 'Midnight',
  60: '1:00 am',
  120: '2:00 am',
  180: '3:00 am',
  240: '4:00 am',
  300: '5:00 am',
  360: '6:00 am',
};

/// Currencies this app offers, and the zones it offers with them.
///
/// One list per client, shared with the onboarding form — see
/// `core/region_options.dart`. The column is free text and the server applies
/// no allow-list of its own, so this list *is* the contract: a code the browser
/// cannot pick must not be reachable from the phone either, and a restaurant
/// created on a phone must be configurable the same way as one created at a
/// desk.
const settingsCurrencies = kCurrencyOptions;

/// Not the full IANA set on purpose: this is a dropdown someone scrolls with a
/// thumb, and a wrong zone silently moves every trading day boundary.
const settingsTimezones = kTimezoneOptions;

/// How payments are taken. Real gateways (eSewa, Khalti, Stripe) will register
/// under their own keys; until then the choice is a sandbox or a manual
/// terminal, and the server rejects anything else.
const paymentGateways = <String, String>{
  'sandbox': 'Sandbox (test)',
  'manual': 'Manual / cash-terminal',
};

/// Said before the day cutoff moves, wherever it is offered — the day-close
/// sheet and the settings screen both raise this, and they must not describe
/// the consequence differently.
const dayCutoffRetroWarning =
    'This re-buckets every past day, on this phone and on the web. Yesterday '
    'may gain or lose the orders either side of the new boundary.';

/// One line of `tenant_settings.tax_rules`.
///
/// Semantics come from the web's copy: an exclusive rule is added on top of the
/// subtotal plus service charge; an inclusive rule is already in the price. The
/// arithmetic itself lives in Postgres — this is only how the rule is described.
class TaxRule {
  const TaxRule({
    required this.name,
    required this.rate,
    required this.inclusive,
  });

  final String name;

  /// A percentage, 0..100. Not a fraction.
  final double rate;
  final bool inclusive;

  static TaxRule fromJson(Map<String, dynamic> json) => TaxRule(
    name: (json['name'] as String? ?? '').trim(),
    rate: _num(json['rate']),
    inclusive: json['inclusive'] == true,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rate': rate,
    'inclusive': inclusive,
  };

  TaxRule copyWith({String? name, double? rate, bool? inclusive}) => TaxRule(
    name: name ?? this.name,
    rate: rate ?? this.rate,
    inclusive: inclusive ?? this.inclusive,
  );
}

/// `tenant_settings.receipt_template`.
///
/// Two parallel representations, as on the web: `*_url` is what a screen shows,
/// [printAssets] is what paper gets. A thermal head cannot fetch a URL, and a
/// phone should not be asked to render a packed 1-bit bitmap.
class ReceiptTemplate {
  const ReceiptTemplate({
    this.header = '',
    this.footer = '',
    this.terms = '',
    this.qrCaption = '',
    this.logoUrl,
    this.qrUrl,
    this.printAssets = const {},
  });

  final String header;
  final String footer;
  final String terms;
  final String qrCaption;
  final String? logoUrl;
  final String? qrUrl;

  /// The baked bitmaps, kept **opaque**: `{"logo": {"384": {w,h,data}, …}}`.
  ///
  /// Read whole and written whole, one `kind` at a time. `merge_receipt_template`
  /// merges shallowly, so a patch carrying half of this map deletes the other
  /// half — see [SettingsRepository.attachBrandImage].
  final Map<String, dynamic> printAssets;

  Map<String, dynamic>? assetsFor(String kind) =>
      printAssets[kind] as Map<String, dynamic>?;

  /// Which roll widths this image is prepared for, as dot counts. Keys only —
  /// the values are never parsed here.
  Set<String> widthsFor(String kind) =>
      (assetsFor(kind)?.keys.toSet() ?? const <String>{});

  static ReceiptTemplate fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReceiptTemplate();
    final assets = json['print_assets'];
    return ReceiptTemplate(
      header: json['header'] as String? ?? '',
      footer: json['footer'] as String? ?? '',
      terms: json['terms'] as String? ?? '',
      qrCaption: json['qr_caption'] as String? ?? '',
      logoUrl: _url(json['logo_url']),
      qrUrl: _url(json['qr_url']),
      printAssets: assets is Map
          ? Map<String, dynamic>.from(assets)
          : const <String, dynamic>{},
    );
  }
}

/// One row of `tenant_settings`, with the column defaults applied here so no
/// screen has to know what a missing row means.
class TenantSettings {
  const TenantSettings({
    this.currency = 'USD',
    this.timezone = 'UTC',
    this.dayCutoffMinutes = 0,
    this.serviceCharge = 0,
    this.packagingFee = 0,
    this.taxRules = const [],
    this.receipt = const ReceiptTemplate(),
    this.blockNegativeStock = false,
    this.qrAutoFire = true,
    this.paymentGateway = 'sandbox',
    this.printingMode = 'local',
  });

  final String currency;
  final String timezone;
  final int dayCutoffMinutes;

  /// A **percentage**, `numeric(5,2)`. Applied to dine-in bills.
  final double serviceCharge;

  /// A flat fee in **currency units, not cents** — `numeric(10,2)`, unlike every
  /// other money value in this app. Never route it through `money()`: that
  /// expects cents and would divide by a hundred a second time.
  final double packagingFee;

  final List<TaxRule> taxRules;
  final ReceiptTemplate receipt;
  final bool blockNegativeStock;
  final bool qrAutoFire;
  final String paymentGateway;

  /// `local` (a browser driving printers through QZ Tray) or `cloud` (the
  /// headless agent). Read-only here — the phone is neither.
  final String printingMode;

  static TenantSettings fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TenantSettings();
    final rules = json['tax_rules'];
    return TenantSettings(
      currency: json['currency'] as String? ?? 'USD',
      timezone: json['timezone'] as String? ?? 'UTC',
      dayCutoffMinutes: _int(json['day_cutoff_minutes']),
      serviceCharge: _num(json['service_charge']),
      packagingFee: _num(json['packaging_fee']),
      taxRules: rules is List
          ? rules
                .whereType<Map<String, dynamic>>()
                .map(TaxRule.fromJson)
                .toList()
          : const <TaxRule>[],
      receipt: ReceiptTemplate.fromJson(
        json['receipt_template'] is Map<String, dynamic>
            ? json['receipt_template'] as Map<String, dynamic>
            : null,
      ),
      blockNegativeStock: json['block_negative_stock'] == true,
      // Defaults true in the column, so a missing key means on, not off.
      qrAutoFire: json['qr_auto_fire'] != false,
      paymentGateway: json['payment_gateway'] as String? ?? 'sandbox',
      printingMode: json['printing_mode'] as String? ?? 'local',
    );
  }
}

/// PostgREST hands `numeric` back as a string often enough that a bare cast
/// throws in production and never in a test written against a hand-typed map.
double _num(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

int _int(Object? value) => switch (value) {
  int n => n,
  num n => n.round(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

/// An empty string in `logo_url` means "no logo", not "a logo at the empty URL".
String? _url(Object? value) {
  final raw = value as String?;
  if (raw == null || raw.trim().isEmpty) return null;
  return raw;
}

/// Everything under `tenant_settings`, plus the restaurant's own name.
///
/// Mirrors the web's `app/(app)/settings/actions.ts`. Split into three writes
/// rather than the web's single fused one: the browser can hold twenty fields
/// behind one Save button, a phone shows them one screen at a time, and a
/// screen that saves fields the user cannot see is a screen that overwrites
/// someone else's change.
///
/// **Every table write reads its result back with `.select()`.** RLS does not
/// raise on an update that matches zero rows, so without the read-back a
/// refused write returns success and the UI lies about it.
class SettingsRepository {
  const SettingsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// Move the boundary the trading day turns over on.
  ///
  /// A plain table update, not an RPC, because `tenant_settings_owner_write`
  /// already restricts writes to owners and managers — the same set the UI
  /// gates on. RLS is the boundary here, exactly as it is for every other
  /// write in this app.
  ///
  /// **Retroactive.** Every past day re-buckets, on both clients and on the
  /// POS, because `tenant_day_start` reads this column. The caller confirms
  /// before calling.
  Future<void> setDayCutoff(int minutes) async {
    if (!dayCutoffOptions.containsKey(minutes)) {
      throw const PosFailure('That is not a day-start time we offer.');
    }
    try {
      // `.select()` so a blocked write is an error rather than a lie. RLS does
      // not raise on an update that matches nothing — it silently affects zero
      // rows — so without reading the result back, someone without the role
      // would be told the day had moved when it had not.
      final changed = await _client
          .from('tenant_settings')
          .update({'day_cutoff_minutes': minutes})
          .eq('tenant_id', _tenantId)
          .select('tenant_id');

      if (changed.isEmpty) {
        throw const PosFailure(
          'Only an owner or manager can change when the day starts.',
        );
      }
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that just now.");
    }
  }

  static const _columns =
      'currency, timezone, day_cutoff_minutes, service_charge, packaging_fee, '
      'tax_rules, receipt_template, block_negative_stock, payment_gateway, '
      'printing_mode, qr_auto_fire';

  /// Every setting in one read. A missing row is not an error — a tenant made
  /// before the table existed simply gets the column defaults.
  Future<TenantSettings> load() async {
    try {
      final row = await _client
          .from('tenant_settings')
          .select(_columns)
          .eq('tenant_id', _tenantId)
          .maybeSingle();
      return TenantSettings.fromJson(row);
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your settings.");
    }
  }

  /// The General screen. Not the restaurant's name — that lives on `tenants`
  /// and is owner-only, so it is a separate call the caller makes after this
  /// one succeeds. Fusing them would half-succeed invisibly for a manager.
  Future<void> saveGeneral({
    required String currency,
    required String timezone,
    required int dayCutoffMinutes,
    required String paymentGateway,
    required bool qrAutoFire,
    required bool blockNegativeStock,
  }) async {
    if (!settingsCurrencies.contains(currency)) {
      throw const PosFailure('That is not a currency we offer.');
    }
    if (!settingsTimezones.contains(timezone)) {
      throw const PosFailure('That is not a timezone we offer.');
    }
    if (!dayCutoffOptions.containsKey(dayCutoffMinutes)) {
      throw const PosFailure('That is not a day-start time we offer.');
    }
    if (!paymentGateways.containsKey(paymentGateway)) {
      throw const PosFailure('That is not a payment mode we offer.');
    }
    await _update({
      'currency': currency,
      'timezone': timezone,
      'day_cutoff_minutes': dayCutoffMinutes,
      'payment_gateway': paymentGateway,
      'qr_auto_fire': qrAutoFire,
      'block_negative_stock': blockNegativeStock,
    });
  }

  /// Charges and tax. [serviceCharge] is a percentage; [packagingFee] is in
  /// currency units, not cents.
  Future<void> saveCharges({
    required double serviceCharge,
    required double packagingFee,
    required List<TaxRule> taxRules,
  }) async {
    if (serviceCharge.isNaN || serviceCharge < 0 || serviceCharge > 100) {
      throw const PosFailure('Service charge must be between 0 and 100.');
    }
    if (packagingFee.isNaN || packagingFee < 0) {
      throw const PosFailure("Packaging fee can't be negative.");
    }
    for (final rule in taxRules) {
      if (rule.name.trim().isEmpty) {
        throw const PosFailure('Give every tax rule a name.');
      }
      if (rule.rate.isNaN || rule.rate < 0 || rule.rate > 100) {
        throw PosFailure('${rule.name} must be between 0 and 100 percent.');
      }
    }
    await _update({
      'service_charge': serviceCharge,
      'packaging_fee': packagingFee,
      'tax_rules': taxRules.map((r) => r.toJson()).toList(),
    });
  }

  /// The words on the receipt.
  ///
  /// Through `merge_receipt_template` rather than a column write: the template
  /// also holds branding the phone did not load, and a whole-column update
  /// would drop it. The patch carries these four keys and **never**
  /// `print_assets` — see [attachBrandImage] for why that matters.
  Future<void> saveReceiptText({
    required String header,
    required String footer,
    required String terms,
    required String qrCaption,
  }) async {
    await _merge({
      'header': header.trim(),
      'footer': footer.trim(),
      'terms': terms.trim(),
      'qr_caption': qrCaption.trim(),
    });
  }

  /// Point the receipt at a freshly uploaded logo or payment QR.
  ///
  /// [currentAssets] must be the `print_assets` map as it stands on the server,
  /// because the merge is **shallow**: the patch's `print_assets` replaces the
  /// stored one outright. Send only the new kind and the other one — logo or QR
  /// — vanishes from every printed slip with no error anywhere.
  Future<void> attachBrandImage({
    required String kind,
    required String url,
    required Map<String, dynamic> variants,
    required Map<String, dynamic> currentAssets,
  }) async {
    _assertKind(kind);
    await _merge({
      kind == 'logo' ? 'logo_url' : 'qr_url': url,
      // Replaced wholesale for this kind, never merged into: a half-old set of
      // widths prints last month's logo on the 58mm roll and this month's on
      // the 80mm one.
      'print_assets': {...currentAssets, kind: variants},
    });
  }

  /// Take an image off the receipt — the picture and the baked bytes together.
  ///
  /// A json `null` deletes the key outright; that is what
  /// `merge_receipt_template` does with one, and it is why the URL is nulled
  /// rather than set to an empty string.
  Future<void> detachBrandImage({
    required String kind,
    required Map<String, dynamic> currentAssets,
  }) async {
    _assertKind(kind);
    final assets = Map<String, dynamic>.from(currentAssets)..remove(kind);
    await _merge({
      kind == 'logo' ? 'logo_url' : 'qr_url': null,
      'print_assets': assets,
    });
  }

  /// Rename the restaurant.
  ///
  /// **Owner-only**, unlike everything else here: `tenants_owner_update` is
  /// stricter than `tenant_settings_owner_write`. A manager's rename matches no
  /// row, so the read-back is what turns a silent no-op into a sentence they
  /// can act on.
  Future<void> renameTenant(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PosFailure('The restaurant needs a name.');
    }
    try {
      final changed = await _client
          .from('tenants')
          .update({'name': trimmed})
          .eq('id', _tenantId)
          .select('id');
      if (changed.isEmpty) {
        throw const PosFailure(
          'Only the owner can rename the restaurant. Ask them, or have them '
          'change your role under Team.',
        );
      }
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that just now.");
    }
  }

  /// Put the picture in the bucket and hand back the URL a screen can show.
  ///
  /// The bucket is `menu-images`, public-read, with writes scoped by RLS to a
  /// folder named after the tenant — the same path shape the web uses, so the
  /// two clients overwrite each other's upload rather than accumulating two
  /// logos. Note the policy checks the *folder* only: any member of the tenant
  /// can write here, and it is `merge_receipt_template` that refuses to attach
  /// it for anyone but an owner or manager.
  Future<String> uploadBrandObject({
    required String kind,
    required Uint8List bytes,
    required String extension,
    String? contentType,
  }) async {
    _assertKind(kind);
    final ext = extension.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final path = '$_tenantId/${kind == 'logo' ? 'logo' : 'receipt-qr'}'
        '.${ext.isEmpty ? 'png' : ext}';
    try {
      await _client.storage
          .from('menu-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );
      final url = _client.storage.from('menu-images').getPublicUrl(path);
      // Cache-buster: the path is stable across uploads, so without this every
      // screen and CDN keeps serving the picture that was replaced.
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } on StorageException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't upload that image just now.");
    }
  }

  /// Delete the stored object behind a brand URL.
  ///
  /// Called before the template is patched: the bucket is public, so an object
  /// left behind keeps serving the "removed" logo to anyone holding its URL.
  /// Failure is swallowed — an orphaned object is untidy, a receipt still
  /// showing a logo the owner deleted is wrong.
  Future<void> removeBrandObject(String? url) async {
    if (url == null) return;
    final path = url.split('?').first.split('/menu-images/').elementAtOrNull(1);
    if (path == null || !path.startsWith('$_tenantId/')) return;
    try {
      await _client.storage.from('menu-images').remove([path]);
    } catch (_) {
      // Deliberately ignored — see above.
    }
  }

  void _assertKind(String kind) {
    if (kind != 'logo' && kind != 'qr') {
      throw PosFailure('Unknown image kind: $kind.');
    }
  }

  /// One place the read-back rule is applied, so it cannot be forgotten in a
  /// hurry on the next setting somebody adds.
  Future<void> _update(Map<String, dynamic> patch) async {
    try {
      final changed = await _client
          .from('tenant_settings')
          .update(patch)
          .eq('tenant_id', _tenantId)
          .select('tenant_id');
      if (changed.isEmpty) {
        throw const PosFailure(
          'Only an owner or manager can change these settings.',
        );
      }
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that just now.");
    }
  }

  /// `merge_receipt_template` is `security definer` and checks owner|manager
  /// itself, so this one raises rather than returning an empty set.
  Future<void> _merge(Map<String, dynamic> patch) async {
    try {
      await _client.rpc<dynamic>(
        'merge_receipt_template',
        params: {'_tenant': _tenantId, '_patch': patch},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(
        e.message.contains('not authorized') || e.message.contains('permission')
            ? 'Only an owner or manager can change the receipt.'
            : e.message,
      );
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that just now.");
    }
  }
}

final settingsRepositoryProvider = Provider.family<SettingsRepository, String>(
  (ref, tenantId) => SettingsRepository(ref.watch(supabaseProvider), tenantId),
);
