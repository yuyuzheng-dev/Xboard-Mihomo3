import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';

final userInfoProvider = StateProvider<UserInfoData?>((ref) => null);
final subscriptionInfoProvider = StateProvider<SubscriptionData?>((ref) => null);
final userUIStateProvider = StateProvider<UIState>((ref) => const UIState());

class XBoardUserAuthNotifier extends Notifier<UserAuthState> {
  late final XBoardStorageService _storageService;

  @override
  UserAuthState build() {
    _storageService = ref.read(storageServiceProvider);
    return const UserAuthState();
  }

  /// 稳定的 quickAuth 实现：一次性状态更新，避免竞态和频繁UI重建
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

      // 如果有 token，并发读取本地缓存和短超时的网络请求
      commonPrint.log('发现 token，开始并发读取缓存与网络补充');

      // 启动并发任务（短超时）
      final networkSubscriptionFuture = XBoardSDK.getSubscription()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      final networkUserInfoFuture = XBoardSDK.getUserInfo()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      String? email;
      UserInfoData? finalUserInfo;
      SubscriptionData? finalSubscription;

      // 读取本地存储
      try {
        final emailResult = await _storageService.getUserEmail().timeout(const Duration(seconds: 3));
        email = emailResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 email 失败: $e');
      }

      try {
        final userInfoResult = await _storageService.getUserInfo().timeout(const Duration(seconds: 3));
        finalUserInfo = userInfoResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 userInfo 失败: $e');
      }

      try {
        final subscriptionResult = await _storageService.getSubscriptionInfo().timeout(const Duration(seconds: 3));
        finalSubscription = subscriptionResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 subscription 失败: $e');
      }

      // 如果本地缺数据，尝试短时网络补充
      if (finalUserInfo == null) {
        try {
          final netUser = await networkUserInfoFuture;
          if (netUser != null) {
            finalUserInfo = netUser;
            commonPrint.log('从网络补充用户信息');
          }
        } catch (e) {
          commonPrint.log('短时网络获取用户信息失败: $e');
        }
      }

      if (finalSubscription == null) {
        try {
          final netSub = await networkSubscriptionFuture;
          if (netSub != null) {
            finalSubscription = netSub;
            commonPrint.log('从网络补充订阅信息');
          }
        } catch (e) {
          commonPrint.log('短时网络获取订阅失败: $e');
        }
      }

      // ===== 核心改进：一次性原子更新状态 + provider =====
      // 先批量更新 provider（不触发额外重建）
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
        email: email,
        userInfo: finalUserInfo,
        subscriptionInfo: finalSubscription,
      );

      commonPrint.log('快速认证成功：已有token，进入主界面');

      // 后台启动完整验证（不阻塞，不修改主状态）
      _backgroundTokenValidationAndRefresh();

      // 自动导入订阅配置
      if (finalSubscription?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('启动时自动导入订阅: ${finalSubscription!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(finalSubscription.subscribeUrl!);
      }

      return true;
    } catch (e) {
      commonPrint.log('快速认证失败: $e');
      state = state.copyWith(isInitialized: true);
      return false;
    }
  }

  /// 后台验证token并刷新数据（纯后台任务，不修改主认证状态）
  void _backgroundTokenValidationAndRefresh() {
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        commonPrint.log('后台验证token有效性...');
        final isValid = await XBoardSDK.isLoggedIn();
        
        if (!isValid) {
          commonPrint.log('Token验证失败，标记过期');
          state = state.copyWith(errorMessage: 'TOKEN_EXPIRED');
        } else {
          commonPrint.log('Token验证成功，后台更新用户数据');
          // 更新用户和订阅数据，但不修改认证状态
          await _backgroundUpdateUserData();
        }
      } catch (e) {
        commonPrint.log('后台token验证异常: $e');
      }
    });
  }

  /// 后台更新用户数据：批量化更新，避免频繁重建
  Future<void> _backgroundUpdateUserData() async {
    try {
      commonPrint.log('后台获取最新用户数据...');
      
      UserInfoData? updatedUserInfo;
      SubscriptionData? updatedSubscription;

      // 并发获取
      try {
        updatedUserInfo = await XBoardSDK.getUserInfo();
      } catch (e) {
        commonPrint.log('后台获取用户信息失败: $e');
      }

      try {
        updatedSubscription = await XBoardSDK.getSubscription();
      } catch (e) {
        commonPrint.log('后台获取订阅信息失败: $e');
      }

      // 批量保存到存储
      if (updatedUserInfo != null) {
        try {
          await _storageService.saveUserInfo(updatedUserInfo);
        } catch (e) {
          commonPrint.log('保存用户信息失败: $e');
        }
      }

      if (updatedSubscription != null) {
        try {
          await _storageService.saveSubscriptionInfo(updatedSubscription);
        } catch (e) {
          commonPrint.log('保存订阅信息失败: $e');
        }
      }

      // ===== 批量更新：一次性修改state和provider =====
      if (updatedUserInfo != null) {
        ref.read(userInfoProvider.notifier).state = updatedUserInfo;
      }
      if (updatedSubscription != null) {
        ref.read(subscriptionInfoProvider.notifier).state = updatedSubscription;
      }

      // 只在有真实数据变化时更新认证状态（单次更新）
      if (updatedUserInfo != null || updatedSubscription != null) {
        state = state.copyWith(
          userInfo: updatedUserInfo ?? state.userInfo,
          subscriptionInfo: updatedSubscription ?? state.subscriptionInfo,
        );
        commonPrint.log('后台数据更新完成');
      }

      // 如果订阅链接有效，触发导入（但不阻塞）
      final curSubscription = updatedSubscription ?? ref.read(subscriptionInfoProvider);
      if (curSubscription?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('后台导入订阅配置: ${curSubscription!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(
          curSubscription.subscribeUrl!,
          forceRefresh: true,
        );
      }
    } catch (e) {
      commonPrint.log('后台更新用户数据失败: $e');
    }
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
        }
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
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

  /// 支付成功后刷新订阅信息
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
      }

      try {
        subscriptionData = await XBoardSDK.getSubscription();
      } catch (e) {
        commonPrint.log('获取订阅信息失败: $e');
      }

      // 批量保存
      if (userInfo != null) {
        await _storageService.saveUserInfo(userInfo);
      }
      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
      }

      // ===== 一次性批量更新 =====
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
      if (subscriptionData?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[支付成功] 开始重新导入订阅配置: ${subscriptionData!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(
          subscriptionData.subscribeUrl!,
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

  /// 手动刷新订阅信息
  Future<void> refreshSubscriptionInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('手动刷新订阅信息...');
      
      UserInfoData? userInfo;
      SubscriptionData? subscriptionData;

      try {
        userInfo = await XBoardSDK.getUserInfo();
      } catch (e) {
        commonPrint.log('获取用户信息失败: $e');
      }

      try {
        subscriptionData = await XBoardSDK.getSubscription();
      } catch (e) {
        commonPrint.log('获取订阅信息失败: $e');
      }

      if (userInfo != null) {
        await _storageService.saveUserInfo(userInfo);
      }
      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
      }

      // ===== 一次性批量更新 =====
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

      if (subscriptionData?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[手动刷新] 开始导入订阅配置: ${subscriptionData!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(
          subscriptionData.subscribeUrl!,
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

  /// 刷新用户信息
  Future<void> refreshUserInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    try {
      commonPrint.log('刷新用户详细信息...');
      final userInfoData = await XBoardSDK.getUserInfo();
      if (userInfoData != null) {
        await _storageService.saveUserInfo(userInfoData);
        ref.read(userInfoProvider.notifier).state = userInfoData;
        state = state.copyWith(userInfo: userInfoData);
        commonPrint.log('用户详细信息已刷新');
      }
    } catch (e) {
      commonPrint.log('刷新用户详细信息出错: $e');
    }
  }

  Future<void> logout() async {
    commonPrint.log('用户登出');
    await XBoardSDK.logout();
    await _storageService.clearAuthData();
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
