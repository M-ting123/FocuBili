import 'package:flutter/material.dart';
import '../../services/app_favorites_service.dart';

/// Choose a local folder; the built-in learning folder is always available.
Future<String?> showNoteFolderPicker(
  BuildContext context,
  AppFavoritesService service,
) async {
  final folders = (await service.loadFolders()).toList();
  if (!folders.any(
    (folder) => folder.id == AppFavoritesService.learningNotesFolderId,
  )) {
    folders.insert(0, AppFavoritesService.learningNotesFolder);
  }
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('笔记收藏夹'),
      children: [
        for (final folder in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(folder.id),
            child: Text(folder.name),
          ),
      ],
    ),
  );
}
