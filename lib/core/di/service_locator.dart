import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:get_storage/get_storage.dart';

import '../../data/local/storage_service.dart';
import '../../data/repository/chat_remote_data_source.dart';
import '../../data/repository/chat_repository.dart';
import '../../presentation/cubit/chat_cubit.dart';
import '../../presentation/cubit/contact_cubit.dart';
import '../network/api_client.dart';

final getIt = GetIt.instance;

void setupLocator() {
  getIt.registerLazySingleton<Dio>(() => Dio());
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));
  getIt.registerLazySingleton<StorageService>(() => StorageService(GetStorage()));
  getIt.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ChatRepository>(
    () => ChatRepository(getIt<ChatRemoteDataSource>(), getIt<StorageService>()),
  );
  getIt.registerFactory<ChatCubit>(() => ChatCubit(getIt<ChatRepository>()));
  getIt.registerFactory<ContactCubit>(() => ContactCubit(getIt<ChatRepository>()));
}
