import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repository/chat_repository.dart';
import 'contact_state.dart';

class ContactCubit extends Cubit<ContactState> {
  final ChatRepository _repository;

  ContactCubit(this._repository) : super(const ContactState());

  Future<void> loadContacts() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final contacts = await _repository.getContacts();
      emit(state.copyWith(contacts: contacts, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  void updateSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }
}
