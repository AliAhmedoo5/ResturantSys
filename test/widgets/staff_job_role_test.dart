import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/department.dart';
import 'package:resturant_sys/core/auth/job_role.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/widgets/supervisor/staff_form_dialog.dart';

void main() {
  testWidgets('registers a Rider job title with no login or PIN', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? savedLogin;
    int? savedJob;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => StaffFormDialog(
        departments: [Department(id: 1, name: 'Riders', createdAt: DateTime(2026))],
        jobRoles: const [JobRole(id: 1, name: 'Rider')],
        onSave: ({required String name, required int departmentId, required StaffRole role,
          required String pin, required bool loginEnabled, required int? jobRoleId, bool? isActive}) async {
          savedLogin = loginEnabled;
          savedJob = jobRoleId;
        },
      )), child: const Text('Open'),
    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff_pin_input')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('staff_name_input')), 'Test Rider');
    await tester.tap(find.byKey(const ValueKey('staff_job_role_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rider').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff_save_button')));
    await tester.pumpAndSettle();
    expect(savedLogin, isFalse);
    expect(savedJob, 1);
  });
}
