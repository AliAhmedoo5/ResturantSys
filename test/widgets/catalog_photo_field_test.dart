import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/catalog_photo_change.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/catalog/catalog_photo_field.dart';

final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

void main() {
  testWidgets('browse stages one picture; cancel preserves it; remove stages removal', (tester) async {
    CatalogPhotoChange? change;
    bool busy = false;
    XFile? next = XFile.fromData(png, name: 'burger.png');
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: Center(child: SizedBox(width: 440, child: CatalogPhotoField(
        entityType: 'menu_item',
        pickFile: () async => next,
        onChanged: (value) => change = value,
        onBusyChanged: (value) => busy = value,
      )))),
    ));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('catalog_photo_browse')));
      for (var i = 0; busy && i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(busy, isFalse);
    expect(change?.bytes, png);
    expect(find.text('Change picture'), findsOneWidget);
    final previous = change;
    next = null;
    await tester.tap(find.byKey(const ValueKey('catalog_photo_browse')));
    await tester.pumpAndSettle();
    expect(change, same(previous));
    await tester.tap(find.byKey(const ValueKey('catalog_photo_remove')));
    await tester.pumpAndSettle();
    expect(change, isNotNull);
    expect(change!.bytes, isNull);
    expect(find.text('Add picture'), findsOneWidget);
  });

  testWidgets('drop rejects multiple, oversized and corrupt pictures without replacing selection', (tester) async {
    CatalogPhotoChange? change;
    bool busy = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 440,
      child: CatalogPhotoField(entityType: 'deal', onChanged: (value) => change = value,
        onBusyChanged: (value) => busy = value),
    ))));

    Future<void> drop(List<DropItem> files) async {
      await tester.runAsync(() async {
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(DropDoneDetails(
          files: files, localPosition: Offset.zero, globalPosition: Offset.zero,
        ));
        for (var i = 0; busy && i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(busy, isFalse);
    }

    await drop([DropItemFile.fromData(png, name: 'deal.png')]);
    expect(change?.bytes, png);
    final previous = change;
    await drop([DropItemFile.fromData(png, name: 'a.png'), DropItemFile.fromData(png, name: 'b.png')]);
    expect(find.text('Choose one picture at a time.'), findsOneWidget);
    expect(change, same(previous));
    await drop([DropItemFile.fromData(Uint8List(5 * 1024 * 1024 + 1), name: 'big.png')]);
    expect(find.text('Choose a non-empty picture up to 5 MB.'), findsOneWidget);
    expect(change, same(previous));
    await drop([DropItemFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'bad.png')]);
    expect(change, same(previous));
    // A valid PNG header alone still fails decoding.
    await drop([DropItemFile.fromData(Uint8List.sublistView(png, 0, 8), name: 'truncated.png')]);
    expect(change, same(previous));
    expect(find.textContaining('could not be read'), findsOneWidget);
    await drop([DropItemFile.fromData(png, name: 'photo.gif')]);
    expect(find.text('Choose a JPEG, PNG or WebP picture.'), findsOneWidget);
    expect(change, same(previous));
  });

  testWidgets('picture row stays compact at desktop size and supports keyboard selection', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var browseCount = 0;
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: RepaintBoundary(key: const ValueKey('photo_preview'), child: Scaffold(
        body: Center(child: SizedBox(width: 500, child: CatalogPhotoField(
          entityType: 'menu_item', onChanged: (_) {}, onBusyChanged: (_) {},
          pickFile: () async { browseCount++; return null; },
        ))),
      )),
    ));
    await tester.pumpAndSettle();
    final row = tester.getSize(find.byKey(const ValueKey('catalog_photo_drop_target')));
    expect(row.height, lessThanOrEqualTo(100));
    expect(row.width, 500);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(browseCount, 1);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('photo_preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/desktop-previews').create(recursive: true);
        await File('build/desktop-previews/catalog-picture.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
