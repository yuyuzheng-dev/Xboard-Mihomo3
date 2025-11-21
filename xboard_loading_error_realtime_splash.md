# XBoard 订阅用量加载 / 错误处理 / 实时更新 / 启动体验改进说明

本文档说明本次在 XBoard Mihomo 客户端中围绕以下四个方面所做的改进：

1. 订阅用量卡片（`SubscriptionUsageCard`）的加载与错误展示
2. 更明确的错误提示与手动重试能力
3. 基于 WebSocket 的订阅信息被动刷新机制
4. 启动阶段的全局 Splash/Loading 优化与首次数据同步策略

---

## 1. 订阅用量卡片：显式加载状态与 AsyncValue

**涉及文件：**
- `lib/xboard/features/subscription/widgets/subscription_usage_card.dart`

### 1.1 使用 AsyncValue 封装空数据时的加载/错误/正常态

`SubscriptionUsageCard` 之前只根据传入的 `subscriptionInfo` / `userInfo` / `profileSubscriptionInfo`
是否为 `null` 来决定展示“空卡片”或“用量卡片”，未显式区分：

- 正在从网络/本地加载
- 加载失败
- 确认没有任何订阅数据

现在在 `build` 方法中引入了 Riverpod 的 `AsyncValue` 概念，对“尚无任何数据”的场景做统一封装：

- **Loading：**
  - 条件：`!hasSubscriptionData && userState.isLoading`
  - UI：调用 `_buildLoadingCard(...)` 展示一张带骨架条 + 圆形进度条的加载卡片，
    代替之前直接看到空白或旧数据的体验。

- **Error：**
  - 条件：`!hasSubscriptionData && userState.errorMessage != null` 且非 `TOKEN_EXPIRED`
  - UI：`AsyncValue.error` 分支调用 `_buildErrorCard(...)`，
    展示“加载失败 + 错误详情 + 重试按钮”的完整错误卡片。

- **Data（无数据但无错误）：**
  - 条件：`!hasSubscriptionData && !isLoading && error == null`
  - UI：保持原有的 `_buildEmptyCard(...)`，提示“暂无套餐信息，请登录后查看”。

通过 `AsyncValue.when`，组件内部逻辑在“没有任何可用数据”时自动切换三种状态，
在网络较差或首帧加载较慢时，用户不再看到莫名的空白或闪烁。

### 1.2 有数据时的状态卡片/用量卡片

当已经存在任意订阅/用户数据时：

- 统一在 `build` 中计算 `SubscriptionStatusResult`：
  - 仍然基于原有的 `subscriptionStatusService.checkSubscriptionStatus(...)`。
- 根据状态类型决定：
  - 过期 / 已用完 / 无订阅 → `_buildStatusCard(...)`
  - 其它有效状态 → `_buildUsageCard(...)`

同时，新增参数 `inlineErrorMessage`，用于在**已有数据但最近一次刷新失败**的场景下，
在卡片底部附加一条内联错误提示（见第 2 节）。


---

## 2. 更全面的错误处理与重试

**涉及文件：**
- `lib/xboard/features/subscription/widgets/subscription_usage_card.dart`
- `lib/xboard/features/auth/providers/xboard_user_provider.dart`

### 2.1 基于 xboardUserProvider.errorMessage 的错误展示

`UserAuthState` 本身带有：

- `bool isLoading`
- `String? errorMessage`

并且在以下场景会被赋值：

- `refreshSubscriptionInfo()` / `refreshSubscriptionInfoAfterPayment()` 抓取异常时
- 其它认证相关操作（登录失败等）

本次在订阅用量卡片中做了以下约定：

- 仅在 `errorMessage != null && errorMessage != 'TOKEN_EXPIRED'` 时，视为**普通加载错误**；
  - `TOKEN_EXPIRED` 仍然由首页的弹窗和路由重定向单独处理，不在卡片中重复提示。

### 2.2 无数据时的完整错误卡片 `_buildErrorCard`

当没有任何订阅数据且最近一次加载失败时：

- 展示一张独立错误卡片：
  - 左侧红色 `error_outline` 图标
  - 标题使用 `xboardLoadingFailed`
  - 副标题展示 `errorMessage` 详情
  - 底部为一个“重试”按钮（`xboardRetry`），调用：
    ```dart
    ref.read(xboardUserProvider.notifier).refreshSubscriptionInfo();
    ```

### 2.3 有数据时的内联错误横幅 `_buildInlineErrorBanner`

当已经有有效的订阅/用量数据，但最近一次刷新失败时：

- 不再遮挡原有进度条和统计信息；
- 在状态卡片和用量卡片底部附加一个浅色错误横幅：
  - 标题：`xboardLoadingFailed`
  - 文本：最近一次的错误信息
  - 右侧提供“重试”（`xboardRetry`）按钮，同样调用
    `xboardUserProvider.notifier.refreshSubscriptionInfo()`。

这样用户既可以继续看到**上一次成功刷新后的数据**，又能明确知道最新刷新失败，
并且可以在本地立即触发重试。

### 2.4 刷新按钮 Loading 体验统一

状态卡片与用量卡片右上角的“刷新”按钮不再内嵌 `Consumer`，而是直接使用
父组件传入的 `userState` / `ref`：

- `userState.isLoading == true` 时：
  - 按钮禁用，显示小号 `CircularProgressIndicator`。
- 否则：
  - 显示刷新图标，点击触发 `refreshSubscriptionInfo()`。
- 提示文案使用本地化：`AppLocalizations.of(context).xboardRefresh`。


---

## 3. 订阅数据的 WebSocket 主动刷新

**涉及文件：**
- `lib/xboard/features/remote_task/remote_task_manager.dart`
- `lib/application.dart`

项目本身已经存在基于 WebSocket 的“远程任务/设备上报”通道（`RemoteTaskManager`），
本次在此之上增加了一个轻量级的**订阅刷新推送**能力：

### 3.1 RemoteTaskManager 新增订阅刷新回调

在 `RemoteTaskManager` 内新增：

```dart
static Future<void> Function()? onSubscriptionRefreshRequested;
```

并在 WebSocket 消息处理函数 `_handleIncomingMessage` 中扩展系统事件分支：

```dart
if (data.containsKey('event')) {
  final String event = data['event'];
  switch (event) {
    case 'pong':
      ...
    case 'identify_ack':
      ...
    case 'subscription_refresh':
      _logger.info('收到服务端订阅刷新事件，准备刷新本地订阅信息');
      final callback = RemoteTaskManager.onSubscriptionRefreshRequested;
      if (callback != null) {
        await callback();
      } else {
        _logger.warning('订阅刷新回调未注册，忽略本次订阅刷新推送');
      }
      return;
    ...
  }
}
```

### 3.2 Application 注册回调，触发 Riverpod 刷新

在 `ApplicationState.initState` 中注册该回调：

```dart
RemoteTaskManager.onSubscriptionRefreshRequested = () async {
  try {
    final notifier = ref.read(xboardUserProvider.notifier);
    await notifier.refreshSubscriptionInfo();
  } catch (e) {
    debugPrint('[Application] 处理订阅刷新推送时出错: $e');
  }
};
```

并在 `dispose` 中清理：

```dart
RemoteTaskManager.onSubscriptionRefreshRequested = null;
```

### 3.3 服务端集成建议

服务端只需要在订阅状态发生关键变更时，通过 RemoteTask WebSocket 向客户端推送：

```json
{
  "event": "subscription_refresh"
}
```

客户端即会通过上面的链路自动调用 `refreshSubscriptionInfo()`，
从面板 API 主动拉取最新的用户与订阅信息，并驱动 UI 层（订阅用量卡片等）刷新。

优势：

- 订阅流量/到期状态变化可以实时反映到客户端；
- 不再依赖频繁轮询，减少服务器与客户端资源消耗；
- 逻辑上与现有 RemoteTask/WebSocket 管道完全复用，无需新增连接。


---

## 4. 启动全局 Splash 与首次数据同步优化

**涉及文件：**
- `lib/xboard/features/auth/providers/xboard_user_provider.dart`
- `lib/xboard/router/routes.dart`
- `lib/xboard/features/auth/pages/loading_page.dart`

### 4.1 快速认证 quickAuth：网络失败时同步恢复本地缓存

原逻辑中，`quickAuth()` 在存在 token 但网络拉取用户/订阅信息失败时：

- 仅异步调用 `_asyncRestoreCacheData()`（使用 `Future.microtask`）；
- 随后立即将 `isInitialized` 设为 `true` 并进入主界面；
- 导致首页初次展示时可能出现“没有任何订阅数据 → 若干秒后突然弹出本地缓存数据”的突变体验。

本次改动：

1. 抽取缓存恢复核心逻辑为 `Future<void> _restoreCacheDataInternal()`。
2. `_asyncRestoreCacheData()` 仅作为异步封装：
   ```dart
   void _asyncRestoreCacheData() {
     Future.microtask(() async {
       await _restoreCacheDataInternal();
     });
   }
   ```
3. 在 `quickAuth()` 中，当 `userInfo == null && subscription == null` 时：
   ```dart
   commonPrint.log('[启动刷新] 网络失败，尝试同步从本地缓存恢复核心数据');
   await _restoreCacheDataInternal();
   // 使用恢复后的 state 继续后续流程
   userInfo = state.userInfo;
   subscription = state.subscriptionInfo;
   ```

这样在启动阶段：

- 若网络可用：仍然优先使用在线接口刷新数据；
- 若网络不可用但本地有缓存：会在 **Loading 页内同步恢复**，
  跳转到首页时即可看到最新的本地订阅/用户数据，而不是空白占位再闪现；
- 若网络和本地缓存都不可用：依然会尽快结束 Loading 并进入登录/首页，不做无限阻塞。

### 4.2 全局 Loading 路由升级为品牌化 Splash

**原逻辑：**

- 路由 `/loading` 仅渲染一个简单的 `CircularProgressIndicator`。
- 当 `xboardUserProvider.state.isInitialized == false` 时，
  `go_router` 会重定向到 `/loading`。

**新逻辑：**

1. 新增页面 `XBoardLoadingPage`：
   - 文件：`lib/xboard/features/auth/pages/loading_page.dart`
   - 内容：
     - 渐变背景
     - 圆形图标（VPN Key）
     - 标题 `XBoard`
     - 文案使用 `xboardProcessing`（处理中...）
     - 圆形进度条
2. 在路由定义中改为：

   ```dart
   GoRoute(
     path: '/loading',
     name: 'loading',
     pageBuilder: (context, state) => const MaterialPage(
       child: XBoardLoadingPage(),
     ),
   ),
   ```

结合前文 quickAuth 的同步缓存策略，现在应用启动流程为：

1. 应用启动，`isInitialized == false` → 自动重定向到 `/loading`；
2. `quickAuth()` 完成 token 检查 + 网络刷新 + 必要的本地缓存恢复；
3. 核心数据就绪后将 `isInitialized` 置为 `true`，`go_router` 自动从 `/loading`
   跳转到首页或登录页；

用户在第一次进入首页时看到的就是**尽可能新的真实数据**，
避免了“打开首页→用量卡片突变一次”的违和感，同时保持启动时间在可接受范围。

---

## 5. 对现有逻辑的兼容性说明

- 所有改动均在现有 Provider / Router / WebSocket 管道之上进行增强，
  不改变既有 API 或路由路径；
- `subscription_refresh` WebSocket 事件是可选的：
  - 未接入该事件的服务端不会受到影响；
  - 客户端在未注册回调时会记录日志并忽略该事件；
- Loading/Splash 的行为仍由 `userState.isInitialized` 控制，
  老的登录/认证逻辑无需调整即可兼容。

如果后续还需要将同样的加载/错误展示模式扩展到其它异步数据组件
（例如节点列表、测速结果等），可以复用本次在 `SubscriptionUsageCard` 中引入的
`AsyncValue + 内联错误横幅 + 统一重试入口` 方案。
