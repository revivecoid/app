import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/features/ops_mobile/ops_access.dart';
import 'package:re_v/features/ops_mobile/presentation/ops_stage_photo_screen.dart';

/// The workshop owner picks between three access modes. The distinction that
/// matters is VIEW vs ACT: view_all_act_own exists precisely so an operator can
/// see every stage without being able to complete another role's work.
///
/// Acting is enforced by the database (`ops_may_act_on_stage()` reading
/// `ops_stage_roles`, which seeds itself from these same Dart lists). These tests
/// pin the Dart side of that agreement — if the two disagree the UI offers taps
/// the server then refuses.
void main() {
  group('OpsViewMode parsing — three values, unknown falls to the DB default', () {
    test('reads each stored value', () {
      expect(OpsViewMode.fromDb('original_role'), OpsViewMode.originalRole);
      expect(OpsViewMode.fromDb('all_access'), OpsViewMode.allAccess);
      expect(OpsViewMode.fromDb('view_all_act_own'), OpsViewMode.viewAllActOwn);
    });

    test('unknown and missing values fall back to all_access (the DB default)', () {
      expect(OpsViewMode.fromDb(null), OpsViewMode.allAccess);
      expect(OpsViewMode.fromDb(''), OpsViewMode.allAccess);
      expect(OpsViewMode.fromDb('typo'), OpsViewMode.allAccess);
      // A near-miss must not silently become a restrictive mode.
      expect(OpsViewMode.fromDb('view_all_act_own '), OpsViewMode.allAccess);
    });

    test('dbValue round-trips through fromDb for every mode', () {
      for (final m in OpsViewMode.values) {
        expect(OpsViewMode.fromDb(m.dbValue), m, reason: m.name);
      }
    });

    test('every mode carries a label and description for the settings UI', () {
      for (final m in OpsViewMode.values) {
        expect(m.label, isNotEmpty, reason: m.name);
        expect(m.description, isNotEmpty, reason: m.name);
      }
    });
  });

  group('view vs act — the distinction that makes view_all_act_own work', () {
    final floorStage = stageByKey('disassembly')!.allowedRoles;

    test('view_all_act_own shows every stage to every operator', () {
      for (final role in ['partner_driver', 'partner_staff', 'partner_mechanic']) {
        expect(opsRoleMayViewStage(OpsViewMode.viewAllActOwn, role, floorStage), isTrue,
            reason: role);
      }
    });

    test('view_all_act_own does NOT let a driver act on a floor stage', () {
      // The whole point: visible, but read-only for this role.
      expect(
        opsRoleMayActOnStage(OpsViewMode.viewAllActOwn, 'partner_driver', floorStage),
        isFalse,
      );
    });

    test('view_all_act_own still lets the owning roles act', () {
      expect(opsRoleMayActOnStage(OpsViewMode.viewAllActOwn, 'partner_staff', floorStage), isTrue);
      expect(opsRoleMayActOnStage(OpsViewMode.viewAllActOwn, 'partner_mechanic', floorStage), isTrue);
    });

    test('all_access lets a driver act on every stage', () {
      for (final s in kOpsStages) {
        expect(opsRoleMayActOnStage(OpsViewMode.allAccess, 'partner_driver', s.allowedRoles), isTrue,
            reason: s.stageKey);
      }
    });

    test('original_role hides AND blocks a floor stage from a driver', () {
      expect(opsRoleMayViewStage(OpsViewMode.originalRole, 'partner_driver', floorStage), isFalse);
      expect(opsRoleMayActOnStage(OpsViewMode.originalRole, 'partner_driver', floorStage), isFalse);
    });

    test('acting implies viewing in every mode — no invisible-but-tappable stage', () {
      for (final mode in OpsViewMode.values) {
        for (final role in kOpsOperatorRoles) {
          for (final s in kOpsStages) {
            if (opsRoleMayActOnStage(mode, role, s.allowedRoles)) {
              expect(opsRoleMayViewStage(mode, role, s.allowedRoles), isTrue,
                  reason: '${mode.name}/$role/${s.stageKey}');
            }
          }
        }
      }
    });

    test('a non-operator is refused both view and act', () {
      for (final role in ['customer', null, '']) {
        expect(opsRoleMayViewStage(OpsViewMode.allAccess, role, floorStage), isFalse);
        expect(opsRoleMayActOnStage(OpsViewMode.allAccess, role, floorStage), isFalse);
      }
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

    test('the new mode genuinely restricts a driver somewhere', () {
      // If every stage admitted every role, view_all_act_own would restrict
      // nothing and the feature would be cosmetic. Guard against that.
      final blocked = kOpsStages
          .where((s) =>
              !opsRoleMayActOnStage(OpsViewMode.viewAllActOwn, 'partner_driver', s.allowedRoles))
          .toList();
      expect(blocked, isNotEmpty,
          reason: 'view_all_act_own would restrict nothing for a driver');
      expect(blocked.map((s) => s.stageKey), contains('disassembly'));
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

  group('opsTabsFor — both seeing modes give every operator every tab', () {
    test('all_access shows floor, logistics and settings to everyone', () {
      for (final role in kOpsOperatorRoles) {
        expect(opsTabsFor(OpsViewMode.allAccess, role), OpsTab.values, reason: role);
      }
    });

    test('view_all_act_own also shows everything — seeing is not acting', () {
      for (final role in kOpsOperatorRoles) {
        expect(opsTabsFor(OpsViewMode.viewAllActOwn, role), OpsTab.values, reason: role);
      }
    });

    test('original_role limits the driver to logistics and settings', () {
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_driver'),
          const [OpsTab.logistics, OpsTab.settings]);
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_staff'), OpsTab.values);
      expect(opsTabsFor(OpsViewMode.originalRole, 'partner_mechanic'), OpsTab.values);
    });
  });

  group('opsHomeRouteFor', () {
    test('all_access and view_all_act_own always land on the floor', () {
      for (final mode in [OpsViewMode.allAccess, OpsViewMode.viewAllActOwn]) {
        expect(opsHomeRouteFor(mode, 'partner_driver'), '/ops/floor', reason: mode.name);
        expect(opsHomeRouteFor(mode, 'partner_staff'), '/ops/floor', reason: mode.name);
      }
    });

    test('original_role sends a driver to logistics, everyone else to the floor', () {
      expect(opsHomeRouteFor(OpsViewMode.originalRole, 'partner_driver'), '/ops/logistics');
      expect(opsHomeRouteFor(OpsViewMode.originalRole, 'partner_staff'), '/ops/floor');
    });
  });
}
