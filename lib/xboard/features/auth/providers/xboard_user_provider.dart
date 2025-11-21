import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';

final userInfoProvider = StateProvider<UserInfoData?>((ref) => null);
final subscriptionInfoProvider = StateProvider<SubscriptionData?>((ref) => null);
final userUIStateProvider = StateProvider<UIState>((ref) => const UIState());

// 缓存时间戳提供者
final subscriptionCacheTimestampProvider = StateProvider<int>((ref) => 0);
final userInfoCacheTimestampProvider = StateProvider<int>((ref) => 0);

class XBoardUserAuthNotifier extends Notifier<UserAuthState> {
  late final XBoardStorageService _storageService;

  @override
  UserAuthState build() {
    _storageService = ref.read(storageServiceProvider);
    return const UserAuthState();
  }

  /// 启动快速认证：有token时先显示加载动画，刷新用户与套餐信息
  Future<bool> quickAuth() async {
    try {
      commonPrint.log('========== 快速认证开始 ==========');
      
      // 第一步：检查token（同步，关键决策点）
      commonPrint.log('第一步：检查token状态...');
      bool hasTokenCheckFailed = false;
      bool hasToken = false;
      
      try {
        hasToken = await XBoardSDK.isLoggedIn().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            commonPrint.log('检查token超时，假设无token');
            return false;
          },
        );
      } catch (e) {
        commonPrint.log('检查token异常: $e');
        hasTokenCheckFailed = true;
        // 如果检查失败且有缓存数据，尝试使用缓存
        final email = await _storageService.getUserEmail().catchError((_) => null);
        if (email?.dataOrNull != null) {
          commonPrint.log('检查token失败但发现缓存数据，尝试离线模式');
          hasToken = true;
        }
      }

      // 如果无token，直接返回未认证
      if (!hasToken) {
        commonPrint.log('✗ 无token，标记未认证');
        state = state.copyWith(
          isInitialized: true,
          hasInitializationError: hasTokenCheckFailed,
        );
        return false;
      }

      // 有token：标记为已认证，但保持未初始化以显示加载动画
      commonPrint.log('✓ 发现token，进入启动刷新流程并显示加载动画');
      state = state.copyWith(
        isAuthenticated: true,
        isInitialized: false,
        hasInitializationError: false,
      );

      // 并发从网络刷新用户信息与订阅信息（带超时保护）
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
        commonPrint.log('[启动刷新] 拉取用户/订阅信息异常: $e');
        networkFetchFailed = true;
      }

      // 网络成功则更新缓存与Provider
      if (userInfo != null) {
        await _storageService.saveUserInfo(userInfo);
        ref.read(userInfoProvider.notifier).state = userInfo;
        ref.read(userInfoCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }
      if (subscription != null) {
        await _storageService.saveSubscriptionInfo(subscription);
        ref.read(subscriptionInfoProvider.notifier).state = subscription;
        ref.read(subscriptionCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }

      // 自动导入订阅
      final finalSubscription = subscription ?? state.subscriptionInfo;
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        ref.read(profileImportProvider.notifier).importSubscription(
          finalSubscription!.subscribeUrl!,
          forceRefresh: true,
        );
      }

      // 若网络均失败，则优先尝试同步恢复本地缓存，避免首页出现空数据闪烁
      if (userInfo == null && subscription == null) {
        commonPrint.log('[启动刷新] 网络失败，尝试同步从本地缓存恢复核心数据');
        await _restoreCacheDataInternal();
        // 同步恢复后使用最新的缓存数据继续后续流程
        userInfo = state.userInfo;
        subscription = state.subscriptionInfo;
      }

      // 结束加载，进入主界面
      state = state.copyWith(
        isInitialized: true,
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscription ?? state.subscriptionInfo,
        hasInitializationError: networkFetchFailed && userInfo == null && subscription == null && state.userInfo == null,
      );

      // 后台验证token有效性
      _backgroundTokenValidation();

      commonPrint.log('========== 启动刷新完成，已进入主界面 ==========');
      return true;
      
    } catch (e) {
      commonPrint.log('快速认证异常: $e');
      state = state.copyWith(
        isInitialized: true,
        hasInitializationError: true,
      );
      return false;
    }
  }

  /// 异步恢复缓存，不影响认证状态（即使全部失败也不改变已认证状态）
  void _asyncRestoreCacheData() {
    // 在后台异步恢复，不阻塞主线程
    Future.microtask(() async {
      await _restoreCacheDataInternal();
    });
  }

  /// 实际的缓存恢复逻辑
  Future<void> _restoreCacheDataInternal() async {
    try {
      commonPrint.log('[缓存恢复] 开始读取本地数据...');
      
      String? email = state.email; // 保持上一个值
      UserInfoData? userInfo = state.userInfo;
      SubscriptionData? subscription = state.subscriptionInfo;

      // 并发读取所有缓存（不相互阻塞）
      try {
        final emailResult = await _storageService.getUserEmail()
            .timeout(const Duration(seconds: 2));
        final newEmail = emailResult.dataOrNull;
        if (newEmail != null) {
          email = newEmail;
          commonPrint.log('[缓存恢复] ✓ email读取成功');
        }
      } catch (e) {
        commonPrint.log('[缓存恢复] email读取失败（保持缓存）: $e');
      }

      try {
        final userInfoResult = await _storageService.getUserInfo()
            .timeout(const Duration(seconds: 2));
        final newUserInfo = userInfoResult.dataOrNull;
        if (newUserInfo != null) {
          userInfo = newUserInfo;
          ref.read(userInfoProvider.notifier).state = newUserInfo;
          ref.read(userInfoCacheTimestampProvider.notifier).state = 
              DateTime.now().millisecondsSinceEpoch;
          commonPrint.log('[缓存恢复] ✓ userInfo读取成功');
        }
      } catch (e) {
        commonPrint.log('[缓存恢复] userInfo读取失败（保持缓存）: $e');
      }

      try {
        final subscriptionResult = await _storageService.getSubscriptionInfo()
            .timeout(const Duration(seconds: 2));
        final newSubscription = subscriptionResult.dataOrNull;
        if (newSubscription != null) {
          subscription = newSubscription;
          ref.read(subscriptionInfoProvider.notifier).state = newSubscription;
          ref.read(subscriptionCacheTimestampProvider.notifier).state = 
              DateTime.now().millisecondsSinceEpoch;
          commonPrint.log('[缓存恢复] ✓ subscription读取成功');
        }
      } catch (e) {
        commonPrint.log('[缓存恢复] subscription读取失败（保持缓存）: $e');
      }

      // 只有当有新数据时才更新state
      if (email != state.email || 
          userInfo != state.userInfo || 
          subscription != state.subscriptionInfo) {
        state = state.copyWith(
          email: email,
          userInfo: userInfo,
          subscriptionInfo: subscription,
        );
        commonPrint.log('[缓存恢复] ✓ 状态已更新');
      }

      // 自动导入订阅
      if (subscription?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[缓存恢复] 自动导入订阅: ${subscription!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(subscription.subscribeUrl!);
      }

      commonPrint.log('[缓存恢复] 完成 - email: $email, 有userInfo: ${userInfo != null}, 有subscription: ${subscription != null}');
    } catch (e) {
      commonPrint.log('[缓存恢复] 严重异常（但已认证）: $e');
      // 即使严重异常也不改变认证状态
    }
  }

  /// 后台仅验证token是否过期
  void _backgroundTokenValidation() {
    Future.delayed(const Duration(milliseconds: 2000), () async {
      try {
        commonPrint.log('后台验证token有效性...');
        final isValid = await XBoardSDK.isLoggedIn();
        
        if (!isValid) {
          commonPrint.log('✗ Token已过期');
          state = state.copyWith(errorMessage: 'TOKEN_EXPIRED');
        } else {
          commonPrint.log('✓ Token有效');
        }
      } catch (e) {
        commonPrint.log('后台token验证异常: $e');
      }
    });
  }

  void clearTokenExpiredError() {
    if (state.errorMessage == 'TOKEN_EXPIRED') {
      state = state.copyWith(errorMessage: null);
    }
  }

  Future<void> handleTokenExpired() async {
    commonPrint.log('处理token过期，清除认证状态');
    await XBoardSDK.logout();
    ref.read(userInfoProvider.notifier).state = null;
    ref.read(subscriptionInfoProvider.notifier).state = null;
    ref.read(userInfoCacheTimestampProvider.notifier).state = 0;
    ref.read(subscriptionCacheTimestampProvider.notifier).state = 0;
    state = const UserAuthState(isInitialized: true);
  }

  Future<bool> autoAuth() async {
    return await quickAuth();
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('开始登录: $email');
      final success = await XBoardSDK.login(email: email, password: password);
      if (success) {
        commonPrint.log('✓ 登录成功，获取用户信息');
        await _storageService.saveUserEmail(email);

        UserInfoData? userInfo;
        SubscriptionData? subscriptionInfo;

        // 并发获取
        final userInfoFuture = XBoardSDK.getUserInfo().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ).catchError((_) => null);

        final subscriptionFuture = XBoardSDK.getSubscription().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ).catchError((_) => null);

        userInfo = await userInfoFuture;
        subscriptionInfo = await subscriptionFuture;

        if (userInfo != null) {
          await _storageService.saveUserInfo(userInfo);
          commonPrint.log('用户信息已保存');
        }
        if (subscriptionInfo != null) {
          await _storageService.saveSubscriptionInfo(subscriptionInfo);
          commonPrint.log('订阅信息已保存');
        }

        // 批量更新
        if (userInfo != null) {
          ref.read(userInfoProvider.notifier).state = userInfo;
          ref.read(userInfoCacheTimestampProvider.notifier).state = 
              DateTime.now().millisecondsSinceEpoch;
        }
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
          ref.read(subscriptionCacheTimestampProvider.notifier).state = 
              DateTime.now().millisecondsSinceEpoch;
        }

        state = state.copyWith(
          isAuthenticated: true,
          isInitialized: true,
          email: email,
          isLoading: false,
          userInfo: userInfo,
          subscriptionInfo: subscriptionInfo,
        );

        if (subscriptionInfo?.subscribeUrl?.isNotEmpty == true) {
          ref.read(profileImportProvider.notifier).importSubscription(subscriptionInfo!.subscribeUrl!);
        }

        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: '登录失败');
        return false;
      }
    } catch (e) {
      commonPrint.log('登录出错: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> register(String email, String password, String? inviteCode, String emailCode) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('开始注册: $email');
      final result = await XBoardSDK.register(
        email: email,
        password: password,
        inviteCode: inviteCode,
        emailCode: emailCode,
      );
      if (result != null) {
        await _storageService.saveUserEmail(email);
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: '注册失败');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> sendVerificationCode(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      throw UnimplementedError('发送验证码功能暂时不可用');
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> resetPassword(String email, String password, String emailCode) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final result = await XBoardSDK.resetPassword(
        email: email,
        password: password,
        emailCode: emailCode,
      );
      if (result) {
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: '密码重置失败');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// 支付后刷新（强制更新）
  Future<void> refreshSubscriptionInfoAfterPayment() async {
    if (!state.isAuthenticated) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      UserInfoData? userInfo;
      SubscriptionData? subscriptionData;

      final userInfoFuture = XBoardSDK.getUserInfo().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).catchError((_) => null);

      final subscriptionFuture = XBoardSDK.getSubscription().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).catchError((_) => null);

      userInfo = await userInfoFuture;
      subscriptionData = await subscriptionFuture;

      // 网络成功则更新缓存，否则保持缓存
      if (userInfo != null) {
        await _storageService.saveUserInfo(userInfo);
        ref.read(userInfoProvider.notifier).state = userInfo;
        ref.read(userInfoCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }
      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
        ref.read(subscriptionCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }

      state = state.copyWith(
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
        isLoading: false,
      );

      final finalSubscription = subscriptionData ?? state.subscriptionInfo;
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        ref.read(profileImportProvider.notifier).importSubscription(
          finalSubscription!.subscribeUrl!,
          forceRefresh: true,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// 用户手动刷新
  Future<void> refreshSubscriptionInfo() async {
    if (!state.isAuthenticated) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      UserInfoData? userInfo;
      SubscriptionData? subscriptionData;

      final userInfoFuture = XBoardSDK.getUserInfo().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).catchError((_) => null);

      final subscriptionFuture = XBoardSDK.getSubscription().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).catchError((_) => null);

      userInfo = await userInfoFuture;
      subscriptionData = await subscriptionFuture;

      if (userInfo != null) {
        await _storageService.saveUserInfo(userInfo);
        ref.read(userInfoProvider.notifier).state = userInfo;
        ref.read(userInfoCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }
      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
        ref.read(subscriptionCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
      }

      state = state.copyWith(
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
        isLoading: false,
      );

      final finalSubscription = subscriptionData ?? state.subscriptionInfo;
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        ref.read(profileImportProvider.notifier).importSubscription(
          finalSubscription!.subscribeUrl!,
          forceRefresh: true,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// 刷新用户信息
  Future<void> refreshUserInfo() async {
    if (!state.isAuthenticated) return;
    try {
      final userInfoData = await XBoardSDK.getUserInfo().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).catchError((_) => null);

      if (userInfoData != null) {
        await _storageService.saveUserInfo(userInfoData);
        ref.read(userInfoProvider.notifier).state = userInfoData;
        ref.read(userInfoCacheTimestampProvider.notifier).state = 
            DateTime.now().millisecondsSinceEpoch;
        state = state.copyWith(userInfo: userInfoData);
      }
    } catch (e) {
      commonPrint.log('刷新用户信息失败: $e');
    }
  }

  Future<void> logout() async {
    commonPrint.log('用户登出');
    await XBoardSDK.logout();
    await _storageService.clearAuthData();
    ref.read(userInfoProvider.notifier).state = null;
    ref.read(subscriptionInfoProvider.notifier).state = null;
    ref.read(userInfoCacheTimestampProvider.notifier).state = 0;
    ref.read(subscriptionCacheTimestampProvider.notifier).state = 0;
    state = const UserAuthState(isInitialized: true);
  }

  String? get currentAuthToken => null;
  bool get isAuthenticated => state.isAuthenticated;
  String? get currentEmail => state.email;
}

final xboardUserAuthProvider = NotifierProvider<XBoardUserAuthNotifier, UserAuthState>(
  XBoardUserAuthNotifier.new,
);
final xboardUserProvider = xboardUserAuthProvider;

extension UserInfoHelpers on WidgetRef {
  UserInfoData? get userInfo => read(userInfoProvider);
  SubscriptionData? get subscriptionInfo => read(subscriptionInfoProvider);
  UserAuthState get userAuthState => read(xboardUserAuthProvider);
  bool get isAuthenticated => read(xboardUserAuthProvider).isAuthenticated;
}
