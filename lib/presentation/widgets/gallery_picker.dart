import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../core/theme/app_theme.dart';

class GalleryPickerSheet extends StatefulWidget {
  final Function(AssetEntity) onAssetSelected;

  const GalleryPickerSheet({super.key, required this.onAssetSelected});

  @override
  State<GalleryPickerSheet> createState() => _GalleryPickerSheetState();
}

class _GalleryPickerSheetState extends State<GalleryPickerSheet> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );
    if (albums.isNotEmpty && mounted) {
      setState(() {
        _albums = albums;
        _selectedAlbum = albums.first;
      });
      await _loadAssets(_selectedAlbum!);
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAssets(AssetPathEntity album) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final assets = await album.getAssetListPaged(page: 0, size: 100);
    if (mounted) {
      setState(() {
        _assets = assets;
        _isLoading = false;
      });
    }
  }

  void _showAlbumPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return ListView.builder(
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final album = _albums[index];
            return ListTile(
              leading: FutureBuilder<List<AssetEntity>>(
                future: album.getAssetListPaged(page: 0, size: 1),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return SizedBox(
                      width: 50,
                      height: 50,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: AssetEntityImage(
                          snapshot.data!.first,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(100),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  }
                  return Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.photo_album, color: Colors.white54),
                  );
                },
              ),
              title: Text(album.name, style: const TextStyle(color: Colors.white)),
              subtitle: FutureBuilder<int>(
                future: album.assetCountAsync,
                builder: (context, snapshot) {
                  return Text(
                    snapshot.hasData ? '${snapshot.data}' : '',
                    style: const TextStyle(color: Colors.white70),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                if (_selectedAlbum != album) {
                  setState(() => _selectedAlbum = album);
                  _loadAssets(album);
                }
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_albums.isNotEmpty) _showAlbumPicker();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _selectedAlbum?.name ?? 'Recent',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 48), // Spacer
              ],
            ),
          ),
          // Grid View
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.accent))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      return GestureDetector(
                        onTap: () => widget.onAssetSelected(asset),
                        child: AssetEntityImage(
                          asset,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(200),
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
