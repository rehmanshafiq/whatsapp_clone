import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';

import '../../core/theme/app_theme.dart';
import 'media_preview_screen.dart';
import '../widgets/gallery_picker.dart';

class CameraScreen extends StatefulWidget {
  final String channelId;
  const CameraScreen({super.key, required this.channelId});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  bool _hasPermissionError = false;
  bool _isAudioEnabled = true;
  bool _hasCameraPermission = false;
  bool _isInitializingCamera = false;

  List<AssetEntity> _recentMedia = [];
  bool _isLoadingMedia = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initScanner();
  }

  Future<void> _initScanner() async {
    try {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      if (!mounted) return;

      if (!cameraStatus.isGranted) {
        setState(() => _hasPermissionError = true);
        return;
      }

      _hasCameraPermission = true;
      _isAudioEnabled = micStatus.isGranted;

      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        await _initCamera(_cameras[_selectedCameraIndex]);
        // Request gallery permission after camera is ready to avoid first-install
        // permission-dialog races that can stall camera initialization.
        unawaited(_fetchRecentMedia());
      } else {
        if (mounted) setState(() => _hasPermissionError = true);
      }
    } catch (e) {
      debugPrint('Error init camera: $e');
      if (mounted) setState(() => _hasPermissionError = true);
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;

    final prevController = _controller;
    _controller = null;

    if (mounted) {
      setState(() => _isCameraInitialized = false);
    } else {
      _isCameraInitialized = false;
    }

    // Must dispose of the old camera before initializing the new one,
    // otherwise hardware locks prevent the new camera from starting.
    if (prevController != null) {
      await prevController.dispose();
    }

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: _isAudioEnabled,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.jpeg,
    );

    _controller = newController;

    try {
      await newController.initialize().timeout(const Duration(seconds: 15));
      await newController.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _hasPermissionError = false;
        });
      }
    } on TimeoutException catch (e) {
      debugPrint('Camera init timeout: $e');
      await newController.dispose();
      if (identical(_controller, newController)) {
        _controller = null;
      }
      if (mounted) setState(() => _hasPermissionError = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
      await newController.dispose();
      if (identical(_controller, newController)) {
        _controller = null;
      }
      if (mounted) setState(() => _hasPermissionError = true);
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _fetchRecentMedia() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (albums.isNotEmpty) {
        List<AssetEntity> media = await albums[0].getAssetListPaged(
          page: 0,
          size: 30,
        );
        if (mounted) {
          setState(() {
            _recentMedia = media;
            _isLoadingMedia = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final controller = _controller;
      _controller = null;

      if (mounted) {
        setState(() => _isCameraInitialized = false);
      } else {
        _isCameraInitialized = false;
      }

      if (controller != null) {
        unawaited(controller.dispose());
      }
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _hasCameraPermission &&
        _cameras.isNotEmpty &&
        !_isInitializingCamera) {
      unawaited(_initCamera(_cameras[_selectedCameraIndex]));
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isRecording) {
      return;
    }
    try {
      final XFile picture = await _controller!.takePicture();
      _openPreviewScreen(picture.path, false);
    } catch (e) {
      debugPrint('Error capturing photo: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isRecording) {
      return;
    }
    try {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Error starting video: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        !_isRecording) {
      return;
    }
    try {
      final XFile video = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      _openPreviewScreen(video.path, true);
    } catch (e) {
      debugPrint('Error stopping video: $e');
    }
  }

  void _switchCamera() async {
    if (_cameras.isEmpty) return;

    // Briefly hide the CameraPreview widget so the old texture gets destroyed
    if (mounted) setState(() => _isCameraInitialized = false);

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_selectedCameraIndex]);
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final modes = [
      FlashMode.off,
      FlashMode.auto,
      FlashMode.always,
      FlashMode.torch,
    ];
    final currentIdx = modes.indexOf(_flashMode);
    final nextMode = modes[(currentIdx + 1) % modes.length];
    await _controller!.setFlashMode(nextMode);
    setState(() => _flashMode = nextMode);
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
    }
  }

  void _openPreviewScreen(String path, bool isVideo) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          channelId: widget.channelId,
          mediaPath: path,
          isVideo: isVideo,
        ),
      ),
    );
  }

  void _openGalleryMedia(AssetEntity asset) async {
    final file = await asset.file;
    if (file != null) {
      _openPreviewScreen(file.path, asset.type == AssetType.video);
    }
  }

  Future<void> _openFullGallery() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return GalleryPickerSheet(
            onAssetSelected: (asset) async {
              Navigator.pop(context);
              final file = await asset.file;
              if (file != null && mounted) {
                _openPreviewScreen(file.path, asset.type == AssetType.video);
              }
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPermissionError) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text(
            'Camera permission is required',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Live Camera Preview
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          // Top Bar Overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: Icon(_getFlashIcon(), color: Colors.white, size: 28),
                  onPressed: _toggleFlash,
                ),
              ],
            ),
          ),

          // Bottom Section
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gallery Strip
                if (!_isLoadingMedia && _recentMedia.isNotEmpty)
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentMedia.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final asset = _recentMedia[index];
                        return GestureDetector(
                          onTap: () => _openGalleryMedia(asset),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AssetEntityImage(
                                asset,
                                isOriginal: false,
                                thumbnailSize: const ThumbnailSize.square(150),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                // Camera Controls Layer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Last Photo Preview (acting as gallery button)
                      _recentMedia.isNotEmpty
                          ? GestureDetector(
                              onTap: _openFullGallery,
                              child: ClipOval(
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: AssetEntityImage(
                                    _recentMedia.first,
                                    isOriginal: false,
                                    thumbnailSize: const ThumbnailSize.square(
                                      150,
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(width: 44),

                      // Shutter button
                      GestureDetector(
                        onTap: () => _takePicture(),
                        onLongPress: () => _startVideoRecording(),
                        onLongPressUp: () => _stopVideoRecording(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isRecording ? 90 : 80,
                          height: _isRecording ? 90 : 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isRecording ? Colors.red : Colors.white,
                              width: _isRecording ? 6 : 4,
                            ),
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: _isRecording ? 30 : 66,
                              height: _isRecording ? 30 : 66,
                              decoration: BoxDecoration(
                                shape: _isRecording
                                    ? BoxShape.rectangle
                                    : BoxShape.circle,
                                borderRadius: _isRecording
                                    ? BorderRadius.circular(6)
                                    : null,
                                color: _isRecording ? Colors.red : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Camera switch
                      IconButton(
                        onPressed: _switchCamera,
                        icon: const Icon(
                          Icons.flip_camera_ios,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ),

                // Instructions Text
                const SizedBox(height: 16),
                const Text(
                  'Hold for video, tap for photo',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
