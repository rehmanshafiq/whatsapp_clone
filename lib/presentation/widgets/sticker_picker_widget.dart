import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/services/sticker_service.dart';
import '../../core/theme/app_theme.dart';

class StickerPickerWidget extends StatefulWidget {
  final ValueChanged<String> onStickerSelected;

  const StickerPickerWidget({super.key, required this.onStickerSelected});

  @override
  State<StickerPickerWidget> createState() => _StickerPickerWidgetState();
}

class _StickerPickerWidgetState extends State<StickerPickerWidget> {
  final StickerService _stickerService = StickerService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<String> _stickers = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String _currentQuery = '';
  int _offset = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _fetchStickers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchStickers(loadMore: true);
    }
  }

  Future<void> _fetchStickers({bool loadMore = false}) async {
    if (_isLoading || (!loadMore && !_hasMore)) return;

    setState(() {
      _isLoading = true;
      if (!loadMore) {
        _offset = 0;
        _stickers.clear();
        _hasMore = true;
      }
    });

    try {
      final newStickers = _currentQuery.isEmpty
          ? await _stickerService.getTrendingStickers(offset: _offset, limit: _limit)
          : await _stickerService.searchStickers(_currentQuery, offset: _offset, limit: _limit);

      if (mounted) {
        setState(() {
          if (newStickers.isEmpty) {
            _hasMore = false;
          } else {
            _stickers.addAll(newStickers);
            _offset += newStickers.length;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_currentQuery == query) return;
    _currentQuery = query;
    _fetchStickers();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.inputBar,
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search stickers',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppColors.iconMuted, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        // Grid View
        Expanded(
          child: _stickers.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // Stickers are usually smaller, 3 per row
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _stickers.length + (_hasMore && _isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _stickers.length) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      );
                    }
                    return GestureDetector(
                      onTap: () => widget.onStickerSelected(_stickers[index]),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: CachedNetworkImage(
                          imageUrl: _stickers[index],
                          fit: BoxFit.contain,
                          placeholder: (context, url) => Container(
                            color: Colors.transparent,
                          ),
                          errorWidget: (context, url, error) => const Icon(Icons.error, color: AppColors.iconMuted),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
