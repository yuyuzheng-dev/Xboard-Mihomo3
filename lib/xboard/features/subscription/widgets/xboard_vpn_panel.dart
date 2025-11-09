import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';

class XBoardVpnPanel extends ConsumerStatefulWidget {
  const XBoardVpnPanel({super.key});

  @override
  ConsumerState<XBoardVpnPanel> createState() => _XBoardVpnPanelState();
}

class _XBoardVpnPanelState extends ConsumerState<XBoardVpnPanel>
    with TickerProviderStateMixin {
  late AnimationController _toggleController; // play/pause 图标与主按钮补间
  late Animation<double> _toggleAnimation;

  late AnimationController _pulseController; // 连接时的脉冲动画
  late AnimationController _pressScaleController; // 点击缩放反馈

  bool isStart = false;

  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;

    _toggleController = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 260),
    );
    _toggleAnimation = CurvedAnimation(
      parent: _toggleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (isStart) {
      _pulseController.repeat();
    }

    _pressScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.06,
      value: 0.0,
    );

    ref.listenManual(
      runTimeProvider.select((state) => state != null),
      (prev, next) {
        if (next != isStart) {
          isStart = next;
          _updateControllers();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _toggleController.dispose();
    _pulseController.dispose();
    _pressScaleController.dispose();
    super.dispose();
  }

  void _handleToggle() {
    isStart = !isStart;
    _updateControllers();
    debouncer.call(
      FunctionTag.updateStatus,
      () {
        globalState.appController.updateStatus(isStart);
      },
      duration: commonDuration,
    );
  }

  void _updateControllers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isStart) {
        _toggleController.forward();
        if (!_pulseController.isAnimating) {
          _pulseController.repeat();
        }
      } else {
        _toggleController.reverse();
        if (_pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(startButtonSelectorStateProvider);
    if (!state.isInit || !state.hasProfile) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 配色：暗色模式使用浅色前景，亮色使用更饱和的颜色
    final connectColor = isDark ? Colors.green.shade200 : Colors.green.shade600;
    final disconnectColor = isDark ? Colors.red.shade300 : Colors.red;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isStart ? connectColor : disconnectColor).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildConnectArea(context, connectColor, disconnectColor),
            const SizedBox(height: 8),
            _buildStatusText(context, isDark),
            const SizedBox(height: 12),
            _buildQuickStats(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.shield_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          AppLocalizations.of(context).xboardProxy, // 复用已有文案
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _buildConnectArea(
    BuildContext context,
    Color connectColor,
    Color disconnectColor,
  ) {
    final baseSize = 116.0;

    return Center(
      child: GestureDetector(
        onTapDown: (_) {
          _pressScaleController.forward();
        },
        onTapCancel: () {
          _pressScaleController.reverse();
        },
        onTapUp: (_) {
          _pressScaleController.reverse();
        },
        onTap: _handleToggle,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _toggleController,
            _pulseController,
            _pressScaleController,
          ]),
          builder: (context, child) {
            final scale = 1 - _pressScaleController.value; // 点击微缩放
            final activeColor = isStart ? connectColor : disconnectColor;

            return SizedBox(
              width: baseSize * 2,
              height: baseSize * 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 脉冲波纹
                  if (isStart) ...List.generate(3, (i) {
                    final t = (_pulseController.value + i / 3) % 1.0;
                    final ringSize = baseSize * (1 + t * 1.4);
                    final opacity = (1 - t) * 0.45;
                    return Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: opacity),
                            blurRadius: 24 * t + 6,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: activeColor.withValues(alpha: opacity),
                          width: 1.2,
                        ),
                      ),
                    );
                  }),

                  // 主按钮
                  Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            activeColor.withValues(alpha: 0.95),
                            activeColor.withValues(alpha: 0.75),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: baseSize,
                        height: baseSize,
                        child: Center(
                          child: AnimatedIcon(
                            icon: AnimatedIcons.play_pause,
                            progress: _toggleAnimation,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusText(BuildContext context, bool isDark) {
    return Consumer(
      builder: (context, ref, _) {
        final runTime = ref.watch(runTimeProvider);
        final textTheme = Theme.of(context).textTheme;

        final statusText = isStart
            ? AppLocalizations.of(context).xboardStopProxy
            : AppLocalizations.of(context).xboardStartProxy;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                statusText,
                key: ValueKey(isStart),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isStart) ...[
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  AppLocalizations.of(context).xboardRunningTime(
                    utils.getTimeText(runTime),
                  ),
                  key: ValueKey(runTime),
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final traffics = ref.watch(trafficsProvider).list;
        final last = traffics.isEmpty ? null : traffics.last;
        final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
        final tunOn =
            ref.watch(patchClashConfigProvider.select((s) => s.tun.enable));

        final String up = last != null ? last.up.toString() : '0B';
        final String down = last != null ? last.down.toString() : '0B';

        final chipTextStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            );

        Widget buildChip(IconData icon, String text) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    style: chipTextStyle,
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  buildChip(Icons.file_upload_outlined, '↑ $up'),
                  buildChip(Icons.file_download_outlined, '↓ $down'),
                ],
              ),
            ),
            buildChip(
              mode == Mode.global ? Icons.public : Icons.rule,
              mode == Mode.global
                  ? AppLocalizations.of(context).global
                  : AppLocalizations.of(context).rule,
            ),
            const SizedBox(width: 8),
            buildChip(
              Icons.stacked_line_chart,
              tunOn
                  ? AppLocalizations.of(context).xboardTunEnabled
                  : 'TUN OFF',
            ),
          ],
        );
      },
    );
  }
}
