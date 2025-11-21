# XBoard 离线白屏问题优化方案

## 问题描述

在项目启动时，如果设备无网络连接或网络不稳定，应用会显示白屏，用户无法了解发生了什么，也无法重试连接。

## 问题根源

1. **初始化流程缺乏容错机制**
   - 应用在启动时需要连接到远程服务器进行快速认证
   - 如果网络连接失败，初始化会被阻塞
   - UI 没有显示任何错误提示或进度信息

2. **状态管理不完善**
   - 用户认证状态只有 `isInitialized` 和 `isAuthenticated` 两个标记
   - 缺少初始化失败原因的标记
   - 无法区分"初始化中"和"初始化失败"

3. **路由重定向逻辑不足**
   - 路由器的重定向函数只处理了已认证/未认证状态
   - 未考虑初始化失败的情况
   - 初始化失败时没有对应的错误页面

## 解决方案

### 1. 增强用户认证状态

#### 文件修改：`lib/xboard/features/auth/models/auth_state.dart`

添加 `hasInitializationError` 字段来标记初始化是否因网络问题而失败：

```dart
class UserAuthState {
  final bool isAuthenticated;
  final bool isInitialized;
  final String? email;
  final bool isLoading;
  final String? errorMessage;
  final UserInfoData? userInfo;
  final SubscriptionData? subscriptionInfo;
  final bool hasInitializationError;  // 新增字段

  const UserAuthState({
    this.isAuthenticated = false,
    this.isInitialized = false,
    this.email,
    this.isLoading = false,
    this.errorMessage,
    this.userInfo,
    this.subscriptionInfo,
    this.hasInitializationError = false,  // 默认为 false
  });
  
  // copyWith 和其他方法已更新...
}
```

### 2. 改进快速认证逻辑

#### 文件修改：`lib/xboard/features/auth/providers/xboard_user_provider.dart`

增强 `quickAuth()` 方法的网络错误处理：

```dart
Future<bool> quickAuth() async {
  try {
    // 第一步：检查 token（带错误处理）
    bool hasTokenCheckFailed = false;
    bool hasToken = false;
    
    try {
      hasToken = await XBoardSDK.isLoggedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      hasTokenCheckFailed = true;
      // 检查是否有本地缓存，如果有则尝试离线模式
      final email = await _storageService.getUserEmail().catchError((_) => null);
      if (email?.dataOrNull != null) {
        hasToken = true;  // 使用缓存数据
      }
    }

    // 如果无 token，返回未认证状态
    if (!hasToken) {
      state = state.copyWith(
        isInitialized: true,
        hasInitializationError: hasTokenCheckFailed,
      );
      return false;
    }

    // 有 token：进入刷新流程
    state = state.copyWith(
      isAuthenticated: true,
      isInitialized: false,
      hasInitializationError: false,
    );

    // 第二步：获取用户和订阅信息（带超时和错误处理）
    UserInfoData? userInfo;
    SubscriptionData? subscription;
    bool networkFetchFailed = false;
    
    try {
      final userInfoFuture = XBoardSDK.getUserInfo()
          .timeout(const Duration(seconds: 6), onTimeout: () => null)
          .catchError((_) => null);
      final subscriptionFuture = XBoardSDK.getSubscription()
          .timeout(const Duration(seconds: 6), onTimeout: () => null)
          .catchError((_) => null);

      userInfo = await userInfoFuture;
      subscription = await subscriptionFuture;
    } catch (e) {
      networkFetchFailed = true;
    }

    // 第三步：尝试从本地缓存恢复数据
    if (userInfo == null && subscription == null) {
      await _restoreCacheDataInternal();
      userInfo = state.userInfo;
      subscription = state.subscriptionInfo;
    }

    // 第四步：标记初始化完成
    state = state.copyWith(
      isInitialized: true,
      userInfo: userInfo ?? state.userInfo,
      subscriptionInfo: subscription ?? state.subscriptionInfo,
      hasInitializationError: networkFetchFailed && 
                             userInfo == null && 
                             subscription == null && 
                             state.userInfo == null,
    );

    return true;
  } catch (e) {
    state = state.copyWith(
      isInitialized: true,
      hasInitializationError: true,
    );
    return false;
  }
}
```

### 3. 创建离线错误页面

#### 新文件：`lib/xboard/features/auth/pages/offline_error_page.dart`

```dart
class OfflineErrorPage extends StatefulWidget {
  final VoidCallback onRetry;

  const OfflineErrorPage({
    super.key,
    required this.onRetry,
  });

  @override
  State<OfflineErrorPage> createState() => _OfflineErrorPageState();
}

class _OfflineErrorPageState extends State<OfflineErrorPage> {
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    // 显示离线错误 UI
    // - WiFi OFF 图标
    // - 错误提示文本
    // - 重试按钮
    // - 故障排查建议
  }
}
```

#### 页面特性

- **清晰的错误提示**：大字号 WiFi OFF 图标和错误信息
- **故障排查建议**：提供常见问题和解决方案
- **重试功能**：按钮显示重试状态，防止多次点击
- **美观设计**：与应用设计风格一致的错误页面

### 4. 更新路由配置

#### 文件修改：`lib/xboard/router/routes.dart`

```dart
// 添加离线错误页面路由
GoRoute(
  path: '/offline-error',
  name: 'offline_error',
  pageBuilder: (context, state) => MaterialPage(
    child: OfflineErrorPage(
      onRetry: () {
        context.go('/');
      },
    ),
  ),
),
```

### 5. 改进路由重定向逻辑

#### 文件修改：`lib/application.dart`

```dart
GoRouter _buildRouter(UserAuthState userState) {
  return GoRouter(
    navigatorKey: globalState.navigatorKey,
    initialLocation: '/',
    routes: xboard_router.routes,
    redirect: (context, state) {
      final isAuthenticated = userState.isAuthenticated;
      final isInitialized = userState.isInitialized;
      final hasInitializationError = userState.hasInitializationError;
      final isLoginPage = state.uri.path == '/login';
      final isOfflineErrorPage = state.uri.path == '/offline-error';

      // 初始化中 → 显示加载页面
      if (!isInitialized) {
        return '/loading';
      }

      // 初始化失败（网络错误）→ 显示离线错误页面
      if (hasInitializationError && !isAuthenticated && !isOfflineErrorPage) {
        return '/offline-error';
      }

      // 未认证 → 显示登录页面
      if (!isAuthenticated && !isLoginPage && !isOfflineErrorPage) {
        return '/login';
      }

      // 已认证且在登录页 → 返回首页
      if (isAuthenticated && isLoginPage) {
        return '/';
      }

      return null;
    },
  );
}
```

## 用户体验流程

### 场景 1：有网络连接且有缓存

1. 应用启动 → 显示加载页面
2. 快速认证成功，获取最新数据
3. 进入首页，显示最新的用户和订阅信息

### 场景 2：无网络连接但有缓存

1. 应用启动 → 显示加载页面
2. 快速认证失败（网络超时）
3. 自动从本地缓存恢复数据
4. 进入首页，显示缓存的用户和订阅信息

### 场景 3：无网络连接且无缓存

1. 应用启动 → 显示加载页面
2. 快速认证失败（网络超时）
3. 本地无缓存，初始化失败
4. 显示离线错误页面，用户可以：
   - 点击"重试"按钮重新尝试连接
   - 查看故障排查建议

### 场景 4：用户重试成功

1. 用户在离线错误页面点击"重试"
2. 应用重新进行快速认证
3. 网络连接恢复，认证成功
4. 自动进入首页

## 改进的优势

| 问题 | 原来的表现 | 改进后的表现 |
|------|----------|----------|
| 无网络启动 | 白屏（无提示） | 显示离线错误页面 |
| 用户无所适从 | 不知道发生了什么 | 清晰的错误提示和建议 |
| 无法重试 | 无法恢复应用 | 提供重试按钮 |
| 有缓存时 | 仍然白屏 | 从缓存恢复，正常使用 |
| 初始化状态不明确 | 无法判断失败原因 | 清晰的状态标记和提示 |

## 测试场景

### 网络测试

1. **完全离线**
   - 步骤：断开网络，启动应用
   - 预期：显示离线错误页面

2. **有缓存+离线**
   - 步骤：登录并使用应用，断开网络，重启应用
   - 预期：显示加载页面后进入首页（使用缓存数据）

3. **无缓存+离线**
   - 步骤：第一次启动应用且无网络
   - 预期：显示离线错误页面

4. **重试成功**
   - 步骤：在离线错误页面，恢复网络，点击重试
   - 预期：成功连接并进入首页

5. **网络超时恢复**
   - 步骤：网络缓慢时启动，等待其恢复
   - 预期：自动进入首页（6 秒超时后使用缓存）

## 文件修改汇总

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `lib/xboard/features/auth/models/auth_state.dart` | 修改 | 添加 `hasInitializationError` 字段 |
| `lib/xboard/features/auth/providers/xboard_user_provider.dart` | 修改 | 增强 `quickAuth()` 方法 |
| `lib/xboard/features/auth/pages/offline_error_page.dart` | 新建 | 离线错误页面 UI |
| `lib/xboard/router/routes.dart` | 修改 | 添加离线错误页面路由 |
| `lib/application.dart` | 修改 | 改进路由重定向逻辑 |

## 性能影响

- **初始化时间**：无增加（仍然是 5-6 秒超时）
- **内存占用**：增加一个布尔值字段（忽略不计）
- **网络流量**：无增加（超时机制相同）

## 向后兼容性

✅ **完全向后兼容**
- 新字段 `hasInitializationError` 默认为 `false`
- 现有逻辑不改变，只是增加新的错误状态处理
- 已有的缓存机制保持不变
