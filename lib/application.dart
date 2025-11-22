import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'controller.dart';
import 'pages/pages.dart';
import 'xboard/xboard.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/features/online_support/providers/websocket_auto_connector.dart';
import 'package:fl_clash/xboard/router/app_router.dart' as xboard_router;
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/remote_task/remote_task_manager.dart';

class Application extends ConsumerStatefulWidget {
  const Application({
    super.key,
  });

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  Timer? _autoUpdateGroupTaskTimer;
  Timer? _autoUpdateProfilesTaskTimer;

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: CommonPageTransitionsBuilder(),
      TargetPlatform.windows: CommonPageTransitionsBuilder(),
      TargetPlatform.linux: CommonPageTransitionsBuilder(),
      TargetPlatform.macOS: CommonPageTransitionsBuilder(),
    },
  );

  ColorScheme _getAppColorScheme({
    required Brightness brightness,
    int? primaryColor,
  }) {
    return ref.read(genColorSchemeProvider(brightness));
  }

  @override
  void initState() {
    super.initState();
    _autoUpdateGroupTask();
    _autoUpdateProfilesTask();
    globalState.appController = AppController(context, ref);

    // 注册远程任务推送回调，用于在订阅变更时主动刷新本地订阅/用量信息
    RemoteTaskManager.onSubscriptionRefreshRequested = () async {
      try {
        final notifier = ref.read(xboardUserProvider.notifier);
        await notifier.refreshSubscriptionInfo();
      } catch (e) {
        debugPrint('[Application] 处理订阅刷新推送时出错: $e');
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      final currentContext = globalState.navigatorKey.currentContext;
      if (currentContext != null) {
        globalState.appController = AppController(currentContext, ref);
      }
      await globalState.appController.init();
      globalState.appController.initLink();
      app?.initShortcuts();
      
      // 使用新的域名服务架构，简化认证检查
      _performQuickAuthWithDomainService();
      
      // 启动后检查更新
      _checkForUpdates();
      
    });
  }

  /// 使用新域名服务架构进行快速认证检查
  void _performQuickAuthWithDomainService() {
    // 立即检查token存在性，不延迟
    Future.microtask(() async {
      try {
        print('[Application] 开始使用新域名服务进行快速认证检查...');

        // 优先获取Flclash入口域名
        String? entryDomain;

        try {
          // 使用竞速方式获取最快的入口域名（带30秒超时）
          entryDomain = await XBoardConfig.getFastestPanelUrl()
              .timeout(const Duration(seconds: 30));
          print('[Application] 竞速获取到最快Flclash入口域名: $entryDomain');
        } catch (e) {
          print('[Application] 竞速获取域名失败，尝试传统方式: $e');
          // 降级到传统方式
          try {
            entryDomain = XBoardConfig.panelUrl;
            print('[Application] 传统方式获取到Flclash入口域名: $entryDomain');
          } catch (e2) {
            print('[Application] 获取Flclash入口域名完全失败: $e2');
            entryDomain = null;
          }
        }

        final userNotifier = ref.read(xboardUserProvider.notifier);
        // 执行快速认证，带20秒超时保护
        try {
          await userNotifier.quickAuth()
              .timeout(const Duration(seconds: 20));
          print('[Application] 快速认证检查完成');
        } on TimeoutException {
          print('[Application] 快速认证超时（20秒）');
          // 标记初始化失败但保持应用可用
          userNotifier.markInitializationTimeout();
        }

        // 强制刷新UI，确保路由能够响应最新的认证状态
        if (mounted) {
          setState(() {});
        }

      } catch (e) {
        print('[Application] 快速认证检查失败: $e');
        // 即使认证检查失败，也要确保UI能正常显示
        if (mounted) {
          setState(() {});
        }
      }
    });
  }


  /// 检查应用更新
  void _checkForUpdates() {
    // 延迟5秒后检查更新，确保应用完全启动
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        debugPrint('[Application] 开始自动检查更新...');
        final updateNotifier = ref.read(updateCheckProvider.notifier);
        await updateNotifier.checkForUpdates();
        
        // 检查是否有更新
        final updateState = ref.read(updateCheckProvider);
        if (updateState.hasUpdate && mounted) {
          final currentContext = globalState.navigatorKey.currentContext;
          if (currentContext != null) {
            debugPrint('[Application] 发现新版本，显示更新弹窗');
            // 显示更新弹窗
            showDialog(
              context: currentContext,
              barrierDismissible: !updateState.forceUpdate, // 强制更新时不能取消
              builder: (context) => UpdateDialog(state: updateState),
            );
          }
        } else if (updateState.error != null) {
          debugPrint('[Application] 自动更新检查失败，忽略错误: ${updateState.error}');
          // 自动检查失败时静默处理，不打扰用户
        } else {
          debugPrint('[Application] 已是最新版本');
        }
      } catch (e) {
        debugPrint('[Application] 自动更新检查异常: $e');
        // 自动检查异常时静默处理，不影响应用正常使用
      }
    });
  }

  _autoUpdateGroupTask() {
    _autoUpdateGroupTaskTimer = Timer(const Duration(milliseconds: 20000), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        globalState.appController.updateGroupsDebounce();
        _autoUpdateGroupTask();
      });
    });
  }

  _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await globalState.appController.autoUpdateProfiles();
      _autoUpdateProfilesTask();
    });
  }

  _buildPlatformState(Widget child) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(
            child: ProxyManager(
              child: child,
            ),
          ),
        ),
      );
    }
    return AndroidManager(
      child: TileManager(
        child: child,
      ),
    );
  }

  _buildState(Widget child) {
    return AppStateManager(
      child: ClashManager(
        child: ConnectivityManager(
          onConnectivityChanged: (results) async {
            if (!results.contains(ConnectivityResult.vpn)) {
              await clashCore.closeConnections();
            }
            globalState.appController.updateLocalIp();
            globalState.appController.addCheckIpNumDebounce();
          },
          child: child,
        ),
      ),
    );
  }

  _buildPlatformApp(Widget child) {
    if (system.isDesktop) {
      return WindowHeaderContainer(
        child: child,
      );
    }
    return VpnManager(
      child: child,
    );
  }

  _buildApp(Widget child) {
    return MessageManager(
      child: ThemeManager(
        child: child,
      ),
    );
  }

  @override
  Widget build(context) {
    return _buildPlatformState(
      _buildState(
        Consumer(
          builder: (_, ref, child) {
            // 初始化 WebSocket 自动连接器 - 监听登录状态并自动管理 WebSocket 连接
            // 这个 Provider 会在登录成功时自动连接,登出时自动断开
            ref.watch(webSocketAutoConnectorProvider);

            final locale =
                ref.watch(appSettingProvider.select((state) => state.locale));
            final themeProps = ref.watch(themeSettingProvider);
            final userState = ref.watch(xboardUserProvider);
            
            // 使用 go_router 的路由系统
            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate
              ],
              builder: (_, child) {
                return AppEnvManager(
                  child: _buildPlatformApp(
                    _buildApp(child!),
                  ),
                );
              },
              routerConfig: _buildRouter(userState),
              scrollBehavior: BaseScrollBehavior(),
              title: appName,
              locale: utils.getLocaleForString(locale),
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              themeMode: themeProps.themeMode,
              theme: ThemeData(
                useMaterial3: true,
                pageTransitionsTheme: _pageTransitionsTheme,
                colorScheme: _getAppColorScheme(
                  brightness: Brightness.light,
                  primaryColor: themeProps.primaryColor,
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                pageTransitionsTheme: _pageTransitionsTheme,
                colorScheme: _getAppColorScheme(
                  brightness: Brightness.dark,
                  primaryColor: themeProps.primaryColor,
                ).toPureBlack(themeProps.pureBlack),
              ),
            );
          },
        ),
      ),
    );
  }

  // 构建带认证重定向的路由器
  GoRouter _buildRouter(UserAuthState userState) {
    return GoRouter(
      navigatorKey: globalState.navigatorKey,
      initialLocation: '/',
      routes: xboard_router.routes,
      redirect: (context, state) {
        final isAuthenticated = userState.isAuthenticated;
        final isInitialized = userState.isInitialized;
        final isLoginPage = state.uri.path == '/login';

        // 初始化中，显示加载页面
        if (!isInitialized) {
          return '/loading';
        }

        // 未认证且不在登录页，跳转到登录页
        if (!isAuthenticated && !isLoginPage) {
          return '/login';
        }

        // 已认证且在登录页，跳转到首页
        if (isAuthenticated && isLoginPage) {
          return '/';
        }

        return null; // 不重定向
      },
    );
  }

  @override
  Future<void> dispose() async {
    try {
      linkManager.destroy();
      _autoUpdateGroupTaskTimer?.cancel();
      _autoUpdateProfilesTaskTimer?.cancel();

      // 清理远程任务推送回调，防止内存泄漏
      RemoteTaskManager.onSubscriptionRefreshRequested = null;
      
      // 释放XBoard SDK资源
      try {
        XBoardSDK.dispose();
      // ignore: empty_catches
      } catch (e) {
      }
      
      await clashCore.destroy();
      await globalState.appController.savePreferences();
      await globalState.appController.handleExit();
      
    // ignore: empty_catches
    } catch (e) {
    }
    
    super.dispose();
  }
}

// ✅ 旧的 _AppHomeRouter 已被 go_router 替代
// go_router 通过 redirect 函数自动处理认证重定向