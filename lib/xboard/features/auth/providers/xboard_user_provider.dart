// File: lib/xboard/user_auth/xboard_user_auth_notifier.dart
// 稳定版：包含 quickAuth 并发策略 + 静默更新
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

      commonPrint.log('发现 token，开始并发读取缓存与短时网络补充');

      final networkSubscriptionFuture = XBoardSDK.getSubscription()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      final networkUserInfoFuture = XBoardSDK.getUserInfo()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      String? email;
      UserInfoData? localUserInfo;
      SubscriptionData? localSubscription;

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

      SubscriptionData? finalSubscription = localSubscription;
      if (finalSubscription == null) {
        try {
          final netSub = await networkSubscriptionFuture;
          if (netSub != null) {
            finalSubscription = netSub;
            await _saveAndSetSubscription(finalSubscription);
            commonPrint.log('从网络补充到订阅信息并已保存');
          }
        } catch (e) {
          commonPrint.log('短时网络获取订阅失败: $e');
        }
      } else {
        networkSubscriptionFuture.then((netSub) async {
          if (netSub != null) {
            await _saveAndSetSubscription(netSub);
            commonPrint.log('后台发现更新的订阅并已保存');
          }
        }).catchError((e) {
          commonPrint.log('后台更新订阅失败: $e');
        });

        await _setSubscriptionIfNotNull(localSubscription);
      }

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
        await _setUserInfoIfNotNull(localUserInfo);
        networkUserInfoFuture.then((netUser) async {
          if (netUser != null) {
            await _saveAndSetUserInfo(netUser);
            commonPrint.log('后台发现更新的用户信息并已保存');
          }
        }).catchError((e) {
          commonPrint.log('后台更新用户信息失败: $e');
        });
      }

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

      _backgroundTokenValidation();

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
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        commonPrint.log('后台验证token有效性...');
        final isValid = await XBoardSDK.isLoggedIn();
        if (!isValid) {
          commonPrint.log('Token验证失败，显示登录过期提示');
          _showTokenExpiredDialog();
        } else {
          commonPrint.log('Token验证成功，静默更新用户数据');
          _silentUpdateUserData();
        }
      } catch (e) {
        commonPrint.log('后台token验证异常: $e');
      }
    });
  }

  Future<void> _silentUpdateUserData() async {
    try {
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
      errorMessage: 'TOKEN_EXPIRED',
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

  // ... 其余方法（login/register/...）保持原样，略去以保持文档简洁

  Future<void> logout() async {
    commonPrint.log('用户登出');
    await XBoardSDK.logout();
    await _storageService.clearAuthData();
    state = const UserAuthState(
      isInitialized: true,
    );
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


// File: lib/widgets/splash_bootstrap.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';

class SplashBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  final Duration maxWait;
  const SplashBootstrap({Key? key, required this.child, this.maxWait = const Duration(seconds: 3)}) : super(key: key);

  @override
  ConsumerState<SplashBootstrap> createState() => _SplashBootstrapState();
}

class _SplashBootstrapState extends ConsumerState<SplashBootstrap> with SingleTickerProviderStateMixin {
  bool _showChild = false;
  Timer? _timeoutTimer;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _timeoutTimer = Timer(widget.maxWait, () {
      if (mounted) {
        _enterApp(reason: 'timeout');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeEnterNow());
  }

  void _maybeEnterNow() {
    final auth = ref.read(xboardUserAuthProvider);
    final sub = ref.read(subscriptionInfoProvider);
    final initialized = auth.isInitialized;
    final canEnterIfReady = !auth.isAuthenticated || auth.isAuthenticated && (sub != null || ref.read(userInfoProvider) != null);

    if (initialized && canEnterIfReady) {
      _enterApp(reason: 'ready');
    } else {
      ref.listen(xboardUserAuthProvider, (previous, next) {
        if (!_showChild) _maybeEnterNow();
      });
      ref.listen(subscriptionInfoProvider, (previous, next) {
        if (!_showChild) _maybeEnterNow();
      });
      ref.listen(userInfoProvider, (previous, next) {
        if (!_showChild) _maybeEnterNow();
      });
    }
  }

  void _enterApp({required String reason}) {
    if (_showChild) return;
    _timeoutTimer?.cancel();
    setState(() {
      _showChild = true;
    });
    _fadeController.forward();
    commonPrint.log('[SplashBootstrap] enterApp due to: $reason');
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        FadeTransition(
          opacity: _fadeController.drive(CurveTween(curve: Curves.easeInOut)),
          child: Offstage(offstage: !_showChild, child: widget.child),
        ),
        if (!_showChild)
          Positioned.fill(
            child: _BootSplash(backgroundColor: bg),
          ),
      ],
    );
  }
}

class _BootSplash extends StatelessWidget {
  final Color? backgroundColor;
  const _BootSplash({Key? key, this.backgroundColor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 84, width: 84, child: FlutterLogo()),
            const SizedBox(height: 16),
            const Text('正在同步账户信息...', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
              ),
              child: Column(
                children: const [
                  SizedBox(height: 8),
                  SizedBox(height: 12, child: LinearProgressIndicator()),
                  SizedBox(height: 8),
                  SizedBox(height: 12, child: LinearProgressIndicator()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// File: lib/main.dart (入口示例)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/widgets/splash_bootstrap.dart';
import 'package:fl_clash/app/main_nav.dart'; // 你的主导航

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlClash',
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFF7F7F7)),
      home: const SplashBootstrap(child: MainNavigator()),
    );
  }
}


// File: lib/widgets/subscription_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';

class SubscriptionCard extends ConsumerWidget {
  const SubscriptionCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionInfoProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: sub == null
          ? _EmptySubscriptionPlaceholder(key: const ValueKey('empty_sub'))
          : _SubscriptionView(sub, key: ValueKey('sub_${sub.hashCode}')),
    );
  }
}

class _EmptySubscriptionPlaceholder extends StatelessWidget {
  const _EmptySubscriptionPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 12),
          Text('无套餐信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('正在同步或请稍后刷新', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SubscriptionView extends StatelessWidget {
  final dynamic sub;
  const _SubscriptionView(this.sub, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 这里根据你的 SubscriptionData 字段渲染
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('套餐：${sub.name ?? '未知'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('到期：${sub.expireAt ?? '—'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
