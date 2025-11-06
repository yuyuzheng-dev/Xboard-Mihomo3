import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';

final userInfoProvider = StateProvider<UserInfoData?>((ref) => null);
final subscriptionInfoProvider = StateProvider<SubscriptionData?>((ref) => null);
final userUIStateProvider = StateProvider<UIState>((ref) => const UIState());

// 缓存时间戳提供者（用于判断缓存是否过期）
final subscriptionCacheTimestampProvider = StateProvider<int>((ref) => 0);
final userInfoCacheTimestampProvider = StateProvider<int>((ref) => 0);

class XBoardUserAuthNotifier extends Notifier<UserAuthState> {
  late final XBoardStorageService _storageService;

  @override
  UserAuthState build() {
    _storageService = ref.read(storageServiceProvider);
    return const UserAuthState();
  }

  /// 稳定的 quickAuth 实现：优先使用本地缓存，确保不显示空状态
  Future<bool> quickAuth() async {
    try {
      commonPrint.log('快速认证检查：检查域名服务登录状态...');
      final hasToken = await XBoardSDK.isLoggedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          commonPrint.log('快速认证超时，假设无token');
          return false;
        },
      );

      if (!hasToken) {
        commonPrint.log('快速认证：无本地token，显示登录页面');
        state = state.copyWith(isInitialized: true);
        return false;
      }

      // 如果有 token，直接读取本地缓存（快速进入主界面）
      commonPrint.log('发现 token，直接从本地缓存恢复状态');

      String? email;
      UserInfoData? finalUserInfo;
      SubscriptionData? finalSubscription;

      // 读取本地存储 - 优先级策略：总是尝试加载，即使失败也不清空
      try {
        final emailResult = await _storageService.getUserEmail().timeout(const Duration(seconds: 3));
        email = emailResult.dataOrNull;
        if (email != null) {
          commonPrint.log('从缓存读取 email: $email');
        }
      } catch (e) {
        commonPrint.log('读取本地 email 失败，但继续: $e');
        // 保持上一次的 email（如果有）
        email = state.email;
      }

      try {
        final userInfoResult = await _storageService.getUserInfo().timeout(const Duration(seconds: 3));
        finalUserInfo = userInfoResult.dataOrNull;
        if (finalUserInfo != null) {
          commonPrint.log('从缓存读取用户信息: ${finalUserInfo.email}');
          ref.read(userInfoCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
        }
      } catch (e) {
        commonPrint.log('读取本地 userInfo 失败，但继续: $e');
        // 保持上一次的用户信息（如果有）
        finalUserInfo = state.userInfo;
      }

      try {
        final subscriptionResult = await _storageService.getSubscriptionInfo().timeout(const Duration(seconds: 3));
        finalSubscription = subscriptionResult.dataOrNull;
        if (finalSubscription != null) {
          commonPrint.log('从缓存读取订阅信息: ${finalSubscription.subscribeUrl}');
          ref.read(subscriptionCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
        }
      } catch (e) {
        commonPrint.log('读取本地 subscription 失败，但继续: $e');
        // 保持上一次的订阅信息（如果有）
        finalSubscription = state.subscriptionInfo;
      }

      // ===== 核心改进：确保数据一致性，避免null覆盖有效缓存 =====
      // 先批量更新 provider（使用有效的缓存数据）
      if (finalUserInfo != null) {
        ref.read(userInfoProvider.notifier).state = finalUserInfo;
      }
      if (finalSubscription != null) {
        ref.read(subscriptionInfoProvider.notifier).state = finalSubscription;
      }

      // 然后一次性更新认证状态（单次UI重建）
      state = state.copyWith(
        isAuthenticated: true,
        isInitialized: true,
        email: email ?? state.email,
        userInfo: finalUserInfo ?? state.userInfo,
        subscriptionInfo: finalSubscription ?? state.subscriptionInfo,
      );

      commonPrint.log('快速认证成功：已有token，使用缓存数据进入主界面');
      commonPrint.log('当前缓存 - email: ${state.email}, 有用户信息: ${state.userInfo != null}, 有订阅信息: ${state.subscriptionInfo != null}');

      // 后台仅做 token 有效性检查（不自动刷新，不触发UI更新）
      _backgroundTokenValidation();

      // 自动导入订阅配置
      if (state.subscriptionInfo?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('启动时自动导入订阅: ${state.subscriptionInfo!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(state.subscriptionInfo!.subscribeUrl!);
      }

      return true;
    } catch (e) {
      commonPrint.log('快速认证失败: $e');
      state = state.copyWith(isInitialized: true);
      return false;
    }
  }

  /// 后台仅验证token是否过期（轻量级检查，不自动刷新）
  void _backgroundTokenValidation() {
    Future.delayed(const Duration(milliseconds: 1500), () async {
      try {
        commonPrint.log('后台检查token有效性...');
        final isValid = await XBoardSDK.isLoggedIn();
        
        if (!isValid) {
          commonPrint.log('Token验证失败，标记过期');
          state = state.copyWith(errorMessage: 'TOKEN_EXPIRED');
        } else {
          commonPrint.log('Token验证成功，等待用户手动刷新');
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
        commonPrint.log('登录成功，authData token已保存到TokenManager，立即获取用户信息');
        await _storageService.saveUserEmail(email);

        // 并发获取用户和订阅信息
        UserInfoData? userInfo;
        SubscriptionData? subscriptionInfo;

        try {
          commonPrint.log('开始获取用户信息...');
          userInfo = await XBoardSDK.getUserInfo();
          commonPrint.log('用户信息API调用完成: ${userInfo != null}');
          if (userInfo != null) {
            await _storageService.saveUserInfo(userInfo);
            commonPrint.log('用户信息已保存: ${userInfo.email}');
          } else {
            commonPrint.log('警告: getUserInfo返回null');
          }
        } catch (e, stackTrace) {
          commonPrint.log('获取用户信息失败: $e');
          commonPrint.log('错误堆栈: $stackTrace');
        }

        try {
          commonPrint.log('开始获取订阅信息...');
          subscriptionInfo = await XBoardSDK.getSubscription();
          commonPrint.log('订阅信息API调用完成: ${subscriptionInfo != null}');
          if (subscriptionInfo != null) {
            await _storageService.saveSubscriptionInfo(subscriptionInfo);
            commonPrint.log('订阅信息已保存，subscribeUrl: ${subscriptionInfo.subscribeUrl}');
          } else {
            commonPrint.log('警告: getSubscription返回null');
          }
        } catch (e, stackTrace) {
          commonPrint.log('获取订阅信息失败: $e');
          commonPrint.log('错误堆栈: $stackTrace');
        }

        // ===== 批量更新：先更新provider，再更新认证状态（一次性） =====
        if (userInfo != null) {
          ref.read(userInfoProvider.notifier).state = userInfo;
          ref.read(userInfoCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
        }
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
          ref.read(subscriptionCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
        }

        commonPrint.log('准备更新认证状态...');
        state = state.copyWith(
          isAuthenticated: true,
          isInitialized: true,
          email: email,
          isLoading: false,
          userInfo: userInfo,
          subscriptionInfo: subscriptionInfo,
        );
        commonPrint.log('===== 认证状态已更新! =====');
        commonPrint.log('isAuthenticated: ${state.isAuthenticated}');
        commonPrint.log('isInitialized: ${state.isInitialized}');
        commonPrint.log('email: ${state.email}');
        commonPrint.log('===========================');

        // 登录成功后自动导入订阅
        if (subscriptionInfo?.subscribeUrl?.isNotEmpty == true) {
          commonPrint.log('登录成功，自动导入订阅: ${subscriptionInfo!.subscribeUrl}');
          ref.read(profileImportProvider.notifier).importSubscription(subscriptionInfo.subscribeUrl!);
        }

        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: '登录失败',
        );
        return false;
      }
    } catch (e) {
      commonPrint.log('登录出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
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
      final success = result != null;
      if (success) {
        commonPrint.log('注册成功');
        await _storageService.saveUserEmail(email);
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: '注册失败',
        );
        return false;
      }
    } catch (e) {
      commonPrint.log('注册出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> sendVerificationCode(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('发送验证码到: $email');
      throw UnimplementedError('发送验证码功能暂时不可用');
    } catch (e) {
      commonPrint.log('发送验证码出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> resetPassword(String email, String password, String emailCode) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('重置密码: $email');
      final result = await XBoardSDK.resetPassword(email: email, password: password, emailCode: emailCode);
      final success = result;
      if (success) {
        commonPrint.log('密码重置邮件发送成功');
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: '密码重置失败',
        );
        return false;
      }
    } catch (e) {
      commonPrint.log('重置密码出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// 支付成功后刷新订阅信息（强制刷新，更新缓存）
  Future<void> refreshSubscriptionInfoAfterPayment() async {
    if (!state.isAuthenticated) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('支付后刷新订阅信息...');
      
      UserInfoData? userInfo;
      SubscriptionData? subscriptionData;

      // 并发获取最新数据
      try {
        userInfo = await XBoardSDK.getUserInfo();
      } catch (e) {
        commonPrint.log('获取用户信息失败: $e');
        // 网络失败时保持缓存
        userInfo = state.userInfo;
      }

      try {
        subscriptionData = await XBoardSDK.getSubscription();
      } catch (e) {
        commonPrint.log('获取订阅信息失败: $e');
        // 网络失败时保持缓存
        subscriptionData = state.subscriptionInfo;
      }

      // 只有网络成功才更新缓存
      if (userInfo != null && userInfo != state.userInfo) {
        await _storageService.saveUserInfo(userInfo);
        ref.read(userInfoCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
      }
      if (subscriptionData != null && subscriptionData != state.subscriptionInfo) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
      }

      // ===== 一次性批量更新，使用缓存数据作为后备 =====
      if (userInfo != null) {
        ref.read(userInfoProvider.notifier).state = userInfo;
      }
      if (subscriptionData != null) {
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      }

      state = state.copyWith(
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
        isLoading: false,
      );
      commonPrint.log('订阅信息已刷新');

      // 自动导入订阅
      final finalSubscription = subscriptionData ?? state.subscriptionInfo;
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[支付成功] 开始重新导入订阅配置: ${finalSubscription!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(
          finalSubscription.subscribeUrl!,
          forceRefresh: true,
        );
      } else {
        commonPrint.log('[支付成功] 订阅链接为空，跳过重新导入');
      }
    } catch (e) {
      commonPrint.log('刷新订阅信息出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 用户手动刷新订阅信息（从卡片刷新按钮调用）
  Future<void> refreshSubscriptionInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('用户手动刷新订阅信息...');
      
      UserInfoData? userInfo;
      SubscriptionData? subscriptionData;

      try {
        userInfo = await XBoardSDK.getUserInfo();
      } catch (e) {
        commonPrint.log('获取用户信息失败: $e');
        // 网络失败时保持缓存
        userInfo = state.userInfo;
      }

      try {
        subscriptionData = await XBoardSDK.getSubscription();
      } catch (e) {
        commonPrint.log('获取订阅信息失败: $e');
        // 网络失败时保持缓存
        subscriptionData = state.subscriptionInfo;
      }

      // 只有网络成功才更新缓存
      if (userInfo != null && userInfo != state.userInfo) {
        await _storageService.saveUserInfo(userInfo);
        ref.read(userInfoCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
      }
      if (subscriptionData != null && subscriptionData != state.subscriptionInfo) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
      }

      // ===== 一次性批量更新，使用缓存数据作为后备 =====
      if (userInfo != null) {
        ref.read(userInfoProvider.notifier).state = userInfo;
      }
      if (subscriptionData != null) {
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      }

      state = state.copyWith(
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
        isLoading: false,
      );
      commonPrint.log('订阅信息已手动刷新');

      final finalSubscription = subscriptionData ?? state.subscriptionInfo;
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[手动刷新] 开始导入订阅配置: ${finalSubscription!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(
          finalSubscription.subscribeUrl!,
          forceRefresh: true,
        );
      } else {
        commonPrint.log('[手动刷新] 订阅链接为空，跳过导入');
      }
    } catch (e) {
      commonPrint.log('刷新订阅信息出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 用户手动刷新用户信息（从卡片刷新按钮调用）
  Future<void> refreshUserInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    try {
      commonPrint.log('用户手动刷新用户详细信息...');
      final userInfoData = await XBoardSDK.getUserInfo();
      if (userInfoData != null) {
        await _storageService.saveUserInfo(userInfoData);
        ref.read(userInfoProvider.notifier).state = userInfoData;
        ref.read(userInfoCacheTimestampProvider.notifier).state = DateTime.now().millisecondsSinceEpoch;
        state = state.copyWith(userInfo: userInfoData);
        commonPrint.log('用户详细信息已手动刷新');
      } else {
        // 网络失败时保持缓存
        commonPrint.log('获取用户信息失败，保持缓存');
      }
    } catch (e) {
      commonPrint.log('刷新用户详细信息出错，保持缓存: $e');
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
