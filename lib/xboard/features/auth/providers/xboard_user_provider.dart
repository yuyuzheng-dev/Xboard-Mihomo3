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

  /// 稳定的 quickAuth 实现：并发使用本地缓存 + 短超时网络拉取（优先本地，网络作为补充），
  /// 尽量避免 UI 在已登录但订阅尚未准备好时显示“暂无套餐”。
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
        commonPrint.log('快速认证：无本地token，显示登录页面. isInitialized: ${state.isInitialized}');
        state = state.copyWith(isInitialized: true);
        return false;
      }

      // 如果有 token，尽快并发去取本地缓存，同时开启短超时的网络请求作为备份
      commonPrint.log('发现 token，开始并发读取缓存与短时网络补充');

      // 启动短超时网络请求（备份/补充）
      final networkSubscriptionFuture = XBoardSDK.getSubscription()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      final networkUserInfoFuture = XBoardSDK.getUserInfo()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      String? email;
      UserInfoData? localUserInfo;
      SubscriptionData? localSubscription;

      // 读取本地存储（稍微放宽超时至 3 秒以减少 IO 偶发超时）
      try {
        final emailResult = await _storageService.getUserEmail().timeout(const Duration(seconds: 3));
        email = emailResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 email 失败: $e');
      }

      try {
        final userInfoResult = await _storageService.getUserInfo().timeout(const Duration(seconds: 3));
        localUserInfo = userInfoResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 userInfo 失败: $e');
      }

      try {
        final subscriptionResult = await _storageService.getSubscriptionInfo().timeout(const Duration(seconds: 3));
        localSubscription = subscriptionResult.dataOrNull;
      } catch (e) {
        commonPrint.log('读取本地 subscription 失败: $e');
      }

      // 如果本地没有订阅信息，尝试等待短时网络结果作为补充（最多等待 3s）
      SubscriptionData? finalSubscription = localSubscription;
      if (finalSubscription == null) {
        try {
          final netSub = await networkSubscriptionFuture;
          if (netSub != null) {
            finalSubscription = netSub;
            // 先保存到 storage 再更新 provider
            await _saveAndSetSubscription(finalSubscription);
            commonPrint.log('从网络补充到订阅信息并已保存');
          }
        } catch (e) {
          commonPrint.log('短时网络获取订阅失败: $e');
        }
      } else {
        // 如果本地已有订阅，后台静默尝试更新网络（不阻塞）
        networkSubscriptionFuture.then((netSub) async {
          if (netSub != null) {
            await _saveAndSetSubscription(netSub);
            commonPrint.log('后台发现更新的订阅并已保存');
          }
        }).catchError((e) {
          commonPrint.log('后台更新订阅失败: $e');
        });

        // 仍把本地订阅同步到 provider（确保 provider 先有数据）
        await _setSubscriptionIfNotNull(localSubscription);
      }

      // 同步用户信息：如果本地存在则立即使用，否则短时网络尝试获取
      UserInfoData? finalUserInfo = localUserInfo;
      if (finalUserInfo == null) {
        try {
          final netUser = await networkUserInfoFuture;
          if (netUser != null) {
            finalUserInfo = netUser;
            await _saveAndSetUserInfo(finalUserInfo);
            commonPrint.log('从网络补充到用户信息并已保存');
          }
        } catch (e) {
          commonPrint.log('短时网络获取用户信息失败: $e');
        }
      } else {
        // 本地已有则先同步 provider
        await _setUserInfoIfNotNull(localUserInfo);
        // 并在后台尝试网络更新
        networkUserInfoFuture.then((netUser) async {
          if (netUser != null) {
            await _saveAndSetUserInfo(netUser);
            commonPrint.log('后台发现更新的用户信息并已保存');
          }
        }).catchError((e) {
          commonPrint.log('后台更新用户信息失败: $e');
        });
      }

      // 最终构建状态：优先使用已经写入 provider/本地/网络的实际值，避免用 null 覆盖
      final providerUserInfo = ref.read(userInfoProvider);
      final providerSubscription = ref.read(subscriptionInfoProvider);

      state = state.copyWith(
        isAuthenticated: true,
        isInitialized: true,
        email: email ?? state.email,
        userInfo: providerUserInfo ?? finalUserInfo ?? state.userInfo,
        subscriptionInfo: providerSubscription ?? finalSubscription ?? state.subscriptionInfo,
      );

      commonPrint.log('快速认证成功：已有token，进入主界面. isInitialized: ${state.isInitialized}');

      // 后台彻底验证 token 并触发更完整的静默更新（不用等待）
      _backgroundTokenValidation();

      // 如果当前已有订阅链接，则尽快触发导入（避免 UI 显示无套餐）
      final curSub = ref.read(subscriptionInfoProvider);
      if (curSub?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('启动时自动导入订阅: ${curSub!.subscribeUrl}');
        ref.read(profileImportProvider.notifier).importSubscription(curSub.subscribeUrl!);
      }

      return true;
    } catch (e) {
      commonPrint.log('快速认证失败: $e');
      state = state.copyWith(isInitialized: true);
      return false;
    } finally {
      if (!state.isInitialized) {
        commonPrint.log('强制设置初始化状态为true. isInitialized: ${state.isInitialized}');
        state = state.copyWith(isInitialized: true);
      }
    }
  }

  Future<void> _saveAndSetSubscription(SubscriptionData sub) async {
    try {
      await _storageService.saveSubscriptionInfo(sub);
    } catch (e) {
      commonPrint.log('保存 subscription 到 storage 失败: $e');
    }
    try {
      ref.read(subscriptionInfoProvider.notifier).state = sub;
    } catch (e) {
      commonPrint.log('设置 subscription provider 失败: $e');
    }
  }

  Future<void> _setSubscriptionIfNotNull(SubscriptionData? sub) async {
    if (sub == null) return;
    try {
      ref.read(subscriptionInfoProvider.notifier).state = sub;
    } catch (e) {
      commonPrint.log('设置 subscription provider 失败: $e');
    }
  }

  Future<void> _saveAndSetUserInfo(UserInfoData user) async {
    try {
      await _storageService.saveUserInfo(user);
    } catch (e) {
      commonPrint.log('保存 userInfo 到 storage 失败: $e');
    }
    try {
      ref.read(userInfoProvider.notifier).state = user;
    } catch (e) {
      commonPrint.log('设置 userInfo provider 失败: $e');
    }
  }

  Future<void> _setUserInfoIfNotNull(UserInfoData? user) async {
    if (user == null) return;
    try {
      ref.read(userInfoProvider.notifier).state = user;
    } catch (e) {
      commonPrint.log('设置 userInfo provider 失败: $e');
    }
  }

  void _backgroundTokenValidation() {
    // 保持短延迟，避免在 very-startup 阶段立刻并发过多请求
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        commonPrint.log('后台验证token有效性...');
        final isValid = await XBoardSDK.isLoggedIn();
        if (!isValid) {
          commonPrint.log('Token验证失败，显示登录过期提示');
          _showTokenExpiredDialog();
        } else {
          commonPrint.log('Token验证成功，静默更新用户数据');
          // 更彻底的静默更新（网络优先），但不阻塞 UI
          _silentUpdateUserData();
        }
      } catch (e) {
        commonPrint.log('后台token验证异常: $e');
      }
    });
  }

  Future<void> _silentUpdateUserData() async {
    try {
      // 使用域名服务获取订阅信息与用户信息
      final subscriptionData = await XBoardSDK.getSubscription();

      UserInfoData? userInfoData;
      try {
        userInfoData = await XBoardSDK.getUserInfo();
        if (userInfoData != null) {
          await _storageService.saveUserInfo(userInfoData);
          ref.read(userInfoProvider.notifier).state = userInfoData;
        }
      } catch (e) {
        commonPrint.log('静默更新用户信息失败: $e');
      }

      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;

        if (subscriptionData.subscribeUrl?.isNotEmpty == true) {
          ref.read(profileImportProvider.notifier).importSubscription(subscriptionData.subscribeUrl!);
        }
      }

      // 同步到UserAuthState，避免界面出现“无套餐”闪烁
      state = state.copyWith(
        userInfo: userInfoData ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
      );

      commonPrint.log('静默更新用户数据完成');
    } catch (e) {
      commonPrint.log('静默更新用户数据失败: $e');
    }
  }

  void _showTokenExpiredDialog() {
    state = state.copyWith(
      errorMessage: 'TOKEN_EXPIRED', // 特殊标记，UI层检测到后显示对话框
    );
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

        // 立即获取用户信息和订阅信息（容错并行）
        try {
          commonPrint.log('开始获取用户信息...');
          final userInfo = await XBoardSDK.getUserInfo();
          commonPrint.log('用户信息API调用完成: ${userInfo != null}');
          if (userInfo != null) {
            ref.read(userInfoProvider.notifier).state = userInfo;
            await _storageService.saveUserInfo(userInfo);
            commonPrint.log('用户信息已保存: ${userInfo.email}');
          } else {
            commonPrint.log('警告: getUserInfo返回null');
          }

          commonPrint.log('开始获取订阅信息...');
          final subscriptionInfo = await XBoardSDK.getSubscription();
          commonPrint.log('订阅信息API调用完成: ${subscriptionInfo != null}');
          if (subscriptionInfo != null) {
            ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
            await _storageService.saveSubscriptionInfo(subscriptionInfo);
            commonPrint.log('订阅信息已保存，subscribeUrl: ${subscriptionInfo.subscribeUrl}');

            if (subscriptionInfo.token != null) {
              commonPrint.log('保存订阅token用于订阅链接: ${subscriptionInfo.token?.substring(0, 10)}...');
            }
          } else {
            commonPrint.log('警告: getSubscription返回null');
          }
        } catch (e, stackTrace) {
          commonPrint.log('获取用户/订阅信息失败，但继续登录: $e');
          commonPrint.log('错误堆栈: $stackTrace');
        }

        commonPrint.log('准备更新状态...');
        final newState = state.copyWith(
          isAuthenticated: true,
          isInitialized: true,
          email: email,
          isLoading: false,
          userInfo: ref.read(userInfoProvider),
          subscriptionInfo: ref.read(subscriptionInfoProvider),
        );
        state = newState;
        commonPrint.log('===== 认证状态已更新! =====');
        commonPrint.log('isAuthenticated: ${state.isAuthenticated}');
        commonPrint.log('isInitialized: ${state.isInitialized}');
        commonPrint.log('email: ${state.email}');
        commonPrint.log('===========================');

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
      // 域名服务暂时不支持发送验证码功能
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

  Future<void> refreshSubscriptionInfoAfterPayment() async {
    if (!state.isAuthenticated) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('刷新订阅信息...');
      final subscriptionData = await XBoardSDK.getSubscription();
      UserInfoData? userInfo;
      try {
        userInfo = await XBoardSDK.getUserInfo();
        if (userInfo != null) {
          await _storageService.saveUserInfo(userInfo);
          ref.read(userInfoProvider.notifier).state = userInfo;
        }
      } catch (e) {
        commonPrint.log('获取用户详细信息失败: $e');
      }

      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      }

      state = state.copyWith(
        userInfo: userInfo ?? state.userInfo,
        subscriptionInfo: subscriptionData ?? state.subscriptionInfo,
        isLoading: false,
      );
      commonPrint.log('订阅信息已刷新');

      if (subscriptionData?.subscribeUrl?.isNotEmpty == true) {
        commonPrint.log('[支付成功] 开始重新导入订阅配置: ${subscriptionData!.subscribeUrl}');
        commonPrint.log('[支付成功] 使用强制刷新模式，跳过重复检测');
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

  Future<void> refreshSubscriptionInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      commonPrint.log('刷新订阅信息...');
      final subscriptionData = await XBoardSDK.getSubscription();
      UserInfoData? userInfo;
      try {
        userInfo = await XBoardSDK.getUserInfo();
        if (userInfo != null) {
          await _storageService.saveUserInfo(userInfo);
          ref.read(userInfoProvider.notifier).state = userInfo;
        }
      } catch (e) {
        commonPrint.log('获取用户详细信息失败: $e');
      }

      if (subscriptionData != null) {
        await _storageService.saveSubscriptionInfo(subscriptionData);
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
        commonPrint.log('[手动刷新] 使用强制刷新模式，跳过重复检测');
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
    state = const UserAuthState(
      isInitialized: true, // 登出后保持初始化状态，只重置认证信息
    );
  }

  String? get currentAuthToken => null; // Token管理已委托给域名服务
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
