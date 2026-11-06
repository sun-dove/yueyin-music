# 自定义音源 HTTP 接入协议

适用版本：同款音乐 0.2.0、0.3.0 的 HTTP 配置。日期：2026-11-01。

## 用户配置

0.3.0 入口为“我的 → 自定义音源 → HTTP 音源设置”。填写名称、HTTPS 服务根地址，选择 QQ 音乐或网易云，按需填写访问令牌、1–60 秒超时。默认关闭，下载单独授权。保存并开启后，只在官方明确返回歌曲、会员或音质不可用时尝试该服务。

此处需要实现本协议的服务地址，不是 GitHub 仓库地址、`.js` 下载地址或单首歌曲地址。0.3.0 新增独立的“音源链接导入”页面，可运行受支持的洛雪脚本；两种协议互不混用。兼容范围见《洛雪音源兼容-调研与补充设计》。当前交付不包含已部署的 HTTP 音源服务。

## 请求

对于配置 `https://source.example/api`，客户端发送 `POST https://source.example/api/v1/resolve`。发送 JSON，有令牌时附 `Authorization: Bearer <用户填写的令牌>`。不发送 QQ/网易云会话、二维码、平台 Cookie 或本地文件路径。

```json
{
  "requestId": "每次请求的标识",
  "platform": "qq",
  "song": {"id": "歌曲ID", "title": "歌曲名", "artists": ["歌手"], "album": "专辑"},
  "quality": "high",
  "purpose": "play"
}
```

- `platform` 为 `qq` 或 `netease`，ID 使用对应平台的歌曲 ID。
- `quality` 使用 `low`、`medium`、`high`、`lossless`、`hires`、`spatial`、`dolby`、`master` 枚举。
- `purpose` 为 `play` 或 `download`；下载开关缺省关闭。
- 连接测试使用 `requestId=connection-test`、`song.id=connection-test`、`quality=low`、`purpose=play`。服务需要识别这个保留请求，返回协议有效的测试结果。客户端不播放测试 URL，“连接成功”只表示本次协议校验成功。

## 成功响应

HTTP 2xx，JSON 对象：

```json
{
  "url": "https://media.example/audio.mp3",
  "quality": "high",
  "format": "mp3",
  "bitrate": 320000,
  "expiresAt": "2030-01-01T00:00:00Z"
}
```

`url` 和 `quality` 必填；URL 必须为 HTTPS 且不含用户名/密码。`format`、`bitrate`（bit/s）、`expiresAt` 可选。缺少规格时不伪造规格；服务声明的规格不等于客户端对音频文件做过媒体检测。有效期出现时必须可解析且晚于当前时间。实际档位低于请求档位时客户端拒绝结果。

示例域名和日期仅说明格式，没有内置可播放音频或运营中的音源服务。

## 错误响应

使用非 2xx 状态，返回 JSON 对象：

```json
{
  "error": {
    "code": "not_found",
    "message": "当前音源没有这首歌",
    "retryable": false
  }
}
```

| HTTP 状态或错误码 | 含义 |
| --- | --- |
| 401 / 403，`unauthorized` | 认证失败 |
| 404，`not_found` | 没有对应歌曲 |
| 429，`rate_limited` | 请求过于频繁 |
| 5xx，`source_unavailable` | 服务暂时不可用 |
| 422，`quality_unavailable` | 当前音质不可用 |
| 422，`timeout` | 上游超时 |
| 其他状态/未知结构，`invalid_response` | 协议不兼容 |

0.2.0 要求错误体也为 JSON；HTML 错误页会显示协议不兼容。错误文案只应包含用户需要的说明，不要回显令牌、Cookie 或内部堆栈。客户端不跟随重定向，服务应直接响应最终地址。解析前检查 UTF-8 响应是否大于 64 KiB；当前检查发生在响应接收后，不是传输层的内存上限。

## 当前验收与限制

配置、安全存储、固定数据协议响应、官方回退矩阵、取消/迟到响应、下载用途和设置页有正式自动化门；模拟器结果与真实服务未验证项见逐门报告。

没有提供实现本协议的真实服务，因此不声称仓库里的任一音源、任一会员歌曲或真实无损音频已经接入。真实内容与返回歌曲是否匹配，需要实际试听验证。
