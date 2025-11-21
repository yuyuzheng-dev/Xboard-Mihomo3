# 离线启动白屏问题 & VPN 面板公告刷新改进说明

本次改动主要解决两个问题：

1. **应用在无网络环境下启动时长时间白屏**（Flutter 还未启动，什么都看不到）
2. **首页左上角公告按钮不会主动重新拉取公告**，公告更新后用户无法及时看到

---

## 一、无网络启动白屏问题

### 1.1 问题现象

- 之前在 `main()` 中会**同步等待**以下初始化逻辑：
  - 从远程配置源拉取 XBoard 配置（`RemoteConfigManager.fetchAllConfigs`）
  - 基于配置做域名竞速（`DomainRacingService.raceSelectFastestDomain`）
  - 使用最快域名初始化底层 `flutter_xboard_sdk`（`XBoardSDK.initialize`）
  - 基于配置初始化 `RemoteTaskManager` WebSocket 服务
- 当网络不可用或非常差时：
  - 这些步骤要经历多次重试和超时，可能耗时几十秒
  - 此时 **Flutter 尚未执行 `runApp`，系统只显示纯白启动页** ⇒ 用户主观感觉就是“打开应用一直白屏不动”

### 1.2 核心思路：把重网络初始化延后到 Flutter 启动之后

现在的策略是：

- `main()` 只做 **本地、快速** 的初始化，然后立刻 `runApp`：
  - 读系统版本、预加载 clash core 等
  - 不再在这里拉取远程配置、做域名竞速或初始化 XBoard SDK
- 所有 XBoard 相关的网络初始化统一交给 **`XBoardSDK.ensureInitialized()` 延迟执行**，并且只在真正需要访问面板 API 时才触发。

### 1.3 具体代码改动

#### 1）`lib/main.dart`

- 删除：
  - `_initializeXBoardServices()` 及 `_loadSecurityConfig()` 两个函数
  - `remoteTaskManager` 全局变量及启动逻辑
  - 启动阶段对 `XBoardConfig.initialize` / `XBoardSDK.initialize` / `RemoteTaskManager.create()` 的等待
- 保留且简化后的启动流程：

```dart
Future<void> main() async {
  globalState.isService = false;
  WidgetsFlutterBinding.ensureInitialized();

  final version = await system.version;
  await clashCore.preload();
  await globalState.initApp(version);
  await android?.init();
  await window?.init(version);
  HttpOverrides.global = FlClashHttpOverrides();

  WidgetsBinding.instance.addObserver(AppLifecycleObserver());

  runApp(
    ProviderScope(
      child: const Application(),
    ),
  );
}
```

- `AppLifecycleObserver` 只负责在应用真正退出时释放 XBoard 相关资源：

```dart
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      XBoardSDK.dispose(); // 内部会同时关闭 RemoteTaskManager
      print('应用生命周期状态改变: $state, 所有服务资源已释放。');
    }
  }
}
```

#### 2）`lib/xboard/sdk/xboard_sdk.dart`

新增了统一的延迟初始化入口：

```dart
class XBoardSDK {
  static Completer<void>? _initCompleter;
  static RemoteTaskManager? _remoteTaskManager;

  /// 对外暴露的延迟初始化方法
  static Future<void> ensureInitialized() => _ensureInitialized();

  static Future<void> _ensureInitialized() async {
    if (isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      // 1. 从配置文件加载安全配置（证书路径等），配置域名竞速 CA
      await _configureSecurity();

      // 2. 初始化 XBoardConfig（从 assets/config/xboard.config.yaml 读取）
      if (!XBoardConfig.isInitialized) {
        final settings = await ConfigFileLoader.loadFromFile();
        await XBoardConfig.initialize(settings: settings);
      }

      // 3. 通过配置模块做域名竞速，选出最快面板域名
      String? baseUrl;
      try {
        baseUrl = await XBoardConfig.getFastestPanelUrl();
      } catch (e) {
        baseUrl = XBoardConfig.panelUrl;
      }

      // 4. 使用选出的域名初始化底层 flutter_xboard_sdk
      await initialize(
        configProvider: XBoardConfig.provider,
        baseUrl: baseUrl,
        strategy: baseUrl != null ? 'first' : 'race_fastest',
      );

      // 5. 基于配置初始化 RemoteTaskManager（WebSocket 远程任务/订阅刷新推送）
      try {
        _remoteTaskManager = await RemoteTaskManager.create();
        if (_remoteTaskManager != null) {
          _remoteTaskManager!.initialize();
          _remoteTaskManager!.start();
        }
      } catch (e) {
        _logger.error('[SDK] RemoteTaskManager 初始化异常', e);
      }

      _initCompleter!.complete();
    } catch (e, stack) {
      _logger.error('[SDK] 延迟初始化失败', e);
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.completeError(e, stack);
      }
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  static Future<void> _configureSecurity() async { /* 证书路径加载逻辑 */ }

  static void dispose() {
    _remoteTaskManager?.dispose();
    _remoteTaskManager = null;
    _client.dispose();
  }
  // ...
}
```

并且对所有对外异步方法（如 `login` / `getUserInfo` / `getSubscription` / `getPlans` / 支付、工单、公告等）统一在方法起始处调用：

```dart
await _ensureInitialized();
```

例如：

```dart
static Future<bool> login({
  required String email,
  required String password,
}) async {
  await _ensureInitialized();
  // 之后才真正调用 _sdk.loginWithCredentials(...)
}
```

这样，无论是启动阶段的 `quickAuth()`，还是后续登录、支付、邀请、公告等功能，
都会在真正访问面板 API 之前，自动确保 SDK 与配置已经正确初始化。

#### 3）`lib/xboard/features/domain_status/services/domain_status_service.dart`

- 原来在 `initialize()` 中手动调用 `XBoardConfig.initialize()`，现在改为依赖
  `XBoardSDK.ensureInitialized()`，由 SDK 统一完成配置与域名相关初始化：

```dart
Future<void> initialize() async {
  if (_isInitialized) return;
  try {
    XBoardLogger.info('开始初始化');
    await XBoardSDK.ensureInitialized();
    _isInitialized = true;
    XBoardLogger.info('初始化完成');
  } catch (e) {
    XBoardLogger.error('初始化失败', e);
    rethrow;
  }
}
```

- `_initializeXBoardService` 也改为调用 `ensureInitialized()`，不再直接重复调用
  `XBoardSDK.initialize(...)`：

```dart
Future<void> _initializeXBoardService(String domain) async {
  try {
    XBoardLogger.info('初始化XBoard服务: $domain');
    await XBoardSDK.ensureInitialized();
    XBoardLogger.info('XBoard服务初始化成功');
  } catch (e) {
    XBoardLogger.error('XBoard服务初始化失败', e);
  }
}
```

### 1.4 效果

- **无网络启动时不再出现长时间纯白屏**：
  - Flutter 会立即 `runApp`，展示已有的 `/loading` 品牌化加载页
  - 所有需要访问面板的初始化（配置拉取、域名竞速、SDK 初始化）都在 Loading 页内部完成
- 即使远程配置或网络很慢：
  - 用户看到的是“XBoard 加载中”的界面，而不是系统级白屏
  - 失败时会按照原有逻辑走本地缓存恢复 / 进入登录页等流程

---

## 二、VPN 面板左上角公告按钮改进

### 2.1 问题现象

- 组件路径：`lib/xboard/features/subscription/widgets/xboard_vpn_panel.dart`
- 左上角公告图标原逻辑：
  - 如果本地 `noticeProvider` 还没有公告，就触发一次 `fetchNotices()` 拉取
  - 如果已经有公告，则 **直接打开当前缓存的公告列表**
- 问题：
  - 点击图标不会强制刷新公告
  - 服务端公告更新后，客户端若不重启，很难第一时间获取到最新公告
  - 当确实没有公告时，点击图标也没有任何反馈

### 2.2 新的交互逻辑

修改方法：`_buildNoticeIcon`。

**关键变化：**

```dart
Widget _buildNoticeIcon(BuildContext context) {
  return Consumer(builder: (context, ref, _) {
    final noticeState = ref.watch(noticeProvider);
    final notices = noticeState.visibleNotices;
    final hasNotices = notices.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          // 每次点击都主动刷新公告，确保获取最新内容
          await ref.read(noticeProvider.notifier).fetchNotices();

          if (!mounted) return;

          final updatedState = ref.read(noticeProvider);
          final updatedNotices = updatedState.visibleNotices;

          if (updatedState.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('公告获取失败，请检查网络后重试'),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }

          if (updatedNotices.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('暂无公告'),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            _showNoticesBottomSheet(context, updatedNotices);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.campaign_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (hasNotices)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  });
}
```

### 2.3 行为总结

1. **每次点击都会重新请求公告数据**：
   - 无论当前是否已有公告缓存，都会调用
     `noticeProvider.notifier.fetchNotices()`
   - 确保公告内容可以被即时刷新

2. **请求成功但没有任何公告**：
   - 通过 `SnackBar` 给出明确提示：`"暂无公告"`

3. **请求失败**（网络异常或服务端错误）：
   - 通过 `SnackBar` 提示：`"公告获取失败，请检查网络后重试"`

4. **仍然保留原有红点提示逻辑**：
   - 只要 `visibleNotices.isNotEmpty`，图标右上角仍会显示红点
   - 红点不依赖本次点击是否成功拉取，只表示“当前有可见公告”

---

## 三、小结

- 启动阶段：
  - 通过将 XBoard 初始化从 `main()` 挪到 `XBoardSDK.ensureInitialized()`，
    避免了无网络时长时间系统级白屏，所有耗时操作都转移到 Loading 页内部完成。
- 公告体验：
  - VPN 面板左上角公告按钮现在**每次点击都会即时刷新公告**，
    并在“无公告”或“拉取失败”时给出明确的用户反馈文案。

如需在其它模块（如支付、邀请、在线客服等）中使用相同的“延迟初始化 + 自动刷新 + 失败提示”模式，可以参考本次在 `XBoardSDK` 与 `noticeProvider` 上的改动方式进行扩展。
