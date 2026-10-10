import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/game_repository.dart';
import 'data/storage/prefs_storage.dart';
import 'state/game_controller.dart';
import 'ui/game_scope.dart';
import 'ui/shell/home_shell.dart';
import 'ui/widgets/starfield.dart';

class StarwardApp extends StatelessWidget {
  const StarwardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starward 星际漫游',
      debugShowCheckedModeBanner: false,
      theme: buildStarwardTheme(),
      home: const _Boot(),
    );
  }
}

/// Loads the save (async, via SharedPreferences) behind an ambient starfield
/// splash, then hands control to the shell. The galaxy is never blank: the
/// splash itself is already part of the atmosphere.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  GameController? _controller;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final storage = await PrefsStorage.create();
    final controller = GameController(repository: GameRepository(storage));
    await controller.init();
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            StarfieldBackground(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'STARWARD',
                    style: TextStyle(
                      color: StarColors.offWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 8,
                    ),
                  ),
                  SizedBox(height: 18),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StarColors.cyan,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GameScope(
      controller: controller,
      child: const HomeShell(),
    );
  }
}
