/// App 竖屏推荐流（/x/v2/feed/index/story）单条视频
class StoryItem {
  final int aid;
  final int cid;
  final String bvid;
  final String? title;
  final String? cover;
  final int duration;
  final int width;
  final int height;
  final int rotate;
  final StoryOwner owner;
  final StoryStat stat;
  final String? trackId;

  StoryItem({
    required this.aid,
    required this.cid,
    required this.bvid,
    this.title,
    this.cover,
    required this.duration,
    required this.width,
    required this.height,
    required this.rotate,
    required this.owner,
    required this.stat,
    this.trackId,
  });

  bool get isVertical => rotate == 1 ? width > height : height > width;

  /// 画面宽高比，未知时按竖屏 9:16
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 9 / 16;
    return rotate == 1 ? height / width : width / height;
  }

  /// 非视频卡片（直播、广告等）返回 null
  static StoryItem? fromJson(Map<String, dynamic> json) {
    if (json['goto'] != 'vertical_av') return null;
    final playerArgs = json['player_args'] as Map<String, dynamic>?;
    final aid = playerArgs?['aid'] as int?;
    final cid = playerArgs?['cid'] as int?;
    final bvid = json['bvid'] as String?;
    if (aid == null || cid == null || bvid == null) return null;
    final dimension = json['dimension'] as Map<String, dynamic>?;
    return StoryItem(
      aid: aid,
      cid: cid,
      bvid: bvid,
      title: json['title'],
      cover: json['cover'],
      duration: json['duration'] ?? 0,
      width: dimension?['width'] ?? 0,
      height: dimension?['height'] ?? 0,
      rotate: dimension?['rotate'] ?? 0,
      owner: StoryOwner.fromJson(json['owner'] ?? const {}),
      stat: StoryStat.fromJson(json['stat'] ?? const {}),
      trackId: json['track_id'],
    );
  }
}

class StoryOwner {
  final int? mid;
  final String? name;
  final String? face;

  const StoryOwner({this.mid, this.name, this.face});

  factory StoryOwner.fromJson(Map<String, dynamic> json) => StoryOwner(
    mid: json['mid'],
    name: json['name'],
    face: json['face'],
  );
}

class StoryStat {
  int like;
  final int reply;
  final int favorite;
  final int share;
  final int view;

  StoryStat({
    required this.like,
    required this.reply,
    required this.favorite,
    required this.share,
    required this.view,
  });

  factory StoryStat.fromJson(Map<String, dynamic> json) => StoryStat(
    like: json['like'] ?? 0,
    reply: json['reply'] ?? 0,
    favorite: json['favorite'] ?? 0,
    share: json['share'] ?? 0,
    view: json['view'] ?? 0,
  );
}
