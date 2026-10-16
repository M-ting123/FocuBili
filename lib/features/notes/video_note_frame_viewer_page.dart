import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// 以黑色背景全屏显示一张笔记视频截图，并允许缩放和平移。
class VideoNoteFrameViewerPage extends StatefulWidget {
  /// 创建只读取本机截图文件的全屏浏览页。
  const VideoNoteFrameViewerPage({super.key, required this.framePath});

  final String framePath;

  /// 创建负责读取原图尺寸和保存缩放矩阵的全屏截图浏览状态。
  @override
  State<VideoNoteFrameViewerPage> createState() =>
      _VideoNoteFrameViewerPageState();
}

/// 使用专用图片查看器承载截图，统一处理居中、双指、双击和平移边界。
class _VideoNoteFrameViewerPageState extends State<VideoNoteFrameViewerPage> {
  late final PhotoViewController _photoController;
  late final PhotoViewScaleStateController _scaleStateController;

  /// 页面创建时建立图片位置与缩放状态控制器，供重置按钮恢复完整居中。
  @override
  void initState() {
    super.initState();
    _photoController = PhotoViewController();
    _scaleStateController = PhotoViewScaleStateController();
  }

  /// 将位置、倍率和双击循环状态一起恢复为“整张图片居中显示”。
  void _resetZoom() {
    _photoController.reset();
    _scaleStateController.reset();
  }

  /// 页面销毁时释放图片查看器控制器，避免退出后继续持有手势状态流。
  @override
  void dispose() {
    _photoController.dispose();
    _scaleStateController.dispose();
    super.dispose();
  }

  /// 构建全屏图片查看器；初始完整居中，双击和双指缩放都由 PhotoView 处理。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: PhotoView(
              key: const Key('fullscreen-note-frame-viewer'),
              imageProvider: FileImage(File(widget.framePath)),
              controller: _photoController,
              scaleStateController: _scaleStateController,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              basePosition: Alignment.center,
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.contained * 6,
              strictScale: true,
              enablePanAlways: false,
              filterQuality: FilterQuality.high,
              gestureDetectorBehavior: HitTestBehavior.opaque,
              semanticLabel: '时间点笔记视频截图',
              // 截图加载函数在大文件解码期间显示居中进度，不闪烁旧画面。
              loadingBuilder:
                  (BuildContext context, ImageChunkEvent? progress) => Center(
                    child: CircularProgressIndicator(
                      value:
                          progress?.expectedTotalBytes == null ||
                              progress!.expectedTotalBytes == 0
                          ? null
                          : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                    ),
                  ),
              // 全屏截图错误函数在文件缺失或损坏时显示说明并保留返回能力。
              errorBuilder:
                  (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) => const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text(
                        '截图文件不存在或已损坏',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    IconButton.filledTonal(
                      key: const Key('close-fullscreen-note-frame'),
                      // 关闭函数返回笔记详情页，不修改截图或文字笔记。
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const Key('reset-fullscreen-note-frame-zoom'),
                      // 重置函数恢复 PhotoView 的初始倍率与精确中心位置。
                      onPressed: _resetZoom,
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      tooltip: '重置缩放',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
