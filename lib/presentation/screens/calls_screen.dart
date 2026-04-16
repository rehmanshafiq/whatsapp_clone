import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/call_log.dart';
import '../../data/repository/auth_repository.dart';
import '../../data/repository/chat_repository.dart';
import '../widgets/chat_avatar.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final _searchController = TextEditingController();
  List<CallLog> _calls = const [];
  bool _loading = true;
  String? _errorMessage;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await getIt<AuthRepository>().validateOrLogoutExpiredSession();
    if (!mounted) return;
    if (!getIt<AuthRepository>().isAuthenticated) {
      context.goNamed(AppRouter.auth);
      return;
    }
    await _loadCalls();
  }

  Future<void> _loadCalls() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final list = await getIt<ChatRepository>().fetchCallHistory();
      if (!mounted) return;
      setState(() {
        _calls = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final hadData = _calls.isNotEmpty;
      setState(() {
        _errorMessage = hadData ? null : e.message;
        _loading = false;
      });
      if (hadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final hadData = _calls.isNotEmpty;
      setState(() {
        _errorMessage = hadData ? null : e.toString();
        _loading = false;
      });
      if (hadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  List<CallLog> get _filteredCalls {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _calls;
    return _calls
        .where((c) => c.peerDisplayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
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
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _calls.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_errorMessage != null && _calls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadCalls,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filteredCalls;
    if (items.isEmpty) {
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
              _query.trim().isEmpty ? 'No call logs yet' : 'No matching calls',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_query.trim().isEmpty) ...[
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
      onRefresh: _loadCalls,
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
