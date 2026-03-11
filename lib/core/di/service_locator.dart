import 'package:get_it/get_it.dart';
import 'package:get_storage/get_storage.dart';

import '../../data/local/audio_playback_service.dart';
import '../../data/local/storage_service.dart';
import '../../data/repository/auth_remote_data_source.dart';
import '../../data/repository/auth_repository.dart';
import '../../data/repository/chat_remote_data_source.dart';
import '../../data/repository/chat_repository.dart';
import '../../data/services/web_socket_service.dart';
import '../../presentation/cubit/chat_cubit.dart';
import '../../presentation/cubit/contact_cubit.dart';
import '../../presentation/cubit/auth_cubit.dart';
import '../network/dio_api_client.dart';

final getIt = GetIt.instance;

void setupLocator() {
  // Auth / real backend client
  getIt.registerLazySingleton<DioApiClient>(() => DioApiClient());
  getIt.registerLazySingleton<StorageService>(
    () => StorageService(GetStorage()),
  );
  getIt.registerLazySingleton<WebSocketService>(() => WebSocketService());
  getIt.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(getIt<DioApiClient>().dio),
  );
  getIt.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSource(getIt<DioApiClient>().dio),
  );
  getIt.registerLazySingleton<ChatRepository>(
    () => ChatRepository(
      getIt<ChatRemoteDataSource>(),
      getIt<StorageService>(),
      getIt<WebSocketService>(),
    ),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      getIt<AuthRemoteDataSource>(),
      getIt<StorageService>(),
      getIt<WebSocketService>(),
    ),
  );
  getIt.registerLazySingleton<AudioPlaybackService>(
    () => AudioPlaybackService(),
  );
  getIt.registerFactory<ChatCubit>(() => ChatCubit(getIt<ChatRepository>()));
  getIt.registerFactory<ContactCubit>(
    () => ContactCubit(getIt<ChatRepository>()),
  );
  getIt.registerFactory<AuthCubit>(() => AuthCubit(getIt<AuthRepository>()));
}
