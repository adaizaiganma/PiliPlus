import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/pages/story/controller.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 竖屏短视频：上下滑动切换，单击暂停，双击点赞，长按倍速
class StoryPage extends StatefulWidget {
  const StoryPage({super.key});

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  final _tag = Utils.generateRandomString(8);
  late final StoryController _controller;
  // 刷新后从第一条开始，不恢复旧的滚动位置
  final _pageController = PageController(keepPage: false);

  @override
  void initState() {
    super.initState();
    _controller = Get.put(StoryController(), tag: _tag);
  }

  @override
  void dispose() {
    _pageController.dispose();
    Get.delete<StoryController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: Obx(_buildBody)),
            _buildTopBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final items = _controller.items;
    if (items.isEmpty) {
      return switch (_controller.loadingState.value) {
        Loading() => const Center(child: CircularProgressIndicator()),
        Error(:final errMsg) => _message(errMsg ?? '加载失败', retry: true),
        Success() => _message('暂无视频', retry: true),
      };
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: items.length,
      onPageChanged: _controller.onPageChanged,
      itemBuilder: (context, index) => _StoryItemView(
        key: ValueKey(items[index].aid),
        controller: _controller,
        index: index,
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white70)),
          if (retry)
            TextButton(
              onPressed: _controller.onRefresh,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top,
      left: 0,
      right: 0,
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: Row(
          children: [
            const BackButton(color: Colors.white),
            const Text(
              '短视频',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            const Spacer(),
            Obx(
              () => IconButton(
                tooltip: _controller.onlyVertical.value ? '显示全部视频' : '只看竖屏',
                onPressed: _controller.toggleOnlyVertical,
                icon: Icon(
                  _controller.onlyVertical.value
                      ? Icons.stay_current_portrait
                      : Icons.stay_current_portrait_outlined,
                ),
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _controller.onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryItemView extends StatefulWidget {
  const _StoryItemView({
    super.key,
    required this.controller,
    required this.index,
  });

  final StoryController controller;
  final int index;

  @override
  State<_StoryItemView> createState() => _StoryItemViewState();
}

class _StoryItemViewState extends State<_StoryItemView> {
  StoryController get _controller => widget.controller;
  bool _speeding = false;

  StoryItem get _item => _controller.items[widget.index];

  void _toVideoPage() {
    final item = _item;
    _controller.pauseDuring(
      () => PageUtils.toVideoPage(
        aid: item.aid,
        bvid: item.bvid,
        cid: item.cid,
        cover: item.cover,
        title: item.title,
        isVertical: item.isVertical,
      ),
    );
  }

  void _toMemberPage() {
    final mid = _item.owner.mid;
    if (mid == null) return;
    _controller.pauseDuring(() => Get.toNamed('/member?mid=$mid'));
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _controller.togglePlay,
      onDoubleTap: () => _controller.toggleLike(onlyLike: true),
      onLongPressStart: (_) {
        _controller.setSpeed(2.0);
        setState(() => _speeding = true);
      },
      onLongPressEnd: (_) {
        _controller.setSpeed(1.0);
        setState(() => _speeding = false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCover(),
          _buildVideo(),
          _buildPauseIcon(),
          if (_speeding)
            Positioned(
              top: padding.top + 56,
              left: 0,
              right: 0,
              child: const Center(child: _Chip(text: '2x 倍速播放中')),
            ),
          Positioned(
            right: 8,
            bottom: padding.bottom + 96,
            child: _buildActions(),
          ),
          Positioned(
            left: 14,
            right: 88,
            bottom: padding.bottom + 22,
            child: _buildInfo(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: padding.bottom,
            child: _buildProgress(),
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final cover = _item.cover;
    if (cover == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width / _item.aspectRatio).clamp(
          0.0,
          constraints.maxHeight,
        );
        return Center(
          child: NetworkImgLayer(
            src: cover,
            width: width,
            height: height,
            fit: BoxFit.contain,
            borderRadius: BorderRadius.zero,
          ),
        );
      },
    );
  }

  Widget _buildVideo() {
    return Obx(() {
      _controller.slotVersion.value;
      final slot = _controller.slotOf(widget.index);
      if (slot == null || !slot.ready.value) {
        return const SizedBox.shrink();
      }
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SimpleVideo(controller: slot.videoController),
          ),
        ),
      );
    });
  }

  Widget _buildPauseIcon() {
    return Obx(
      () =>
          _controller.userPaused.value &&
              _controller.currentIndex.value == widget.index
          ? const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 80,
                color: Colors.white70,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildActions() {
    final item = _item;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toMemberPage,
          child: NetworkImgLayer(
            src: item.owner.face,
            width: 44,
            height: 44,
            type: .avatar,
          ),
        ),
        const SizedBox(height: 18),
        Obx(() {
          _controller.items.length;
          final liked = _controller.likedAids.contains(item.aid);
          return _ActionButton(
            icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
            color: liked ? Colors.pinkAccent : Colors.white,
            label: NumUtils.numFormat(item.stat.like),
            onTap: _controller.toggleLike,
          );
        }),
        _ActionButton(
          icon: Icons.comment_outlined,
          label: NumUtils.numFormat(item.stat.reply),
          onTap: _toVideoPage,
        ),
        _ActionButton(
          icon: Icons.share_outlined,
          label: '分享',
          onTap: () =>
              Utils.copyText('https://www.bilibili.com/video/${item.bvid}'),
        ),
        _ActionButton(
          icon: Icons.open_in_new,
          label: '详情',
          onTap: _toVideoPage,
        ),
      ],
    );
  }

  Widget _buildInfo() {
    final item = _item;
    const shadow = [Shadow(blurRadius: 4, color: Colors.black54)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toMemberPage,
          child: Text(
            '@${item.owner.name ?? ''}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              shadows: shadow,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.title ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, shadows: shadow),
        ),
        const SizedBox(height: 4),
        Text(
          '${NumUtils.numFormat(item.stat.view)}播放',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            shadows: shadow,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    return Obx(() {
      _controller.slotVersion.value;
      final slot = _controller.slotOf(widget.index);
      if (slot == null) return const SizedBox(height: 2);
      final player = slot.player;
      return StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, snapshot) {
          final total = player.state.duration.inMilliseconds;
          final position = (snapshot.data ?? Duration.zero).inMilliseconds;
          return LinearProgressIndicator(
            minHeight: 2,
            value: total > 0 ? (position / total).clamp(0.0, 1.0) : 0,
            backgroundColor: Colors.white24,
            color: Colors.white,
          );
        },
      );
    });
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
