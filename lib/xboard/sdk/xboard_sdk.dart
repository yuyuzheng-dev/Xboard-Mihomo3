/// XBoard SDK Wrapper - SDK 封装层
///
/// 本模块封装 flutter_xboard_sdk，提供统一的访问入口和便捷方法
///
/// 核心职责：
/// 1. SDK 初始化和配置管理
/// 2. 多域名切换和竞速选择
/// 3. 统一的 API 访问接口
/// 4. 便捷方法封装（减少重复代码）
///
/// 使用示例：
/// ```dart
/// import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
///
/// // 1. 初始化（通过配置提供者）
/// await XBoardSDK.initialize(configProvider: XBoardConfig);
///
/// // 2. 使用 API
/// final userInfo = await XBoardSDK.getUserInfo();
/// final plans = await XBoardSDK.getPlans();
/// await XBoardSDK.login(email: email, password: password);
/// ```
library;

import 'dart:async';

import 'src/xboard_client.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart' as sdk;
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/config/interface/config_provider_interface.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/xboard/infrastructure/infrastructure.dart';
import 'package:fl_clash/xboard/features/remote_task/remote_task_manager.dart';

// ========== 核心客户端 ==========
export 'src/xboard_client.dart';

// ========== 直接导出 SDK 模型和 API ==========
// 不再维护自定义模型，直接使用 SDK 的 Freezed 模型
// 注意：重导出时要避免名称冲突
export 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart'
    hide XBoardException; // 使用我们自己的XBoardException

// ========== 工具类 ==========
export 'src/utils/subscription_url_transformer.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_sdk.dart');

// ========== 为了向后兼容，提供类型别名 ==========
typedef UserInfoData = sdk.UserInfo;
typedef SubscriptionData = sdk.SubscriptionInfo;
typedef PlanData = sdk.Plan;
typedef OrderData = sdk.Order;
typedef PaymentMethodData = sdk.PaymentMethodInfo;
typedef PaymentMethod = sdk.PaymentMethodInfo; // 主要别名
typedef PaymentMethodInfoData = sdk.PaymentMethodInfo;
typedef InviteData = sdk.InviteInfo;
typedef InviteCodeData = sdk.InviteCode;
typedef CommissionDetailData = sdk.CommissionDetail;
typedef CommissionHistoryItem =
    sdk.CommissionDetail; // SDK中没有单独的HistoryItem
typedef CommissionHistoryItemData = sdk.CommissionDetail;
typedef WithdrawResultData = sdk.WithdrawResult;
typedef TransferResultData = sdk.TransferResult;
typedef VerificationCodeResponseData = sdk.ApiResponse<dynamic>;
typedef NoticeData = sdk.Notice;
typedef TicketData = sdk.Ticket;
typedef Ticket = sdk.TicketDetail; // TicketDetail是Ticket的扩展版

/// XBoard SDK - SDK 封装类
///
/// 这是应用中访问 XBoard 功能的 **统一入口**。
///
/// ## 核心职责
/// - SDK 初始化和生命周期管理
/// - 多域名竞速选择和自动切换
/// - 统一的 API 访问接口
///
/// ## 使用规范（必读！）
///
/// ### ✅ 正确用法：通过 XBoardSDK 调用
/// ```dart
/// // 1. 初始化（应用启动时）
/// await XBoardSDK.initialize(configProvider: XBoardConfig);
///
/// // 2. 使用 API
/// final userInfo = await XBoardSDK.getUserInfo();
/// final plans = await XBoardSDK.getPlans();
/// await XBoardSDK.login(email: email, password: password);
/// ```
///
/// ### ❌ 错误用法：不要直接访问底层 SDK
/// ```dart
/// // ❌ 禁止！不要这样做
/// final sdk = XBoardClient.instance.sdk;
/// ```
///
/// ## 设计原则
/// - **单一入口**：所有 XBoard 功能只通过 XBoardSDK 访问
/// - **依赖接口**：依赖 ConfigProviderInterface 而非具体实现
/// - **统一规范**：强制使用标准 API，避免混乱
/// - **易于维护**：集中管理，方便未来修改
class XBoardSDK {
  // 私有构造函数 - 禁止实例化
  XBoardSDK._();

  // 内部获取 SDK Client
  static XBoardClient get _client => XBoardClient.instance;
  static sdk.XBoardSDK get _sdk => _client.sdk;

  static Completer<void>? _initCompleter;
  static RemoteTaskManager? _remoteTaskManager;

  /// 对外暴露的延迟初始化方法（一般不需要手动调用，SDK 方法内部会自动调用）
  static Future<void> ensureInitialized() => _ensureInitialized();

  static Future<void> _ensureInitialized() async {
    if (isInitialized) return;

    // 已有初始化在进行中，直接等待
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      _logger.info('[SDK] 开始延迟初始化 XBoard SDK');

      // 1. 配置域名竞速所需的安全参数（证书等）
      await _configureSecurity();

      // 2. 初始化配置模块（从 assets/config/xboard.config.yaml 读取）
      if (!XBoardConfig.isInitialized) {
        final settings = await ConfigFileLoader.loadFromFile();
        _logger.info('[SDK] 从配置文件初始化 XBoardConfig, provider: '
            '${settings.currentProvider}');
        await XBoardConfig.initialize(settings: settings);
      }

      // 3. 使用配置模块选择最快的面板域名
      String? baseUrl;
      try {
        baseUrl = await XBoardConfig.getFastestPanelUrl();
        _logger.info('[SDK] 竞速获得面板域名: $baseUrl');
      } catch (e) {
        _logger.warning(
            '[SDK] 竞速获取面板域名失败，尝试使用首个面板地址: $e');
        baseUrl = XBoardConfig.panelUrl;
      }

      // 4. 初始化底层 SDK
      await initialize(
        configProvider: XBoardConfig.provider,
        baseUrl: baseUrl,
        strategy: baseUrl != null ? 'first' : 'race_fastest',
      );

      // 5. 初始化 RemoteTaskManager（用于远程任务和订阅刷新推送）
      try {
        _remoteTaskManager = await RemoteTaskManager.create();
        if (_remoteTaskManager != null) {
          _remoteTaskManager!.initialize();
          _remoteTaskManager!.start();
          _logger.info('[SDK] RemoteTaskManager 初始化成功');
        } else {
          _logger.warning(
              '[SDK] RemoteTaskManager 初始化失败 - 配置中未找到 WebSocket URL');
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

  /// 配置域名竞速所需的安全参数（自定义 CA 证书等）
  static Future<void> _configureSecurity() async {
    try {
      final certConfig = await ConfigFileLoaderHelper.getCertificateConfig();
      final certPath = certConfig['path'] as String?;
      final certEnabled = certConfig['enabled'] as bool? ?? true;

      if (certEnabled && certPath != null && certPath.isNotEmpty) {
        final fullCertPath =
            certPath.startsWith('packages/') ? certPath : 'packages/$certPath';
        DomainRacingService.setCertificatePath(fullCertPath);
        _logger.info('[SDK] 设置域名竞速证书路径: $fullCertPath');
      }
    } catch (e) {
      _logger.warning('[SDK] 加载证书配置失败（使用默认证书）: $e');
    }
  }

  // ========== 直接访问底层 SDK API（仅供向后兼容） ==========
  // 目前项目内部均通过封装好的静态方法访问 SDK，
  // 这些底层 API getter 暂无实际使用场景，且随着 SDK 升级容易产生命名不匹配问题，
  // 因此这里移除具体类型暴露，避免不必要的编译错误。

  // ========== 生命周期管理 ==========

  /// 初始化 SDK
  ///
  /// 一般情况下无需手动调用，推荐使用 [ensureInitialized] 或直接
  /// 调用任意 SDK 方法（内部会自动触发延迟初始化）。
  static Future<void> initialize({
    required ConfigProviderInterface configProvider,
    String? baseUrl,
    String strategy = 'race_fastest',
  }) async {
    return _client.initialize(
      configProvider: configProvider,
      baseUrl: baseUrl,
      strategy: strategy,
    );
  }

  /// 释放资源
  static void dispose() {
    _remoteTaskManager?.dispose();
    _remoteTaskManager = null;
    _client.dispose();
  }

  /// 获取当前域名
  static Future<String?> getCurrentDomain() async {
    await _ensureInitialized();
    return _client.getCurrentDomain();
  }

  /// 切换到最快的域名
  static Future<void> switchToFastestDomain() async {
    await _ensureInitialized();
    return _client.switchToFastestDomain();
  }

  /// 检查是否已初始化
  static bool get isInitialized => _client.isInitialized;

  // ========== 认证相关 ==========

  /// 登录
  static Future<bool> login({
    required String email,
    required String password,
  }) async {
    await _ensureInitialized();
    try {
      // 使用 loginWithCredentials 方法，它会自动保存 auth_data token
      final success = await _sdk.loginWithCredentials(email, password);
      if (success) {
        _logger.info('[SDK] 登录成功，authData token已保存');
        return true;
      }
      return false;
    } catch (e) {
      _logger.error('[SDK] 登录失败', e);
      return false;
    }
  }

  /// 注册
  static Future<sdk.UserInfo?> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    await _ensureInitialized();
    try {
      await _sdk.register.register(
        email,
        password,
        inviteCode ?? '',
        emailCode ?? '',
      );
      // 注册成功后返回null，因为API返回的是generic data
      return null;
    } catch (e) {
      _logger.error('[SDK] 注册失败', e);
      rethrow; // 重新抛出异常以便上层获取详细错误信息
    }
  }

  /// 登出
  static Future<bool> logout() async {
    await _ensureInitialized();
    try {
      await _sdk.clearToken();
      return true;
    } catch (e) {
      _logger.error('[SDK] 登出失败', e);
      return false;
    }
  }

  /// 重置密码
  static Future<bool> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.resetPassword.resetPassword(
        email: email,
        password: password,
        emailCode: emailCode,
      );
      return result.data ?? false;
    } catch (e) {
      _logger.error('[SDK] 重置密码失败', e);
      return false;
    }
  }

  /// 发送验证码
  static Future<bool> sendVerificationCode(String email) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.sendEmailCode.sendEmailCode(email);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 发送验证码失败', e);
      return false;
    }
  }

  /// 检查是否已登录
  static Future<bool> isLoggedIn() async {
    await _ensureInitialized();
    try {
      return _sdk.isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  /// 获取认证Token
  static Future<String?> getAuthToken() async {
    await _ensureInitialized();
    try {
      return await _sdk.getToken();
    } catch (e) {
      _logger.error('[SDK] 获取认证Token失败', e);
      return null;
    }
  }

  // ========== 用户相关 ==========

  /// 获取用户信息
  static Future<sdk.UserInfo?> getUserInfo() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.userInfo.getUserInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取用户信息失败', e);
      return null;
    }
  }

  // ========== 套餐相关 ==========

  /// 获取套餐列表
  static Future<List<sdk.Plan>> getPlans() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.plan.fetchPlans();
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取套餐列表失败', e);
      return [];
    }
  }

  // ========== 订阅相关 ==========

  /// 获取订阅信息
  static Future<sdk.SubscriptionInfo?> getSubscription() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.subscription.getSubscriptionInfo();
      return result;
    } catch (e) {
      _logger.error('[SDK] 获取订阅信息失败', e);
      return null;
    }
  }

  // ========== 订单相关 ==========

  /// 创建订单
  static Future<String?> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.order.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );
      // createOrder返回ApiResponse<String>
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 创建订单失败', e);
      return null;
    }
  }

  /// 获取订单列表
  static Future<List<sdk.Order>> getOrders() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.order.fetchUserOrders();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取订单列表失败', e);
      return [];
    }
  }

  /// 根据订单号获取订单详情
  static Future<sdk.Order?> getOrderByTradeNo(String tradeNo) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.order.getOrderDetails(tradeNo);
      return result;
    } catch (e) {
      _logger.error('[SDK] 获取订单详情失败', e);
      return null;
    }
  }

  /// 取消订单
  static Future<bool> cancelOrder(String tradeNo) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.order.cancelOrder(tradeNo);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 取消订单失败', e);
      return false;
    }
  }

  // ========== 支付相关 ==========

  /// 获取支付方式列表
  static Future<List<PaymentMethod>> getPaymentMethods() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.payment.getPaymentMethods();
      // API返回PaymentMethodInfo列表，PaymentMethod是其别名
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取支付方式失败', e);
      return [];
    }
  }

  /// 提交支付
  /// 返回 Map 包含 type 和 data
  /// type: -1 表示余额支付成功, 0 表示跳转支付, 1 表示二维码支付
  /// data: 支付URL或支付结果
  static Future<Map<String, dynamic>?> submitPayment({
    required String tradeNo,
    required int method,
  }) async {
    await _ensureInitialized();
    try {
      final request =
          sdk.PaymentRequest(tradeNo: tradeNo, method: method.toString());
      final result = await _sdk.payment.submitOrderPayment(request);
      // 返回完整的支付结果，包含 type 和 data
      final data = result.data;
      if (data != null) {
        return {
          'type': data['type'] ?? 0,
          'data': data['data'],
        };
      }
      return null;
    } catch (e) {
      _logger.error('[SDK] 提交支付失败', e);
      return null;
    }
  }

  /// 查询支付状态
  static Future<int?> checkPaymentStatus(String tradeNo) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.payment.checkPaymentStatus(tradeNo);
      final paymentResult = result.data;
      if (paymentResult != null) {
        if (paymentResult.isSuccess) return 3; // 支付成功
        if (paymentResult.isCanceled) return 2; // 已取消
        if (paymentResult.isPending) return 0; // 等待中
      }
      return null;
    } catch (e) {
      _logger.error('[SDK] 查询支付状态失败', e);
      return null;
    }
  }

  // ========== 邀请佣金相关 ==========

  /// 获取邀请信息
  static Future<sdk.InviteInfo?> getInviteInfo() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.invite.getInviteInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取邀请信息失败', e);
      return null;
    }
  }

  /// 生成邀请码
  static Future<sdk.InviteCode?> generateInviteCode() async {
    await _ensureInitialized();
    try {
      await _sdk.invite.generateInviteCode();
      // API返回void，需要重新获取邀请信息来获取新生成的码
      final info = await getInviteInfo();
      if (info != null && info.codes.isNotEmpty) {
        return info.codes.first;
      }
      return null;
    } catch (e) {
      _logger.error('[SDK] 生成邀请码失败', e);
      return null;
    }
  }

  /// 获取佣金历史
  static Future<List<CommissionHistoryItem>> getCommissionHistory({
    int current = 1,
    int pageSize = 100,
  }) async {
    await _ensureInitialized();
    try {
      // SDK的fetchCommissionDetails需要分页参数
      final result = await _sdk.invite.fetchCommissionDetails(
        current: current,
        pageSize: pageSize,
      );
      // 直接返回CommissionDetail列表，CommissionHistoryItem是其别名
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取佣金历史失败', e);
      return [];
    }
  }

  /// 提现佣金
  /// 注意：SDK中可能没有此API，这里仅作占位
  static Future<sdk.WithdrawResult?> withdrawCommission({
    required double amount,
    required String withdrawAccount,
  }) async {
    await _ensureInitialized();
    try {
      // SDK中可能没有此方法，返回null
      _logger.warning('[SDK] withdrawCommission API未实现');
      return null;
    } catch (e) {
      _logger.error('[SDK] 提现佣金失败', e);
      return null;
    }
  }

  /// 划转佣金到余额
  /// 注意：SDK中可能没有此API，这里仅作占位
  static Future<sdk.TransferResult?> transferCommissionToBalance(
      double amount) async {
    await _ensureInitialized();
    try {
      // SDK中可能没有此方法，返回null
      _logger.warning('[SDK] transferCommissionToBalance API未实现');
      return null;
    } catch (e) {
      _logger.error('[SDK] 划转佣金失败', e);
      return null;
    }
  }

  // ========== 优惠券相关 ==========

  /// 验证优惠券
  static Future<sdk.CouponData?> checkCoupon({
    required String code,
    required int planId,
  }) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.coupon.checkCoupon(code, planId);
      // 返回完整的优惠券数据，包含折扣类型和金额
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 验证优惠券失败', e);
      return null;
    }
  }

  // ========== 工单相关 ==========

  /// 获取工单列表
  static Future<List<sdk.Ticket>> getTickets() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.ticket.fetchTickets();
      return result.data ?? [];
    } catch (e) {
      _logger.error('[SDK] 获取工单列表失败', e);
      return [];
    }
  }

  /// 创建工单
  static Future<sdk.Ticket?> createTicket({
    required String subject,
    required String message,
    required int level,
  }) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.ticket.createTicket(
        subject: subject,
        message: message,
        level: level,
      );
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 创建工单失败', e);
      return null;
    }
  }

  /// 获取工单详情
  static Future<Ticket?> getTicketDetail(int id) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.ticket.getTicketDetail(id);
      // TicketDetail就是Ticket的别名
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取工单详情失败', e);
      return null;
    }
  }

  /// 回复工单
  static Future<bool> replyTicket({
    required int id,
    required String message,
  }) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.ticket.replyTicket(
        ticketId: id,
        message: message,
      );
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 回复工单失败', e);
      return false;
    }
  }

  /// 关闭工单
  static Future<bool> closeTicket(int id) async {
    await _ensureInitialized();
    try {
      final result = await _sdk.ticket.closeTicket(id);
      return result.success;
    } catch (e) {
      _logger.error('[SDK] 关闭工单失败', e);
      return false;
    }
  }

  // ========== 公告相关 ==========

  /// 获取公告列表
  static Future<List<sdk.Notice>> getNotices() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.notice.fetchNotices();
      return result.data ?? <sdk.Notice>[];
    } catch (e) {
      _logger.error('[SDK] 获取公告列表失败', e);
      return [];
    }
  }

  // ========== 配置相关 ==========

  /// 获取应用配置
  static Future<dynamic> getConfig() async {
    await _ensureInitialized();
    try {
      final config = await _sdk.config.getConfig();
      return config;
    } catch (e) {
      _logger.error('[SDK] 获取配置失败', e);
      return null;
    }
  }

  /// 获取应用信息
  static Future<sdk.AppInfo?> getAppInfo() async {
    await _ensureInitialized();
    try {
      final result = await _sdk.app.fetchDedicatedAppInfo();
      return result.data;
    } catch (e) {
      _logger.error('[SDK] 获取应用信息失败', e);
      return null;
    }
  }
}
