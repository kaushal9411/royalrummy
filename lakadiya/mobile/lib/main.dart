import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/router/app_router.dart';
import 'core/services/api_service.dart';
import 'core/services/socket_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/game/presentation/bloc/game_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  ApiService().init();
  SocketService().connect();
  runApp(const LakadiyaApp());
}

class LakadiyaApp extends StatefulWidget {
  const LakadiyaApp({super.key});

  @override
  State<LakadiyaApp> createState() => _LakadiyaAppState();
}

class _LakadiyaAppState extends State<LakadiyaApp> {
  late final AuthBloc _authBloc;
  late final GameBloc _gameBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc(repo: AuthRepository())
      ..add(AuthCheckRequested());
    _gameBloc = GameBloc();
  }

  @override
  void dispose() {
    _authBloc.close();
    _gameBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _gameBloc),
      ],
      child: _AppView(authBloc: _authBloc),
    );
  }
}

class _AppView extends StatefulWidget {
  final AuthBloc authBloc;
  const _AppView({required this.authBloc});

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  late final router = createRouter(widget.authBloc);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      bloc: widget.authBloc,
      buildWhen: (_, s) => s is AuthAuthenticated || s is AuthUnauthenticated,
      builder: (_, __) => MaterialApp.router(
        title:            'Lakadiya',
        debugShowCheckedModeBanner: false,
        theme:            AppTheme.light,
        darkTheme:        AppTheme.dark,
        themeMode:        ThemeMode.dark,
        routerConfig:     router,
      ),
    );
  }
}
