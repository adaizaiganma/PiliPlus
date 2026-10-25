import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/story.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 一个可复用的播放器槽位：当前页和预载的下一页各占一个
class StorySlot {
  StorySlot(this.player, this.videoController) {
    _sizeSub = player.stream.size.listen((size) {
      if (size.$1 > 0) ready.value = true;
    });
  }

  final Player player;
  final VideoController videoController;
  late final StreamSubscription<(int, int)> _sizeSub;

  /// 当前装载的列表下标
  int? index;

  /// 已解码出画面，可以把封面换成视频
  final RxBool ready = false.obs;

  void dispose() {
    _sizeSub.cancel();
    player.dispose();
  }
}

class StoryController extends GetxController with WidgetsBindingObserver {
  static const _onlyVerticalKey = 'storyOnlyVertical';
  static const _slotCount = 2;
  static const _loadMoreThreshold = 3;

  /// 连续多页过滤后为空时停止自动续拉，避免频繁请求触发风控
  static const _maxEmptyStreak = 5;

  /// 从某个视频进入时作为推荐种子
  final int? seedAid = int.tryParse(Get.parameters['aid'] ?? '');

  final RxList<StoryItem> items = <StoryItem>[].obs;
  final Rx<LoadingState<void>> loadingState = LoadingState<void>.loading().obs;
  final RxInt currentIndex = 0.obs;
  final RxBool userPaused = false.obs;
  final RxBool onlyVertical =
      (GStorage.setting.get(_onlyVerticalKey, defaultValue: false) as bool).obs;
  final RxSet<int> likedAids = <int>{}.obs;

  /// 槽位与下标的对应关系变化时自增，供界面刷新
  final RxInt slotVersion = 0.obs;

  final List<StorySlot> _slots = [];
  final Map<int, (String, String?)> _urlCache = {};
  final Set<int> _seenAids = {};

  int _displayId = 1;
  int? _cursorAid;
  String? _trackId;
  bool _isLoadingMore = false;
  bool _isEnd = false;
  int _emptyStreak = 0;
  bool _routePaused = false;
  bool _closed = false;

  late final bool _enableHeart =
      Accounts.heartbeat.isLogin && !Pref.historyPause;

  StoryItem? get currentItem => items.elementAtOrNull(currentIndex.value);

  StorySlot? slotOf(int index) =>
      _slots.firstWhereOrNull((slot) => slot.index == index);

  StorySlot? get _currentSlot => slotOf(currentIndex.value);

  @override
  void onInit() {
    super.onInit();
    _cursorAid = seedAid;
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    await _initSlots();
    if (_closed) return;
    await queryData();
  }

  Future<void> _initSlots() async {
    final hwdec = Pref.enableHA ? Pref.hardwareDecoding : null;
    for (var i = 0; i < _slotCount; i++) {
      final player = await Player.create(
        configuration: PlayerConfiguration(
          logLevel: kDebugMode ? .warn : .error,
          options: {
            'video-sync': Pref.videoSync,
            if (Platform.isAndroid) 'ao': Pref.audioOutput,
            // 短视频循环播放
            'loop-file': 'inf',
          },
        ),
      );
      final videoController = await VideoController.create(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: hwdec != null,
          androidAttachSurfaceAfterVideoParameters: false,
          hwdec: hwdec,
        ),
      );
      if (Platform.isAndroid) {
        player.setProperty('force-window', 'no');
      }
      player.setMediaHeader(
        userAgent: BrowserUa.pc,
        referer: HttpString.baseUrl,
      );
      if (_closed) {
        player.dispose();
        return;
      }
      _slots.add(StorySlot(player, videoController));
    }
  }

  Future<void> queryData() async {
    if (_isLoadingMore || _isEnd) return;
    _isLoadingMore = true;
    final isFirst = items.isEmpty;
    final res = await StoryHttp.storyFeed(
      aid: _cursorAid,
      displayId: _displayId,
      trackId: _trackId,
    );
    _isLoadingMore = false;
    if (_closed) return;
    switch (res) {
      case Success(:final response):
        if (response.isEmpty) {
          _isEnd = items.isNotEmpty;
        } else {
          _displayId++;
          _cursorAid = response.last.aid;
          _trackId = response.last.trackId ?? _trackId;
        }
        final newItems = response
            .where(
              (e) =>
                  _seenAids.add(e.aid) && (!onlyVertical.value || e.isVertical),
            )
            .toList();
        items.addAll(newItems);
        loadingState.value = const Success(null);
        _emptyStreak = newItems.isEmpty ? _emptyStreak + 1 : 0;
        if (isFirst && items.isNotEmpty) {
          onPageChanged(0);
        } else if (_emptyStreak < _maxEmptyStreak &&
            items.length - currentIndex.value <= _loadMoreThreshold) {
          // 只看竖屏时一页可能全被过滤掉，继续拉
          queryData();
        } else {
          _preloadNext();
        }
      case Error():
        if (isFirst) loadingState.value = res;
        res.toast();
      case Loading():
        break;
    }
  }

  Future<void> onRefresh() async {
    _sendHeartBeat();
    for (final slot in _slots) {
      slot
        ..index = null
        ..ready.value = false;
      slot.player.stop();
    }
    slotVersion.value++;
    items.clear();
    _seenAids.clear();
    currentIndex.value = 0;
    _displayId = 1;
    _cursorAid = seedAid;
    _trackId = null;
    _isEnd = false;
    _emptyStreak = 0;
    loadingState.value = LoadingState<void>.loading();
    await queryData();
  }

  void onPageChanged(int index) {
    if (index != currentIndex.value) {
      _sendHeartBeat();
    }
    currentIndex.value = index;
    userPaused.value = false;
    _activate(index);
    _queryRelation(index);
    if (items.length - index <= _loadMoreThreshold) {
      queryData();
    }
  }

  /// 当前页用已预载的槽位直接播放，另一个槽位去预载下一页
  Future<void> _activate(int index) async {
    if (_slots.isEmpty) return;
    var slot = slotOf(index);
    for (final other in _slots) {
      if (other != slot) other.player.pause();
    }
    if (slot == null) {
      slot = _pickSlot(index);
      await _load(slot, index);
    } else if (_canPlay(index)) {
      slot.player.play();
    }
    _preloadNext();
  }

  void _preloadNext() {
    final next = currentIndex.value + 1;
    if (next >= items.length || slotOf(next) != null || _slots.length < 2) {
      return;
    }
    _load(_pickSlot(next), next);
  }

  /// 优先选离当前页最远（不再需要）的槽位
  StorySlot _pickSlot(int target) {
    final current = currentIndex.value;
    StorySlot? best;
    var bestDistance = -1;
    for (final slot in _slots) {
      final idx = slot.index;
      if (idx == current && target != current) continue;
      final distance = idx == null ? 1 << 30 : (idx - current).abs();
      if (distance > bestDistance) {
        best = slot;
        bestDistance = distance;
      }
    }
    return best ?? _slots.first;
  }

  bool _canPlay(int index) =>
      index == currentIndex.value &&
      !userPaused.value &&
      !_routePaused &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;

  Future<void> _load(StorySlot slot, int index) async {
    slot
      ..index = index
      ..ready.value = false;
    slotVersion.value++;
    await slot.player.stop();
    final item = items.elementAtOrNull(index);
    if (item == null) return;
    final urls = await _resolveUrls(item);
    // 等待取流期间槽位可能已被挪作他用
    if (_closed || slot.index != index) return;
    if (urls == null) {
      if (index == currentIndex.value) {
        SmartDialog.showToast('获取播放地址失败');
      }
      return;
    }
    final (video, audio) = urls;
    final source = audio == null || audio.isEmpty
        ? video
        : 'edl://!no_chapters;%${video.length}%$video;'
              '!new_stream;!no_chapters;%${audio.length}%$audio';
    await slot.player.open(
      Media(source, extras: Pref.initBuffer()),
      play: false,
    );
    if (_closed || slot.index != index) return;
    if (_canPlay(index)) slot.player.play();
  }

  Future<(String, String?)?> _resolveUrls(StoryItem item) async {
    if (_urlCache[item.aid] case final cached?) return cached;
    final isWiFi = await ConnectivityUtils.isWiFi;
    final qn = isWiFi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;
    final res = await VideoHttp.videoUrl(
      avid: item.aid,
      bvid: item.bvid,
      cid: item.cid,
      qn: qn,
      tryLook: !Accounts.get(AccountType.video).isLogin && Pref.p1080,
      videoType: VideoType.ugc,
    );
    if (res case Success(:final response)) {
      final videos = response.dash?.video;
      final formats = response.supportFormats;
      if (videos != null && videos.isNotEmpty && formats != null) {
        final (_, _, _, targetVideo) = VideoUtils.findTargetVideo(
          videos,
          qn,
          response.acceptQuality,
          formats,
          isWiFi ? Pref.preferCodecs : Pref.preferCodecsCellular,
        );
        String? audioUrl;
        if (response.dash!.audio case final audios? when audios.isNotEmpty) {
          final targetAudio = VideoUtils.findTargetAudio(
            audios,
            isWiFi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular,
          );
          audioUrl = VideoUtils.getCdnUrl(targetAudio.playUrls, isAudio: true);
        }
        return _urlCache[item.aid] = (
          VideoUtils.getCdnUrl(targetVideo.playUrls),
          audioUrl,
        );
      }
      if (response.durl?.firstOrNull?.url case final url?) {
        return _urlCache[item.aid] = (url, null);
      }
    }
    return null;
  }

  Future<void> _queryRelation(int index) async {
    if (!Accounts.main.isLogin) return;
    final item = items.elementAtOrNull(index);
    if (item == null) return;
    final res = await VideoHttp.videoRelation(bvid: item.bvid);
    if (res case Success(:final response)) {
      if (response.like == true) {
        likedAids.add(item.aid);
      } else {
        likedAids.remove(item.aid);
      }
    }
  }

  void togglePlay() {
    final player = _currentSlot?.player;
    if (player == null) return;
    if (player.state.playing) {
      userPaused.value = true;
      player.pause();
    } else {
      userPaused.value = false;
      player.play();
    }
  }

  void setSpeed(double speed) => _currentSlot?.player.setRate(speed);

  Future<void> toggleLike({bool onlyLike = false}) async {
    final item = currentItem;
    if (item == null) return;
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final liked = likedAids.contains(item.aid);
    if (onlyLike && liked) return;
    final res = await VideoHttp.likeVideo(bvid: item.bvid, type: liked);
    if (res case Success()) {
      if (liked) {
        likedAids.remove(item.aid);
        item.stat.like--;
      } else {
        likedAids.add(item.aid);
        item.stat.like++;
      }
      items.refresh();
    } else {
      res.toast();
    }
  }

  void toggleOnlyVertical() {
    onlyVertical.value = !onlyVertical.value;
    GStorage.setting.put(_onlyVerticalKey, onlyVertical.value);
    SmartDialog.showToast(onlyVertical.value ? '只看竖屏视频' : '显示全部视频');
    onRefresh();
  }

  /// 跳转其他页面时暂停，返回后恢复
  Future<T?> pauseDuring<T>(Future<T?>? Function() navigate) async {
    _routePaused = true;
    _currentSlot?.player.pause();
    final result = await navigate();
    _routePaused = false;
    if (!_closed && _canPlay(currentIndex.value)) {
      _currentSlot?.player.play();
    }
    return result;
  }

  void _sendHeartBeat() {
    if (!_enableHeart) return;
    final item = currentItem;
    final slot = _currentSlot;
    if (item == null || slot == null) return;
    final progress = slot.player.state.position.inSeconds;
    if (progress <= 0) return;
    VideoHttp.heartBeat(
      aid: item.aid,
      bvid: item.bvid,
      cid: item.cid,
      progress: progress,
      videoType: VideoType.ugc,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _sendHeartBeat();
        _currentSlot?.player.pause();
      case AppLifecycleState.resumed:
        if (_canPlay(currentIndex.value)) _currentSlot?.player.play();
      default:
        break;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _sendHeartBeat();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    for (final slot in _slots) {
      slot.dispose();
    }
    _slots.clear();
    super.onClose();
  }
}
