import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/infrastructure/network/domain_racing_service.dart';

// 初始化文件级日志器
final _logger = FileLogger('domain_status_service.dart');


/// 域名状态服务
/// 
/// 负责域名检测、状态管理和XBoard服务初始化
class DomainStatusService {
  // 使用V2配置模块
  bool _isInitialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.info('开始初始化');
      
      // 确保V2配置模块已初始化
      if (!XBoardConfig.isInitialized) {
        await XBoardConfig.initialize();
      }

      _logger.info('V2配置模块初始化成功');

      _isInitialized = true;
      _logger.info('初始化完成');
    } catch (e) {
      _logger.error('初始化失败', e);
      rethrow;
    }
  }

  /// 检查域名状态
  Future<Map<String, dynamic>> checkDomainStatus() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('开始检查域名状态');

      // 真实测试所有面板域名，避免错误的“可用”判断
      final allDomains = XBoardConfig.allPanelUrls;
      if (allDomains.isEmpty) {
        _logger.warning('配置中没有面板域名');
        return {
          'success': false,
          'domain': null,
          'latency': null,
          'availableDomains': <String>[],
          'message': '未配置面板域名',
        };
      }

      final results = await DomainRacingService.testAllDomains(allDomains);
      // 选取第一个成功的结果
      final winner = results.firstWhere(
        (r) => r.success,
        orElse: () => DomainTestResult.failure('', '全部失败', 0),
      );

      if (winner.success && winner.domain.isNotEmpty) {
        final bestDomain = winner.domain;
        final latency = winner.responseTime;

        // 初始化XBoard服务（使用检测到的最佳域名）
        await _initializeXBoardService(bestDomain);

        _logger.info('域名检查成功: $bestDomain (${latency}ms)');
        return {
          'success': true,
          'domain': bestDomain,
          'latency': latency,
          'availableDomains': allDomains,
          'message': null,
        };
      }

      _logger.warning('未找到可用域名');
      return {
        'success': false,
        'domain': null,
        'latency': null,
        'availableDomains': <String>[],
        'message': '无法获取可用域名',
      };
    } catch (e) {
      _logger.error('域名检查失败', e);
      return {
        'success': false,
        'domain': null,
        'latency': null,
        'availableDomains': <String>[],
        'message': '域名检查失败: $e',
      };
    }
  }

  /// 刷新域名缓存
  Future<void> refreshDomainCache() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('刷新域名缓存');
      // 使用config_v2刷新配置
      await XBoardConfig.refresh();
    } catch (e) {
      _logger.error('刷新缓存失败', e);
      rethrow;
    }
  }

  /// 验证特定域名
  Future<bool> validateDomain(String domain) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('验证域名: $domain');
      // 简化验证：检查域名是否在可用列表中
      final availableDomains = XBoardConfig.allPanelUrls;
      return availableDomains.contains(domain);
    } catch (e) {
      _logger.error('域名验证失败', e);
      return false;
    }
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    return XBoardConfig.stats;
  }

  /// 初始化XBoard服务
  Future<void> _initializeXBoardService(String domain) async {
    try {
      _logger.info('初始化XBoard服务: $domain');
      
      await XBoardSDK.initialize(
        configProvider: XBoardConfig.provider,
        baseUrl: domain,
        strategy: 'first',
      );
      
      _logger.info('XBoard服务初始化成功');
    } catch (e) {
      _logger.error('XBoard服务初始化失败', e);
      // 不抛出异常，因为域名检查已经成功
    }
  }

  /// 释放资源
  void dispose() {
    _logger.info('释放资源');
    _isInitialized = false;
  }
}