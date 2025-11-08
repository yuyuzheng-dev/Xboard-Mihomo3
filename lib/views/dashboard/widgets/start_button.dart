import 'dart:math' show max;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerStatefulWidget {
  const StartButton({super.key});

  @override
  ConsumerState<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool isStart = false;

  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;
    _controller = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    ref.listenManual(
      runTimeProvider.select((state) => state != null),
      (prev, next) {
        if (next != isStart) {
          isStart = next;
          updateController();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  handleSwitchStart() {
    isStart = !isStart;
    updateController();
    debouncer.call(
      FunctionTag.updateStatus,
      () {
        globalState.appController.updateStatus(isStart);
      },
      duration: commonDuration,
    );
  }

  updateController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isStart) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(startButtonSelectorStateProvider);
    if (!state.isInit || !state.hasProfile) {
      return Container();
    }
    return Theme(
      data: Theme.of(context).copyWith(
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          sizeConstraints: const BoxConstraints(
            minWidth: 56,
            maxWidth: 240,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller.view,
        builder: (_, child) {
          final labelStyle = context.textTheme.titleMedium?.toSoftBold;
          final timeWidth = globalState.measure
                  .computeTextSize(
                    Text(
                      '99:59:59',
                      style: labelStyle,
                    ),
                  )
                  .width +
              16;
          final startLabel = AppLocalizations.of(context).xboardStartProxy;
          final startWidth = globalState.measure
                  .computeTextSize(
                    Text(
                      startLabel,
                      style: labelStyle,
                    ),
                  )
                  .width +
              16;
          final textWidth = max(timeWidth, startWidth);
          return FloatingActionButton(
            backgroundColor:
                isStart ? context.colorScheme.primary : Colors.red,
            foregroundColor: Colors.white,
            clipBehavior: Clip.antiAlias,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            heroTag: null,
            onPressed: () {
              handleSwitchStart();
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  height: 56,
                  width: 56,
                  alignment: Alignment.center,
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _animation,
                    color: Colors.white,
                  ),
                ),
                SizedBox(
                  width: textWidth,
                  child: child!,
                )
              ],
            ),
          );
        },
        child: Consumer(
          builder: (_, ref, __) {
            final runTime = ref.watch(runTimeProvider);
            final text = runTime == null
                ? AppLocalizations.of(context).xboardStartProxy
                : utils.getTimeText(runTime);
            return Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style:
                  Theme.of(context).textTheme.titleMedium?.toSoftBold.copyWith(
                        color: Colors.white,
                      ),
            );
          },
        ),
      ),
    );
  }
}
