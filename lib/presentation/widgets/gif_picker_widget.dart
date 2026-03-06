import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/services/gif_service.dart';
import '../../core/theme/app_theme.dart';

class GifPickerWidget extends StatefulWidget {
  final ValueChanged<String> onGifSelected;

  const GifPickerWidget({super.key, required this.onGifSelected});

  @override
  State<GifPickerWidget> createState() => _GifPickerWidgetState();
}

class _GifPickerWidgetState extends State<GifPickerWidget> {
  final GifService _gifService = GifService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<String> _gifs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String _currentQuery = '';
  int _offset = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _fetchGifs();
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
      _fetchGifs(loadMore: true);
    }
  }

  Future<void> _fetchGifs({bool loadMore = false}) async {
    if (_isLoading || (!loadMore && !_hasMore)) return;

    setState(() {
      _isLoading = true;
      if (!loadMore) {
        _offset = 0;
        _gifs.clear();
        _hasMore = true;
      }
    });

    try {
      final newGifs = _currentQuery.isEmpty
          ? await _gifService.getTrendingGifs(offset: _offset, limit: _limit)
          : await _gifService.searchGifs(_currentQuery, offset: _offset, limit: _limit);

      if (mounted) {
        setState(() {
          if (newGifs.isEmpty) {
            _hasMore = false;
          } else {
            _gifs.addAll(newGifs);
            _offset += newGifs.length;
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
    _fetchGifs();
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
                hintText: 'Search Tenor', // Similar to WhatsApp placeholder
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
          child: _gifs.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _gifs.length + (_hasMore && _isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _gifs.length) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      );
                    }
                    return GestureDetector(
                      onTap: () => widget.onGifSelected(_gifs[index]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: _gifs[index],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: AppColors.chatBackground,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.chatBackground,
                            child: const Icon(Icons.error, color: AppColors.iconMuted),
                          ),
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
