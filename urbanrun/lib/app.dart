import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/hud/urbanrun_hud.dart';
import 'game/urbanrun_game.dart';

class UrbanrunApp extends StatelessWidget {
  const UrbanrunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urbanrun',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1018),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0B1018),
          primary: Color(0xFF65D5B3),
        ),
      ),
      home: const _GameHost(),
    );
  }
}

class _GameHost extends StatefulWidget {
  const _GameHost();

  @override
  State<_GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<_GameHost> with WidgetsBindingObserver {
  late final UrbanrunGame _game;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = UrbanrunGame();
    _focusNode = FocusNode(debugLabel: 'Urbanrun keyboard focus')
      ..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _game.clearInput();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _game.resumeInput();
      _focusNode.requestFocus();
    } else {
      _game.clearInput();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            _game.onKeyDown(event.logicalKey);
          } else if (event is KeyUpEvent) {
            _game.onKeyUp(event.logicalKey);
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GameWidget(game: _game),
            UrbanrunHud(
              state: _game.hudState,
              onInteract: () {
                // The prompt acts on pointer-up and immediately restores the
                // keyboard focus used by the game host.
                _game.requestInteraction();
                _focusNode.requestFocus();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _game.resumeInput();
    } else {
      _game.clearInput();
    }
  }
}
