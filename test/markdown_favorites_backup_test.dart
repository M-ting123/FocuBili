import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focubili/models/app_favorites_backup.dart';
import 'package:focubili/models/video_note.dart';
import 'package:focubili/services/app_favorites_service.dart';

VideoNote document(
  String folderId, {
  Map<String, String> attachments = const {},
}) => VideoNote(
  id: 'document',
  bvid: 'BV1GJ411x7h7',
  videoTitle: '课程',
  ownerName: '老师',
  partCid: 100,
  partPageNumber: 1,
  partTitle: '第一课',
  title: '笔记',
  body: '# 课程\n![截图](images/a.png)',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  position: Duration.zero,
  folderId: folderId,
  attachments: attachments,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'folder backup restores Markdown, image bytes and folder identity',
    () async {
      final dir = await Directory.systemTemp.createTemp('note-backup');
      try {
        final service = AppFavoritesService(
          noteAssetDirectoryLoader: () async => dir,
        );
        final folder = (await service.createFolder('课程笔记'))!;
        final image = File('${dir.path}/original.png');
        await image.writeAsBytes([1, 2, 3]);
        await service.noteService.saveNote(
          document(folder.id, attachments: {'images/a.png': image.path}),
        );
        final backup = await service.exportBackup();
        expect(backup.notes, hasLength(1));
        expect(backup.fileName, endsWith('.zip'));
        final decoded = AppFavoritesBackup.fromBytes(backup.toBytes());
        SharedPreferences.setMockInitialValues({});
        final imported = await service.importBackup(decoded);
        expect(imported.importedNotes, 1);
        final restored = (await service.noteService.loadNotes()).single;
        expect(restored.folderId, folder.id);
        expect(restored.body, '# 课程\n![截图](images/a.png)');
        expect(
          await File(restored.attachments['images/a.png']!).readAsBytes(),
          [1, 2, 3],
        );
        expect(restored.attachments['images/a.png'], isNot(image.path));
        expect((await service.importBackup(decoded)).duplicates, 1);
        expect(await service.noteService.loadNotes(), hasLength(1));
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'deleting a folder moves documents into the built-in learning folder',
    () async {
      final service = AppFavoritesService();
      final folder = (await service.createFolder('旧目录'))!;
      await service.noteService.saveNote(document(folder.id));
      expect(await service.deleteFolder(folder.id), isTrue);
      expect(
        (await service.noteService.loadNotes()).single.folderId,
        'learning-notes',
      );
      expect((await service.loadFolders()).single.name, '学习笔记');
      expect(await service.deleteFolder('learning-notes'), isFalse);
    },
  );
  test(
    'ZIP backup rejects traversal paths before extracting any attachment',
    () {
      final zip = ZipEncoder().encodeBytes(
        Archive()
          ..add(ArchiveFile.string('favorites.json', '{}'))
          ..add(ArchiveFile.bytes('../outside.png', [1])),
      );
      expect(() => AppFavoritesBackup.fromBytes(zip), throwsFormatException);
    },
  );
}
