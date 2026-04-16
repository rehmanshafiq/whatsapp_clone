import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/call_log.dart';
import '../../data/repository/auth_repository.dart';
import '../../data/repository/chat_repository.dart';
import '../bloc/calls/calls_bloc.dart';
import '../bloc/calls/calls_event.dart';
import '../bloc/calls/calls_state.dart';
import '../widgets/chat_avatar.dart';

/// Call history tab. Uses [CallsBloc] for list, loading, errors, and search query.
///
/// A minimal [StatefulWidget] is only used for post-frame auth bootstrap; UI
/// state is held in the bloc.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await getIt<AuthRepository>().validateOrLogoutExpiredSession();
    if (!mounted) return;
    if (!getIt<AuthRepository>().isAuthenticated) {
      context.goNamed(AppRouter.auth);
      return;
    }
    context.read<CallsBloc>().add(const CallsLoadRequested());
  }

  Future<void> _onRefresh(BuildContext context) async {
    context.read<CallsBloc>().add(const CallsLoadRequested());
    await context.read<CallsBloc>().stream.firstWhere((s) => !s.isLoading);
    if (!context.mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CallsBloc, CallsState>(
      listenWhen: (previous, current) =>
          current.refreshErrorMessage != null &&
          current.refreshErrorMessage != previous.refreshErrorMessage,
      listener: (context, state) {
        final message = state.refreshErrorMessage;
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          context.read<CallsBloc>().add(const CallsRefreshErrorConsumed());
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Calls',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (value) => context
                      .read<CallsBloc>()
                      .add(CallsSearchQueryChanged(value)),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.searchBar,
                    hintText: 'Search calls...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.iconMuted,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: BlocBuilder<CallsBloc, CallsState>(
                  builder: (context, state) {
                    return _CallsBody(
                      state: state,
                      onRetry: () => context
                          .read<CallsBloc>()
                          .add(const CallsLoadRequested()),
                      onRefresh: () => _onRefresh(context),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallsBody extends StatelessWidget {
  const _CallsBody({
    required this.state,
    required this.onRetry,
    required this.onRefresh,
  });

  final CallsState state;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.showInitialLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (state.errorMessage != null && state.calls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final items = state.filteredCalls;
    if (items.isEmpty) {
      final q = state.searchQuery.trim();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_outlined,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              q.isEmpty ? 'No call logs yet' : 'No matching calls',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (q.isEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Voice and video calls you make or receive will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final userId = getIt<ChatRepository>().getCurrentUserId();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.appBar,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(
          color: AppColors.divider,
          height: 1,
          indent: 76,
        ),
        itemBuilder: (context, index) {
          final log = items[index];
          return _CallHistoryTile(log: log, currentUserId: userId);
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({
    required this.log,
    required this.currentUserId,
  });

  final CallLog log;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final outgoing =
        currentUserId != null && log.callerId == currentUserId;
    final alert = _isAlertStatus(log.status);
    final subColor =
        alert ? const Color(0xFFE53935) : AppColors.textSecondary;
    final statusIcon = _statusIcon(log, outgoing);
    final subtitleText =
        '${_statusLabel(log.status)}${_durationPart(log)} • ${_formatCallTimestamp(log.startedAt)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ChatAvatar(
        imageUrl: log.peerAvatarUrl.isEmpty ? null : log.peerAvatarUrl,
        name: log.peerDisplayName,
        radius: 28,
      ),
      title: Text(
        log.peerDisplayName,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(statusIcon, size: 16, color: subColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subColor, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      trailing: Icon(
        log.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
        color: AppColors.seenTick,
        size: 26,
      ),
    );
  }
}

bool _isAlertStatus(String status) {
  switch (status.toLowerCase()) {
    case 'missed':
    case 'rejected':
    case 'busy':
    case 'cancelled':
      return true;
    default:
      return false;
  }
}

IconData _statusIcon(CallLog log, bool outgoing) {
  switch (log.status.toLowerCase()) {
    case 'missed':
      return Icons.call_missed;
    case 'rejected':
    case 'busy':
      return Icons.phone_disabled;
    case 'cancelled':
      return Icons.call_made;
    case 'completed':
      return outgoing ? Icons.call_made : Icons.call_received;
    default:
      return Icons.phone_callback;
  }
}

String _statusLabel(String status) {
  final s = status.trim();
  if (s.isEmpty) return 'Unknown';
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

String _durationPart(CallLog log) {
  if (log.status.toLowerCase() != 'completed' || log.duration <= 0) {
    return '';
  }
  return ' • ${_formatDurationSeconds(log.duration)}';
}

String _formatDurationSeconds(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _formatCallTimestamp(DateTime local) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String fmtTime(DateTime d) {
    final h24 = d.hour;
    final m = d.minute;
    final isPm = h24 >= 12;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

  if (day == today) {
    return fmtTime(local);
  }
  if (local.year == now.year) {
    return '${months[local.month - 1]} ${local.day}, ${fmtTime(local)}';
  }
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}, ${fmtTime(local)}';
}
