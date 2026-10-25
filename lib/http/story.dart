import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:dio/dio.dart';

abstract final class StoryHttp {
  static const String _storyFeed =
      '${HttpString.appBaseUrl}/x/v2/feed/index/story';

  /// 竖屏推荐流，app 签名与 access_key 由拦截器注入
  /// [aid] 种子视频（翻页时传上一页最后一条），[displayId] 从 1 递增
  static Future<LoadingState<List<StoryItem>>> storyFeed({
    int? aid,
    required int displayId,
    String? trackId,
  }) async {
    final params = {
      'aid': ?aid,
      'build': 8430300,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'disable_rcmd': 0,
      'display_id': displayId,
      'fnval': 4048,
      'fnver': 0,
      'force_host': 2,
      'fourk': 1,
      'mobi_app': 'android',
      'network': 'wifi',
      'platform': 'android',
      'player_net': 1,
      'pull': displayId == 1 ? 1 : 0,
      'qn': 32,
      'request_from': 1,
      's_locale': 'zh_CN',
      'spmid': 'main.ugc-video-detail-vertical.0.0',
      'statistics': Constants.statisticsApp,
      'trackid': ?trackId,
    };
    final res = await Request().get(
      _storyFeed,
      queryParameters: params,
      options: Options(
        headers: {
          'bili-http-engine': 'cronet',
          'user-agent': Constants.userAgentApp,
        },
        extra: {'account': Accounts.get(AccountType.recommend)},
      ),
    );
    if (res.data['code'] == 0) {
      final items = res.data['data']?['items'] as List?;
      return Success([
        ...?items
            ?.map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
            .nonNulls,
      ]);
    } else {
      return Error(res.data['message']);
    }
  }
}
