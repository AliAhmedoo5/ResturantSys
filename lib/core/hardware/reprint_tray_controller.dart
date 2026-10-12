import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/pos_database_constants.dart';
import '../orders/order.dart';
import 'esc_pos_generator.dart';
import 'hardware_device_adapter.dart';
import 'paper_width.dart';
import 'print_job.dart';
import 'printer_target.dart';
import 'printer_topology.dart';

/// Controller coordinating decoupled hardware printing, cash drawer kick pulses,
/// and an on-screen Reprint Tray for paper jams or hardware disconnects.
class ReprintTrayController extends ChangeNotifier {
  ReprintTrayController({
    required this.hardwareAdapter,
    this.generator = const EscPosGenerator(),
    this.topology = PrinterTopology.single,
    this.paperWidth = PaperWidth.mm80,
    this.cashDrawerEnabled = true,
    this.storeName = 'RESTURANT POS',
    this.storeTagline = 'Fast Food & Kitchen Operations',
    this.storeAddress = 'Main Commercial Avenue',
    this.storePhone = '+92 300 1234567',
    this.storeTaxId = 'STRN/NTN: 9876543-2',
  });

  final HardwareDeviceAdapter hardwareAdapter;
  final EscPosGenerator generator;

  PrinterTopology topology;
  PaperWidth paperWidth;
  bool cashDrawerEnabled;

  String storeName;
  String storeTagline;
  String storeAddress;
  String storePhone;
  String? storeTaxId;

  final List<PrintJob> _failedJobs = [];
  final List<PrintJob> _recentJobs = [];
  static const int _maxRecentJobs = 30;

  UnmodifiableListView<PrintJob> get failedJobs => UnmodifiableListView(_failedJobs);
  UnmodifiableListView<PrintJob> get recentJobs => UnmodifiableListView(_recentJobs);

  int get failedCount => _failedJobs.length;
  bool get hasFailures => _failedJobs.isNotEmpty;

  /// Loads configuration from SQLite system settings if present.
  Future<void> loadSettings(DatabaseExecutor executor) async {
    try {
      final rows = await executor.query(PosDatabaseConstants.tableSystemSettings);
      final settings = {for (final r in rows) r['key'] as String: r['value'] as String};

      if (settings.containsKey('printer_topology')) {
        topology = PrinterTopology.fromSetting(settings['printer_topology']);
      }
      if (settings.containsKey('paper_width')) {
        paperWidth = PaperWidth.fromSetting(settings['paper_width']);
      }
      if (settings.containsKey('cash_drawer_enabled')) {
        cashDrawerEnabled = settings['cash_drawer_enabled']?.toLowerCase() == 'true';
      }
      if (settings.containsKey('app_name') && settings['app_name']!.isNotEmpty) {
        storeName = settings['app_name']!;
      }
      notifyListeners();
    } catch (_) {
      // Graceful fallback to default configuration
    }
  }

  /// Decoupled printing of Customer Tax Receipt and Kitchen Order Ticket (KOT).
  ///
  /// CRITICAL GUARANTEE:
  /// - Invoked strictly AFTER the order transaction commits to SQLite.
  /// - Hardware failures NEVER throw exceptions back to the database or cashier checkout.
  /// - Failed tickets enqueue into the on-screen Reprint Tray with 1-tap retry.
  /// - RJ11 cash drawer kicks strictly if cash was tendered.
  Future<void> dispatchOrderPrinting({
    required Order order,
    required bool isCashPaid,
  }) async {
    // 1. RJ11 Cash Drawer Kick Pulse (Strictly on Cash transactions)
    if (isCashPaid && cashDrawerEnabled) {
      try {
        await hardwareAdapter.kickCashDrawer();
      } catch (e) {
        // Cash drawer failure is recorded as a failed job in the tray
        final drawerJob = PrintJob(
          id: 'drawer_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
          target: PrinterTarget.counter,
          type: PrintJobType.cashDrawerKick,
          bytes: generator.generateCashDrawerPulse(),
          orderId: order.id,
          tokenDisplay: order.tokenDisplay,
          createdAt: DateTime.now(),
        );
        drawerJob.markFailed('Cash drawer kick failed: $e');
        _enqueueFailed(drawerJob);
      }
    }

    // 2. Customer Receipt
    final receiptJob = createCustomerReceiptJob(order);
    await _executeJob(receiptJob);

    // 3. Kitchen Order Ticket (KOT)
    // In Single Printer topology, KOT routes sequentially to Counter printer.
    // In Dual Printer topology, KOT routes to Kitchen printer.
    final kotJob = createKitchenOrderTicketJob(order);
    await _executeJob(kotJob);
  }

  /// Dispatches an Automatic Kitchen Void Slip upon supervisor order cancellation (ADR-0005).
  Future<void> dispatchKitchenVoidSlip({
    required Order order,
    required String reason,
    required String supervisorName,
  }) async {
    final kotTarget = topology == PrinterTopology.single
        ? PrinterTarget.counter
        : PrinterTarget.kitchen;

    final voidBytes = generator.generateKitchenVoidSlip(
      order: order,
      reason: reason,
      supervisorName: supervisorName,
      paperWidth: paperWidth,
    );

    final voidJob = PrintJob(
      id: 'void_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
      target: kotTarget,
      type: PrintJobType.kitchenVoidSlip,
      bytes: voidBytes,
      orderId: order.id,
      tokenDisplay: order.tokenDisplay,
      createdAt: DateTime.now(),
    );

    await _executeJob(voidJob);
  }

  /// Manual supervisor cash drawer override.
  Future<bool> triggerSupervisorDrawerOverride() async {
    if (!cashDrawerEnabled) {
      return true; // Manual unpluggable drawer bypassed
    }

    try {
      await hardwareAdapter.kickCashDrawer();
      return true;
    } catch (e) {
      final overrideJob = PrintJob(
        id: 'drawer_override_${DateTime.now().millisecondsSinceEpoch}',
        target: PrinterTarget.counter,
        type: PrintJobType.cashDrawerKick,
        bytes: generator.generateCashDrawerPulse(),
        orderId: 0,
        tokenDisplay: 'Override',
        createdAt: DateTime.now(),
      );
      overrideJob.markFailed('Supervisor drawer override failed: $e');
      _enqueueFailed(overrideJob);
      return false;
    }
  }

  /// 1-tap retry of a failed job.
  Future<bool> retryJob(String jobId) async {
    final index = _failedJobs.indexWhere((j) => j.id == jobId);
    if (index == -1) return false;

    final job = _failedJobs[index];
    try {
      if (job.type == PrintJobType.cashDrawerKick) {
        await hardwareAdapter.kickCashDrawer();
      } else {
        await hardwareAdapter.sendBytes(job.target, job.bytes);
      }

      job.markSuccess();
      _failedJobs.removeAt(index);
      _recordRecent(job);
      notifyListeners();
      return true;
    } catch (e) {
      job.markFailed('Retry attempt failed: $e');
      notifyListeners();
      return false;
    }
  }

  /// 1-tap retry of all failed jobs currently in the tray.
  Future<int> retryAllFailed() async {
    if (_failedJobs.isEmpty) return 0;

    int successCount = 0;
    final toRetry = List<PrintJob>.of(_failedJobs);

    for (final job in toRetry) {
      final ok = await retryJob(job.id);
      if (ok) successCount++;
    }

    return successCount;
  }

  /// Creates a Customer Receipt print job.
  PrintJob createCustomerReceiptJob(Order order, {String? idPrefix}) {
    final receiptBytes = generator.generateCustomerTaxReceipt(
      order: order,
      paperWidth: paperWidth,
      storeName: storeName,
      storeTagline: storeTagline,
      storeAddress: storeAddress,
      storePhone: storePhone,
      storeTaxId: storeTaxId,
    );

    final prefix = idPrefix ?? 'receipt';
    return PrintJob(
      id: '${prefix}_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
      target: PrinterTarget.counter,
      type: PrintJobType.customerReceipt,
      bytes: receiptBytes,
      orderId: order.id,
      tokenDisplay: order.tokenDisplay,
      createdAt: DateTime.now(),
    );
  }

  /// Creates a Kitchen Order Ticket (KOT) print job routed according to active topology.
  PrintJob createKitchenOrderTicketJob(Order order, {String? idPrefix}) {
    final kotTarget = topology == PrinterTopology.single
        ? PrinterTarget.counter
        : PrinterTarget.kitchen;

    final kotBytes = generator.generateKitchenOrderTicket(
      order: order,
      paperWidth: paperWidth,
    );

    final prefix = idPrefix ?? 'kot';
    return PrintJob(
      id: '${prefix}_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
      target: kotTarget,
      type: PrintJobType.kitchenOrderTicket,
      bytes: kotBytes,
      orderId: order.id,
      tokenDisplay: order.tokenDisplay,
      createdAt: DateTime.now(),
    );
  }

  /// Reprints a customer receipt on demand for duplicate request or manual reprint.
  Future<bool> reprintCustomerReceipt(Order order) async {
    final job = createCustomerReceiptJob(order, idPrefix: 'reprint_receipt');
    return await _executeJob(job);
  }

  /// Reprints a Kitchen Order Ticket on demand.
  Future<bool> reprintKitchenOrderTicket(Order order) async {
    final job = createKitchenOrderTicketJob(order, idPrefix: 'reprint_kot');
    return await _executeJob(job);
  }

  /// Reprints an existing print job, routing cash drawer pulses or printer bytes safely.
  Future<bool> reprintJob(PrintJob job) async {
    final newJob = PrintJob(
      id: 'reprint_${job.type.name}_${job.orderId}_${DateTime.now().millisecondsSinceEpoch}',
      target: job.target,
      type: job.type,
      bytes: job.bytes,
      orderId: job.orderId,
      tokenDisplay: job.tokenDisplay,
      createdAt: DateTime.now(),
    );

    if (newJob.type == PrintJobType.cashDrawerKick) {
      try {
        await hardwareAdapter.kickCashDrawer();
        newJob.markSuccess();
        _recordRecent(newJob);
        notifyListeners();
        return true;
      } catch (e) {
        newJob.markFailed('Cash drawer kick failed: $e');
        _enqueueFailed(newJob);
        return false;
      }
    } else {
      return await _executeJob(newJob);
    }
  }

  /// Clears a resolved or ignored failed job from the tray.
  void dismissFailedJob(String jobId) {
    _failedJobs.removeWhere((j) => j.id == jobId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  Future<bool> _executeJob(PrintJob job) async {
    try {
      await hardwareAdapter.sendBytes(job.target, job.bytes);
      job.markSuccess();
      _recordRecent(job);
      notifyListeners();
      return true;
    } catch (e) {
      job.markFailed('Print failed: $e');
      _enqueueFailed(job);
      return false;
    }
  }

  void _enqueueFailed(PrintJob job) {
    _failedJobs.add(job);
    notifyListeners();
  }

  void _recordRecent(PrintJob job) {
    _recentJobs.insert(0, job);
    if (_recentJobs.length > _maxRecentJobs) {
      _recentJobs.removeLast();
    }
  }
}
