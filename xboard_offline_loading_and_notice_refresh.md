# XBoard 离线启动加载页与公告刷新优化说明

本次改动围绕两个体验问题进行了优化：

1. **应用在网络异常时启动白屏、不知道发生了什么**
2. **订阅首页左上角公告按钮无法主动刷新最新公告**

---

## 1. 启动阶段：离线 / 线路异常时的加载反馈

**涉及文件：**

- `lib/xboard/features/auth/pages/loading_page.dart`
- `lib/xboard/features/domain_status/domain_status.dart`（已有模块）

### 1.1 XBoardLoadingPage 集成域名 / 网络状态

原先的 `XBoardLoadingPage` 只展示品牌 Logo + 文案 + loading 圈，在以下场景下用户仍然会感觉是“白屏卡住”：

- 无网络 / DNS 失败 / 线路全部超时
- 面板域名全部不可用

本次改动中，`XBoardLoadingPage` 从简单的静态 loading 页，升级为**带线路检测与错误提示的启动面板**：

- 页面改为 `ConsumerStatefulWidget`，可以使用 Riverpod 读取状态：
  - 引入依赖：
    - `flutter_riverpod`
    - `xboard/features/domain_status/domain_status.dart`
- 在 `initState` 中，通过 `domainStatusProvider.notifier.checkDomain()` 触发一次域名状态检查（仅在冷启动且从未检查过时触发）。
- `build` 中监听 `domainStatusProvider`，根据状态动态展示不同文案：
  - 首次检测中：`正在检测线路与网络状态，请稍候...`
  - 重新检测中：`正在重新检查线路状态...`
  - 检测成功：`线路已就绪，正在同步账户信息...`
  - 检测失败或有错误：`当前无法连接到加速面板，请检查网络或稍后重试。`
  - 其它情况保留原有文案：`l10n.xboardProcessing`

### 1.2 在 Loading 页内显示具体错误信息

在主视觉下方新增了两层反馈：

1. **域名状态指示器**
   
   ```dart
   DomainStatusIndicator(
     showText: true,
     showLatency: true,
     padding: const EdgeInsets.symmetric(vertical: 4),
   )
   ```

   - 直接复用 `DomainStatusIndicator`：
     - 显示“检测中 / 可用 / 不可用”文字
     - 在成功时显示线路延迟

2. **详细错误提示块**

   当 `domainState.errorMessage != null` 时，在指示器下方展示一块浅色错误卡片：

   - 左侧为 `error_outline` 图标
   - 右侧为最近一次域名/线路检查返回的错误信息（如 DNS 失败、全部线路超时等）
   - 避免用户在网络异常时长时间只看到一块白色背景+loading 圈

### 1.3 一键重新检测线路

在页面右下角增加“重新检查线路”按钮：

```dart
Align(
  alignment: Alignment.centerRight,
  child: TextButton.icon(
    onPressed: isChecking ? null : () {
      ref.read(domainStatusProvider.notifier).refresh();
    },
    icon: isChecking
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh_rounded, size: 18),
    label: Text(isChecking ? '正在检测...' : '重新检查线路'),
  ),
)
```

- 检测进行中时按钮禁用并显示小号圆形进度条
- 检测结束后可再次点击重新发起线路检查
- 结合上方的错误卡片，可快速确认当前是“无网 / 线路全挂 / 其它异常”，而不再是模糊的“白屏卡住”体验

---

## 2. 订阅首页公告按钮：支持点击强制刷新 + 空态提示

**涉及文件：**

- `lib/xboard/features/subscription/widgets/xboard_vpn_panel.dart`
- `lib/xboard/features/notice/providers/notice_provider.dart`（已有）

### 2.1 问题背景

订阅首页左上角的公告图标原有逻辑：

```dart
onTap: () {
  if (notices.isEmpty) {
    ref.read(noticeProvider.notifier).fetchNotices();
  } else {
    _showNoticesBottomSheet(context, notices);
  }
}
```

- 只有在“完全没有公告数据”时才会真正调用 `fetchNotices()`
- 如果后台已经更新了公告，但本地仍有旧数据，点击按钮只会打开旧公告，不会主动刷新

### 2.2 新的点击行为：每次点击强制拉取最新公告

现在的点击逻辑调整为：

```dart
onTap: () async {
  final notifier = ref.read(noticeProvider.notifier);

  // 每次点击时主动刷新公告，确保内容及时更新
  await notifier.fetchNotices();

  if (!mounted) return;

  final updatedState = ref.read(noticeProvider);
  final updatedNotices = updatedState.visibleNotices;

  if (updatedState.error != null && updatedNotices.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('公告加载失败，请稍后重试')),
    );
    return;
  }

  if (updatedNotices.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂无公告')),
    );
  } else {
    _showNoticesBottomSheet(context, updatedNotices);
  }
}
```

具体行为：

1. **每次点击都会调用 `fetchNotices()`**
   - `NoticeNotifier` 内部已通过 `state.isLoading` 做了并发保护
   - 可以保证只要服务端有新公告，用户点击图标时就会尽量拉取到最新内容

2. **拉取失败时的反馈**
   - 当本地没有任何可见公告，且本次刷新返回错误时：
     - 使用 `SnackBar` 提示：`公告加载失败，请稍后重试`
   - 如果本地仍有旧公告数据，则优先保证用户可以继续查看旧公告，不会因一次刷新失败而完全看不到内容

3. **没有公告时的空态提示**
   - 当刷新完成后 `visibleNotices` 为空：
     - 使用 `SnackBar` 提示：`暂无公告`
   - 避免用户点击图标后毫无反馈，以为“按钮失效”或“系统卡死”

### 2.3 其它行为保持不变

- 公告图标右上角的红点逻辑仍然基于 `visibleNotices`：
  - 有可见公告 → 显示红点
  - 无可见公告 → 不显示红点
- 公告内容仍然通过 `NoticeDetailDialog` 以底部弹出面板形式展示，交互体验与之前保持一致。

---

## 3. 效果总结

- **离线 / 线路异常时启动体验**：
  - 用户在启动阶段不再只看到“白屏 + 小圈圈”，而是可以立即看到：
    - 当前线路检测状态（检测中 / 可用 / 不可用）
    - 最近一次失败的错误信息
    - 主动“重新检测线路”的入口
- **公告刷新体验**：
  - 每次点击左上角公告按钮都会主动刷新公告数据，保证公告变更可以被及时获取
  - 当确实没有公告或拉取失败时给出明确提示（`暂无公告` / `公告加载失败，请稍后重试`），避免无反馈操作

以上改动均在现有 Provider 与路由体系之上实现，不改变原有业务接口与路由结构，可平滑兼容现有功能。
