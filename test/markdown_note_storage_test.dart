import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focubili/models/video_note.dart';
import 'package:focubili/services/video_note_service.dart';
import 'app_favorites_backup_test.dart' show FailingPreferences;

VideoNote note(String id, {Map<String, String> attachments = const {}}) =>
    VideoNote(
      id: id,
      bvid: 'BV1GJ411x7h7',
      videoTitle: '课程',
      ownerName: '老师',
      partCid: 100,
      partPageNumber: 1,
      partTitle: '第一课',
      title: '课程笔记',
      body: '# 标题\n\n  正文  ',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      position: const Duration(seconds: 12),
      attachments: attachments,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'rejected save restores cached document and retains referenced screenshots',
    () async {
      final base = await SharedPreferences.getInstance();
      final service = VideoNoteService(preferencesLoader: () async => base);
      await service.saveNote(note('a'));
      final failing = FailingPreferences(base, failOnWrite: 2);
      final failingService = VideoNoteService(
        preferencesLoader: () async => failing,
      );
      await expectLater(
        failingService.saveNote(note('a').copyWith(body: '新的内容')),
        throwsStateError,
      );
      expect((await service.loadNotes()).single.body, note('a').body);
    },
  );
  test(
    'legacy migration preserves text, timestamp, screenshot and original backup',
    () async {
      final old = note('old').toJson()
        ..remove('formatVersion')
        ..remove('attachments');
      old['framePath'] = 'old.png';
      final raw = jsonEncode([old]);
      SharedPreferences.setMockInitialValues({
        VideoNoteService.storageKey: raw,
      });
      final service = VideoNoteService();
      final migrated = (await service.loadNotes()).single;
      expect(migrated.body, contains(r'\# 标题'));
      expect(migrated.body, contains('focubili://video'));
      expect(migrated.attachments['images/legacy.png'], 'old.png');
      await service.saveNote(migrated);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VideoNoteService.legacyBackupKey), raw);
      expect((await service.loadNotes()).single.body, migrated.body);
    },
  );
  test(
    'more than 500 notes survive and concurrent writes are serialized',
    () async {
      final entries = List.generate(501, (i) => note('$i').toJson());
      SharedPreferences.setMockInitialValues({
        VideoNoteService.storageKey: jsonEncode(entries),
      });
      await Future.wait([
        VideoNoteService().saveNote(note('a')),
        VideoNoteService().saveNote(note('b')),
      ]);
      final notes = await VideoNoteService().loadNotes();
      expect(notes, hasLength(503));
      expect(notes.first.body, '# 标题\n\n  正文  ');
    },
  );
  test(
    'shared screenshot is retained until last reference is deleted',
    () async {
      final dir = await Directory.systemTemp.createTemp('focubili-notes-test');
      try {
        final image = File('${dir.path}/shared.png');
        await image.writeAsBytes([1, 2, 3]);
        final service = VideoNoteService();
        await service.saveNote(
          note('a', attachments: {'images/a.png': image.path}),
        );
        await service.saveNote(
          note('b', attachments: {'images/b.png': image.path}),
        );
        await service.deleteNote('a');
        expect(await image.exists(), isTrue);
        await service.deleteNote('b');
        expect(await image.exists(), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('damaged data is never overwritten on save', () async {
    SharedPreferences.setMockInitialValues({
      VideoNoteService.storageKey: 'broken',
    });
    await expectLater(
      VideoNoteService().saveNote(note('a')),
      throwsFormatException,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        VideoNoteService.storageKey,
      ),
      'broken',
    );
  });
}
