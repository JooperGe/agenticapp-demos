import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/scene_model.dart';

/// Immutable snapshot consumed by [UrbanrunHud].
@immutable
class GameHudState {
  const GameHudState({
    required this.sceneName,
    required this.visitedCount,
    required this.complete,
    required this.interactionLabel,
    required this.playerPosition,
    this.errorMessage,
    this.successMessage,
    this.scene = SceneId.street,
    this.sceneModel,
  });

  const GameHudState.street()
    : sceneName = '探索街区',
      visitedCount = 0,
      complete = false,
      interactionLabel = null,
      playerPosition = const Point2(1.5, 1.5),
      errorMessage = null,
      successMessage = null,
      scene = SceneId.street,
      sceneModel = null;

  final String sceneName;
  final int visitedCount;
  final bool complete;
  final String? interactionLabel;
  final Point2 playerPosition;
  final String? errorMessage;
  final String? successMessage;
  final SceneId scene;
  final SceneModel? sceneModel;

  // Compatibility aliases for the state API used by earlier game tasks.
  int get visitedBuildings => visitedCount;
  String? get nearbyLabel => interactionLabel;
  String? get message => errorMessage;
}

class UrbanrunHud extends StatelessWidget {
  const UrbanrunHud({super.key, required this.state, required this.onInteract});

  final ValueListenable<GameHudState> state;
  final VoidCallback onInteract;

  static const _navy = Color(0xE60B1728);
  static const _navyLight = Color(0xCC13263A);
  static const _offWhite = Color(0xFFF2F1E8);
  static const _muted = Color(0xFFB6C8C4);
  static const _cyan = Color(0xFF65D5B3);
  static const _danger = Color(0xFFFFA49A);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameHudState>(
      valueListenable: state,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = width < 1080;
            final rightWidth = (width * (compact ? .29 : .22)).clamp(
              208.0,
              286.0,
            );
            final leftWidth = (width * .24).clamp(190.0, 250.0);
            final minimapHeight = compact ? 132.0 : 150.0;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: leftWidth,
                      child: _RoleBadge(
                        width: leftWidth,
                        sceneName: value.sceneName,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: rightWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _Panel(
                            child: SizedBox(
                              height: minimapHeight,
                              child: CustomPaint(
                                painter: _MinimapPainter(
                                  model: value.sceneModel,
                                  scene: value.scene,
                                  playerPosition: value.playerPosition,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      value.sceneName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _offWhite,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ExplorationCard(value: value),
                        ],
                      ),
                    ),
                  ),
                ),
                if (value.interactionLabel != null)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 72),
                        child: _InteractionPrompt(
                          label: value.interactionLabel!,
                          onInteract: onInteract,
                        ),
                      ),
                    ),
                  ),
                if (value.errorMessage != null || value.successMessage != null)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 128),
                        child: _FeedbackMessage(
                          text: value.errorMessage ?? value.successMessage!,
                          isError: value.errorMessage != null,
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _ControlHints(compact: compact),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.width, required this.sceneName});

  final double width;
  final String sceneName;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: UrbanrunHud._cyan,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.directions_run,
              color: Color(0xFF08201F),
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'URBANRUN',
                  style: TextStyle(
                    color: UrbanrunHud._offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  sceneName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UrbanrunHud._muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorationCard extends StatelessWidget {
  const _ExplorationCard({required this.value});

  final GameHudState value;

  @override
  Widget build(BuildContext context) {
    final color = value.complete ? UrbanrunHud._cyan : UrbanrunHud._offWhite;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.explore_outlined,
                color: UrbanrunHud._cyan,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '探索街区 ${value.visitedCount}/2',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value.visitedCount / 2).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: UrbanrunHud._navyLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                UrbanrunHud._cyan,
              ),
            ),
          ),
          if (value.complete) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              '区域已探索',
              style: TextStyle(
                color: UrbanrunHud._cyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InteractionPrompt extends StatelessWidget {
  const _InteractionPrompt({required this.label, required this.onInteract});

  final String label;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label (E)',
      child: GestureDetector(
        key: const Key('hud-interaction-button'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) => onInteract(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: UrbanrunHud._navy,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: UrbanrunHud._cyan.withValues(alpha: .8)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: UrbanrunHud._cyan,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    'E',
                    style: TextStyle(
                      color: Color(0xFF08201F),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: UrbanrunHud._offWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackMessage extends StatelessWidget {
  const _FeedbackMessage({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: isError ? const Color(0xE6331D2A) : const Color(0xE610302C),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? UrbanrunHud._danger : UrbanrunHud._cyan,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ControlHints extends StatelessWidget {
  const _ControlHints({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: const <Widget>[
          _Hint(label: 'WASD / 箭头', value: '移动'),
          _Hint(label: 'Shift', value: '奔跑'),
          _Hint(label: 'E', value: '互动'),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: UrbanrunHud._muted, fontSize: 11),
        children: <InlineSpan>[
          TextSpan(
            text: '$label  ',
            style: const TextStyle(
              color: UrbanrunHud._offWhite,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.color = UrbanrunHud._navy,
  });

  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x334DD0BF)),
      ),
      child: child,
    );
  }
}

class _MinimapPainter extends CustomPainter {
  const _MinimapPainter({
    required this.model,
    required this.scene,
    required this.playerPosition,
  });

  final SceneModel? model;
  final SceneId scene;
  final Point2 playerPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final sceneBounds = model?.bounds ?? _fallbackBounds(scene);
    final inset = 12.0;
    final map = Rect.fromLTWH(
      inset,
      inset + 16,
      size.width - inset * 2,
      size.height - inset * 2 - 16,
    );
    final sx = map.width / sceneBounds.width;
    final sy = map.height / sceneBounds.height;

    final background = Paint()..color = const Color(0xFF182B3A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(map, const Radius.circular(11)),
      background,
    );

    final road = Paint()
      ..color = const Color(0xFF31515B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene == SceneId.street ? 10 : 5;
    if (scene == SceneId.street) {
      canvas.drawLine(
        Offset(map.left, map.top + map.height * .52),
        Offset(map.right, map.top + map.height * .52),
        road,
      );
      canvas.drawLine(
        Offset(map.left + map.width * .5, map.top),
        Offset(map.left + map.width * .5, map.bottom),
        road,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(map.deflate(17), const Radius.circular(6)),
        road,
      );
    }

    final obstaclePaint = Paint()..color = const Color(0xFF53716D);
    for (final obstacle in model?.obstacles ?? const <Obstacle>[]) {
      final rect = _mapRect(obstacle.bounds, sceneBounds, map, sx, sy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        obstaclePaint,
      );
    }
    final entrancePaint = Paint()..color = UrbanrunHud._cyan;
    for (final entrance in model?.entrances ?? const <Entrance>[]) {
      final point = _mapPoint(entrance.position, sceneBounds, map, sx, sy);
      canvas.drawCircle(point, 3.5, entrancePaint);
    }
    final playerPaint = Paint()..color = UrbanrunHud._offWhite;
    canvas.drawCircle(
      _mapPoint(playerPosition, sceneBounds, map, sx, sy),
      4.5,
      playerPaint,
    );
    canvas.drawCircle(
      _mapPoint(playerPosition, sceneBounds, map, sx, sy),
      7.5,
      Paint()
        ..color = UrbanrunHud._cyan.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  Rect _mapRect(
    Bounds2 value,
    Bounds2 sceneBounds,
    Rect map,
    double sx,
    double sy,
  ) {
    return Rect.fromLTRB(
      map.left + (value.left - sceneBounds.left) * sx,
      map.top + (value.top - sceneBounds.top) * sy,
      map.left + (value.right - sceneBounds.left) * sx,
      map.top + (value.bottom - sceneBounds.top) * sy,
    );
  }

  Offset _mapPoint(
    Point2 value,
    Bounds2 sceneBounds,
    Rect map,
    double sx,
    double sy,
  ) {
    return Offset(
      (map.left + (value.x - sceneBounds.left) * sx).clamp(map.left, map.right),
      (map.top + (value.y - sceneBounds.top) * sy).clamp(map.top, map.bottom),
    );
  }

  Bounds2 _fallbackBounds(SceneId id) => id == SceneId.street
      ? const Bounds2(0, 0, 24, 24)
      : const Bounds2(0, 0, 10, 8);

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.scene != scene ||
      oldDelegate.playerPosition != playerPosition;
}
