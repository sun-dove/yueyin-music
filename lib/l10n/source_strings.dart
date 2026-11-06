/// 多音源独立入口的中文资源，与既有 VideoStrings 使用同一维护方式。
abstract final class SourceStrings {
  static const qqMetadataMissing = 'QQ歌曲信息不完整，请重新同步收藏后重试。';
  static const qqPlaybackError = 'QQ播放接口返回错误，请稍后重试。';
  static const qualityAbove = '音源与音质详情见上方';
  static const attemptDetails = '音源尝试详情';
  static const close = '关闭';
  static const details = '查看详情';
  static const continueSources = '继续尝试剩余音源';
  static const highest = '最高可用音质';
  static const highestHint = '各音源先尝试高档位，失败后再降档';
  static const operationFailed = '操作失败，请重试；原设置尚未被替换。';
  static const initialized = '已初始化，歌曲播放待验证';
  static const imported = '导入成功，请启用需要的音源并保存。';
  static const saveToApply = '保存后生效。';
  static const cancel = '取消';
  static const remove = '删除';
  static const management = '多音源管理';
  static const intro = '保存多个音源，按需要选择播放顺序与音质。';
  static const scriptLink = '音源脚本链接';
  static const busy = '处理中…';
  static const importLink = '从链接导入';
  static const recommended = '使用推荐设置';
  static const autoSwitch = '失败自动切换音源';
  static const autoSwitchHint = '保持当前歌曲，继续尝试其他已启用音源';
  static const highestSourceHint = '先在各源尝试高音质，再明确提示降档';
  static const sourceFirst = '音源优先';
  static const sourceFirstHint = '同档位先尝试自定义源，再尝试官方';
  static const officialFirstHint = '同档位先尝试官方，再尝试自定义源';
  static const empty = '尚未导入音源，仍可尝试官方播放。';
  static const declarationHint = '音源声明支持某个档位，不代表每首歌都能取得该音质。实际来源及失败原因会在播放时显示。';
  static const save = '保存设置';
  static const httpSettings = 'HTTP 音源设置';
  static const qq = 'QQ音乐';
  static const netease = '网易云';
  static const savedUnverified = '已保存，实际播放待验证';
  static const enable = '启用';
  static const allowDownload = '允许用于下载';
  static const prefer = '设为首选';
  static const moveUp = '上移';
  static const moveDown = '下移';
  static const update = '更新';
  static const inspect = '检查初始化';
  static const inspectPassed = '初始化通过，实际播放待验证';
  static const requestCancelled = '音源请求已取消';
  static const resolveFailed = '音源取流失败，未返回当前歌曲所请求的音质';
  static const invalidUrl = '音源未返回有效的音频地址';
  static const invalidCollection = '音源列表格式不兼容';
  static const collectionLoadFailed = '音源列表读取失败，已显示旧版首选音源。原列表仍保留，请确认后重新保存。';
  static const timeout = '请求超时';
  static const userCancelled = '用户已取消';
  static const sourceUnavailable = '该源本轮不可用';
  static const duplicateUrl = '该地址已经加载失败';
  static const resolutionEnded = '本次解析结束';
  static const resolving = '正在取流';
  static const resolved = '已取地址，正在加载';
  static const playing = '已加载播放';
  static const cancelled = '已取消';
  static const inapplicable = '不适用';
  static const failed = '失败';
  static const oldRequestCancelled = '旧播放请求已取消';
  static const invalidAudio = '该地址已经失效或加载失败';
  static const loadBudgetUsed = '本轮加载预算已用完';
  static const loadCancelled = '已取消加载';
  static const downshift = '较高档位暂不可用，';
  static const qualityUnverified = '音质待验证';
  static const preparing = '准备音源…';
  static const switching = '正在切换音源…';
  static const budgetUsed = '本轮等待已达上限，可继续尝试剩余音源。';
  static const noPlayback = '当前歌曲未能播放，请查看音源尝试详情。';
  static const loadFailed = '音频未能加载';
  static const paused = '已暂停';
  static String downloadTimeout(int remaining, String summary) =>
      '本轮下载取流已超时，仍有 $remaining 个组合未尝试。请在音源设置中调整首选后重试。\n$summary';
  static String downloadFailed(String summary) => '下载音源均未返回可用地址。\n$summary';
  static String sourceCount(int count, int enabled) =>
      '$count 个音源 · $enabled 个启用';
  static String deleteNamed(String name) => '删除“$name”？';
  static String savedCount(int count) => '音源列表 $count 个（保存后生效）';
  static String version(String version, bool preferred) =>
      '版本 $version${preferred ? ' · 首选' : ''}';
  static String inspectFailed(String message) => '初始化失败：$message';
  static String downloadDisabled(String name) => '$name：未允许下载，不参与';
  static String platformUnsupported(String name, String platform) =>
      '$name：未声明支持$platform，不参与';
  static String qualityUnsupported(String name, String quality) =>
      '$name · $quality：未声明支持，不参与';
  static String remaining(int remaining) =>
      '本轮等待已达上限，还有 $remaining 个音源/音质组合未尝试，可继续尝试。';
  static String notTried(String label) => '$label：未尝试';
  static String bitrate(int kbps) => '$kbps kbps（接口返回）';
  static String trying(String notice, String label) => '$notice正在尝试 $label';
  static String loading(String label) => '正在加载 $label';
  static String playback(
    String notice,
    String name,
    String quality,
    String evidence,
    bool seekFailed,
  ) =>
      '$notice$name · 请求$quality · $evidence${seekFailed ? ' · 无法恢复进度，从头播放' : ''}';
}
