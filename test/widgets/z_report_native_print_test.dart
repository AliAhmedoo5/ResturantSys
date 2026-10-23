import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/shifts/z_report.dart';
import 'package:resturant_sys/widgets/supervisor/supervisor_portal_workspace.dart';

void main() {
  testWidgets('Manager Portal Print Z-Report reaches the native printer dialog', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('net.nfet.printing');
    final messenger = tester.binding.defaultBinaryMessenger;
    var nativePrintCalls = 0;
    Uint8List? document;
    Future<Object?> nativeCall(String method, Map<String, Object?> args) async {
      final response = Completer<Object?>();
      await messenger.handlePlatformMessage(channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
          (bytes) => response.complete(bytes == null ? null : const StandardMethodCodec().decodeEnvelope(bytes)));
      return response.future;
    }
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printPdf') {
        nativePrintCalls++;
        final args = call.arguments as Map;
        document = await nativeCall('onLayout', {
          'job': args['job'], 'width': 595.0, 'height': 842.0,
          'marginLeft': 20.0, 'marginRight': 20.0,
          'marginTop': 20.0, 'marginBottom': 20.0,
        }) as Uint8List?;
        await nativeCall('onCompleted', {'job': args['job'], 'completed': true});
        return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final tray = ReprintTrayController(hardwareAdapter: InMemoryHardwareAdapter());
    addTearDown(tray.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SupervisorPortalWorkspace(
      reprintTrayController: tray,
      initialDepartments: const [], initialStaff: const [],
      initialTokenTrayEnabled: true, initialCashierVoidEnabled: true,
      initialDiscrepancies: const [],
      initialZReport: ZReport(businessDayId: 2, openedAt: DateTime(2026, 10, 24),
        generatedAt: DateTime(2026, 10, 24), openedByStaffName: 'Manager', totalShiftsCount: 0),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('portal_tab_reports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('portal_view_z_report_btn')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('print_z_report_button')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(nativePrintCalls, 1, reason: 'Print must reach the OS rather than only an in-memory adapter.');
    expect(document, isNotNull);
    expect(String.fromCharCodes(document!.take(5)), '%PDF-');
    expect(find.text('Z-Report sent to the printer.'), findsOneWidget);
  });
}
