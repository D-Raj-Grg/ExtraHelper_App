import 'package:extrahelper/features/menu/menu_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 86 is gated on its own key, not the role string and not `menu.edit`: the
/// kitchen holds `menu.86` by default without being able to edit the menu.
/// `set_item_86` checks the same key, so the switch and the server agree.
ProviderContainer _with(Set<String> permissions) {
  final container = ProviderContainer(
    overrides: [permissionsProvider.overrideWith((ref) => permissions)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('menu.86 alone lets someone 86 a dish', () async {
    final c = _with({'kds.view', 'menu.86'});
    await c.read(permissionsProvider.future);
    expect(c.read(canSetStockProvider), isTrue);
    expect(c.read(canEditMenuProvider), isFalse);
  });

  test('menu.edit without menu.86 cannot 86', () async {
    final c = _with({'menu.view', 'menu.edit'});
    await c.read(permissionsProvider.future);
    expect(c.read(canSetStockProvider), isFalse);
  });
}
