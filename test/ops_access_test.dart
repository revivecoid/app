import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/features/ops_mobile/ops_access.dart';

/// The workshop owner chooses between letting staff and drivers see everything
/// (all_access, the database default) and restoring the original strict per-role
/// split (original_role). These tests pin the rules both modes must satisfy.
void main() {
  group('OpsViewMode parsing', () {
    test('reads original_role from the database value', () {
      expect(OpsViewMode.fromDb('original_role'), OpsViewMode.originalRole);
    });

    test('reads all_access from the database value', () {
      expect(OpsViewMode.fromDb('all_access'), OpsViewMode.allAccess);
    });

    test('unknown and missing values fall back to all_access (the DB default)', () {
      expect(OpsViewMode.fromDb(null), OpsViewMode.allAccess);
      expect(OpsViewMode.fromDb(''), OpsViewMode.allAccess);
      expect(OpsViewMode.fromDb('typo'), OpsViewMode.allAccess);
    });

    test('round-trips back to the database values', () {
      expect(OpsViewMode.allAccess.dbValue, 'all_access');
      expect(OpsViewMode.originalRole.dbValue, 'original_role');
    });
  });

  group('opsTabsFor — all_access shows every tab to both roles', () {
    test('staff sees floor, logistics and settings', () {
      expect(opsTabsFor(OpsViewMode.allAccess, 'partner_staff'), OpsTab.values);
    });

    test('driver sees floor, logistics and settings', () {
      expect(opsTabsFor(OpsViewMode.allAccess, 'partner_driver'), OpsTab.values);
    });

    test('mechanic and admin see every tab', () {
      expect(opsTabsFor(OpsViewMode.allAccess, 'partner_mechanic'), OpsTab.values);
      expect(opsTabsFor(OpsViewMode.allAccess, 'master_admin'), OpsTab.values);
    });
  });

  group('opsTabsFor — original_role restores the previous behaviour', () {
    test('driver is limited to logistics and settings', () {
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_driver'),
          const [OpsTab.logistics, OpsTab.settings]);
    });

    test('staff keeps all three tabs (it always had them)', () {
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_staff'), OpsTab.values);
    });

    test('mechanic keeps all three tabs', () {
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_mechanic'), OpsTab.values);
    });
  });

  group('opsHomeRouteFor', () {
    test('all_access always lands on the floor', () {
      expect(opsHomeRouteFor(OpsViewMode.allAccess, 'partner_driver'), '/ops/floor');
      expect(opsHomeRouteFor(OpsViewMode.allAccess, 'partner_staff'), '/ops/floor');
    });

    test('original_role sends a driver to logistics, everyone else to the floor', () {
      expect(opsHomeRouteFor(OpsViewMode.originalRole, 'partner_driver'), '/ops/logistics');
      expect(opsHomeRouteFor(OpsViewMode.originalRole, 'partner_staff'), '/ops/floor');
    });
  });

  group('opsRoleMayActOnStage — all_access lets either role do any stage', () {
    const intakeStage = ['partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin'];
    const deliveryStage = ['partner_driver', 'partner_mechanic', 'master_admin'];
    const floorStage = ['partner_staff', 'partner_mechanic', 'master_admin'];

    test('a driver may complete the floor-only disassembly stage', () {
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_driver', floorStage), isTrue);
    });

    test('a staff member may complete the driver-only delivery stage', () {
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_staff', deliveryStage), isTrue);
    });

    test('both roles may complete vehicle intake', () {
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_staff', intakeStage), isTrue);
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_driver', intakeStage), isTrue);
    });

    test('customers are still refused', () {
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'customer', floorStage), isFalse);
    });

    test('a missing role is refused', () {
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, null, floorStage), isFalse);
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, '', floorStage), isFalse);
    });
  });

  group('opsRoleMayActOnStage — original_role keeps the stage role lists', () {
    const deliveryStage = ['partner_driver', 'partner_mechanic', 'master_admin'];
    const floorStage = ['partner_staff', 'partner_mechanic', 'master_admin'];

    test('a staff member may NOT complete the delivery stage', () {
      expect(opsRoleMayActOnStage(OpsViewMode.originalRole, 'partner_staff', deliveryStage), isFalse);
    });

    test('a driver may NOT complete a floor-only stage', () {
      expect(opsRoleMayActOnStage(OpsViewMode.originalRole, 'partner_driver', floorStage), isFalse);
    });

    test('each role may still complete its own stage', () {
      expect(opsRoleMayActOnStage(OpsViewMode.originalRole, 'partner_driver', deliveryStage), isTrue);
      expect(opsRoleMayActOnStage(OpsViewMode.originalRole, 'partner_staff', floorStage), isTrue);
    });
  });
}
