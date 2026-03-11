import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_storage/get_storage.dart';

import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'presentation/cubit/chat_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await GetStorage.init();
  setupLocator();

  final box = GetStorage();
  final token = box.read<String>(AppConstants.storageTokenKey);
  final userId = box.read<String>(AppConstants.storageUserIdKey);
  final isAuthenticated = token != null && userId != null;

  runApp(WhatsAppClone(isAuthenticated: isAuthenticated));
}

class WhatsAppClone extends StatelessWidget {
  const WhatsAppClone({super.key, required this.isAuthenticated});

  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ChatCubit>()..loadChats(),
      child: MaterialApp.router(
        title: 'WhatsApp Clone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: AppRouter.create(isAuthenticated),
      ),
    );
  }
}
