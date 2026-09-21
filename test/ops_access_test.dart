import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/features/ops_mobile/ops_access.dart';
import 'package:re_v/features/ops_mobile/presentation/ops_stage_photo_screen.dart';

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

  // These groups read the REAL stage definitions rather than local copies. The
  // copies that used to live here are what let the UI's allowedRoles and the
  // server's role gate drift apart: the test kept passing while the RPC refused
  // what the UI offered.
  group('stage role lists — the UI and the server must agree', () {
    test('the delivery stage admits staff, because staff hand the car back', () {
      // ops_complete_delivery admits partner_staff too. If this list omits them
      // the button is hidden for a role the server would accept; if the server
      // omits them, the button is a dead end.
      final delivery = stageByKey('delivery')!;
      expect(delivery.allowedRoles, contains('partner_staff'));
      expect(delivery.advancesStatus, '9_done');
    });

    test('vehicle intake still admits both ops roles', () {
      final intake = stageByKey('vehicle_intake')!;
      expect(intake.allowedRoles, containsAll(['partner_staff', 'partner_driver']));
      expect(intake.advancesStatus, '5_admitted');
    });

    test('every stage admits at least one ops role and an admin', () {
      for (final s in kOpsStages) {
        expect(s.allowedRoles, isNotEmpty, reason: '${s.stageKey} admits nobody');
        expect(s.allowedRoles, contains('master_admin'), reason: s.stageKey);
        expect(kOpsOperatorRoles.any(s.allowedRoles.contains), isTrue,
            reason: '${s.stageKey} admits no operator role');
      }
    });

    test('stage keys are unique, since they key the milestone upsert', () {
      final keys = kOpsStages.map((s) => s.stageKey).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('opsRoleMayActOnStage — all_access lets either role do any stage', () {
    test('a driver may complete the floor-only disassembly stage', () {
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.allAccess, 'partner_driver', stageByKey('disassembly')!.allowedRoles),
        isTrue,
      );
    });

    test('a staff member may complete the delivery stage', () {
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.allAccess, 'partner_staff', stageByKey('delivery')!.allowedRoles),
        isTrue,
      );
    });

    test('both roles may complete vehicle intake', () {
      final intake = stageByKey('vehicle_intake')!.allowedRoles;
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_staff', intake), isTrue);
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_driver', intake), isTrue);
    });

    test('customers are still refused', () {
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.allAccess, 'customer', stageByKey('disassembly')!.allowedRoles),
        isFalse,
      );
    });

    test('a missing role is refused', () {
      final floor = stageByKey('disassembly')!.allowedRoles;
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, null, floor), isFalse);
      expect(opsRoleMayActOnStage(OpsViewMode.allAccess, '', floor), isFalse);
    });
  });

  group('opsRoleMayActOnStage — original_role keeps the stage role lists', () {
    test('a staff member MAY complete delivery (changed deliberately)', () {
      // Staff deliver cars to clients, so excluding them left a stage the UI
      // offered under all_access and the RPC refused.
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.originalRole, 'partner_staff', stageByKey('delivery')!.allowedRoles),
        isTrue,
      );
    });

    test('a driver may NOT complete a floor-only stage', () {
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.originalRole, 'partner_driver', stageByKey('disassembly')!.allowedRoles),
        isFalse,
      );
    });

    test('a driver may still complete intake and delivery', () {
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.originalRole, 'partner_driver', stageByKey('vehicle_intake')!.allowedRoles),
        isTrue,
      );
      expect(
        opsRoleMayActOnStage(
            OpsViewMode.originalRole, 'partner_driver', stageByKey('delivery')!.allowedRoles),
        isTrue,
      );
    });
  });
}
