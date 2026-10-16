import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focubili/features/notes/visual_note_editor.dart';
import 'package:focubili/features/notes/video_note_frame_viewer_page.dart';

const target = 'focubili://video?bvid=BV1GJ411x7h7&cid=100&page=1&ms=62000';
const timestamp = '[01:02]($target)';

void main() {
  testWidgets(
    'editing and reading display actual images and clickable timestamps',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = File('assets/icon/focubili_icon.png');
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.runAsync(
        () => precacheImage(
          FileImage(image),
          tester.element(find.byType(Scaffold)),
        ),
      );
      final controller = TextEditingController(
        text: '前文$timestamp![视频截图](images/frame.png)后文',
      );
      String? link;
      for (final editing in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualNoteEditor(
                  controller: controller,
                  editing: editing,
                  attachments: {'images/frame.png': image.path},
                  onLink: (value) => link = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        final body = controller.text;
        await tester.tap(
          find.byKey(const ValueKey('open-note-image-images/frame.png')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VideoNoteFrameViewerPage), findsOneWidget);
        expect(
          tester
              .widget<VideoNoteFrameViewerPage>(
                find.byType(VideoNoteFrameViewerPage),
              )
              .framePath,
          image.path,
        );
        expect(
          find.byKey(const Key('reset-fullscreen-note-frame-zoom')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('close-fullscreen-note-frame')));
        await tester.pumpAndSettle();
        expect(find.byType(VideoNoteFrameViewerPage), findsNothing);
        expect(controller.text, body);
        expect(find.text('截图文件不可用'), findsNothing);
        expect(find.widgetWithText(ActionChip, '01:02'), findsOneWidget);
        expect(find.textContaining('focubili://'), findsNothing);
        expect(find.textContaining('![视频截图]'), findsNothing);
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          expect(field.controller!.text, isNot(contains('focubili://')));
          expect(field.controller!.text, isNot(contains('images/frame.png')));
        }
        await tester.tap(find.widgetWithText(ActionChip, '01:02'));
        expect(link, target);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'insert at caret, continue after media, and remove without losing text',
    (tester) async {
      final controller = TextEditingController(text: '前文后文');
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisualNoteEditor(
              controller: controller,
              onChanged: (_) => changes++,
              onTimestamp: () => VisualNoteEditor.insert(controller, timestamp),
            ),
          ),
        ),
      );
      final first = tester.widget<TextField>(
        find.byKey(const Key('visual-note-body')),
      );
      first.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.tap(find.text('时间戳'));
      await tester.pump();
      expect(controller.text, '前文$timestamp后文');
      expect(find.widgetWithText(ActionChip, '01:02'), findsOneWidget);
      final lastField = find.byType(TextField).last;
      await tester.enterText(lastField, '续写后文');
      expect(controller.text, '前文$timestamp续写后文');
      expect(changes, 1);
      await tester.tap(find.byTooltip('移除时间戳'));
      await tester.pump();
      expect(controller.text, '前文续写后文');
      expect(find.byType(ActionChip), findsNothing);
      expect(changes, 2);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'switching documents and editing text preserve image order and references',
    (tester) async {
      final controller = TextEditingController(text: '第一篇');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VisualNoteEditor(controller: controller)),
        ),
      );
      controller.text =
          '前![截图一](images/one.png)中$timestamp![截图二](images/two.png)后';
      await tester.pump();
      expect(find.byTooltip('移除截图'), findsNWidgets(2));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '修改中');
      expect(
        controller.text,
        '前![截图一](images/one.png)修改中$timestamp![截图二](images/two.png)后',
      );
      await tester.tap(find.byTooltip('移除截图').first);
      await tester.pump();
      expect(controller.text, '前修改中$timestamp![截图二](images/two.png)后');
      controller.text = '切换到另一篇';
      await tester.pump();
      expect(find.byType(ActionChip), findsNothing);
      expect(find.byTooltip('移除截图'), findsNothing);
      expect(tester.widget<TextField>(fields).controller!.text, '切换到另一篇');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'literal links in code are preserved as text rather than active media',
    (tester) async {
      final controller = TextEditingController(text: '```\n$timestamp\n```');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VisualNoteEditor(controller: controller)),
        ),
      );
      expect(find.byType(ActionChip), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        controller.text,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
