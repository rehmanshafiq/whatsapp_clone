part of 'select_contact_bloc.dart';

sealed class SelectContactEvent extends Equatable {
  const SelectContactEvent();

  @override
  List<Object?> get props => [];
}

final class SearchQueryChanged extends SelectContactEvent {
  const SearchQueryChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}

final class PerformSearch extends SelectContactEvent {
  const PerformSearch();
}

final class ToggleSelection extends SelectContactEvent {
  const ToggleSelection(this.user);
  final UserSearchResult user;

  @override
  List<Object?> get props => [user];
}

final class ClearSelection extends SelectContactEvent {
  const ClearSelection();
}

final class CreateGroupPressed extends SelectContactEvent {
  const CreateGroupPressed({this.groupName = 'New Group'});
  final String groupName;

  @override
  List<Object?> get props => [groupName];
}

final class StartOneToOneChat extends SelectContactEvent {
  const StartOneToOneChat(this.user);
  final UserSearchResult user;

  @override
  List<Object?> get props => [user];
}

/// Dispatched after the UI has consumed a navigation event.
final class NavigationConsumed extends SelectContactEvent {
  const NavigationConsumed();
}
