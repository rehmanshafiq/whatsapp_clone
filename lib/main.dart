import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_storage/get_storage.dart';

import 'core/di/service_locator.dart';
import 'core/root_scaffold_messenger.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repository/auth_repository.dart';
import 'data/repository/chat_repository.dart';
import 'data/services/webrtc_call_manager.dart';
import 'presentation/cubit/chat_cubit.dart';
import 'presentation/widgets/active_call_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await GetStorage.init();
  setupLocator();
  // Subscribe to call/WebRTC socket events before UI builds (lazy singleton).
  getIt<WebRtcCallManager>();
  await getIt<AuthRepository>().initializeSession();
  runApp(const WhatsAppClone());
}

class WhatsAppClone extends StatefulWidget {
  const WhatsAppClone({super.key});

  @override
  State<WhatsAppClone> createState() => _WhatsAppCloneState();
}

class _WhatsAppCloneState extends State<WhatsAppClone>
    with WidgetsBindingObserver {
  late final AuthRepository _authRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authRepository = getIt<AuthRepository>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _authRepository.validateOrLogoutExpiredSession();
      // Android/iOS commonly drop the WebSocket while the app is backgrounded.
      // Without this, an authenticated user who resumes the app has no live
      // socket and cannot receive `incoming_call`, so the peer's phone never
      // rings. Reconnect eagerly on resume.
      if (_authRepository.isAuthenticated) {
        getIt<ChatRepository>().ensureRealtimeSocketConnected();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ChatCubit>(),
      child: MaterialApp.router(
        title: 'WhatsApp Clone',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        theme: AppTheme.dark,
        routerConfig: AppRouter.create(_authRepository),
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              ListenableBuilder(
                listenable: getIt<WebRtcCallManager>(),
                builder: (context, _) {
                  final manager = getIt<WebRtcCallManager>();
                  if (!manager.hasActiveCall) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: ActiveCallOverlay(manager: manager),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
