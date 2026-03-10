import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../cubit/chat_cubit.dart';

class LocationShareScreen extends StatefulWidget {
  final String channelId;

  const LocationShareScreen({super.key, required this.channelId});

  @override
  State<LocationShareScreen> createState() => _LocationShareScreenState();
}

class _LocationShareScreenState extends State<LocationShareScreen> {
  static const _defaultCamera = CameraPosition(
    target: LatLng(23.8103, 90.4125),
    zoom: 12,
  );

  GoogleMapController? _mapController;
  Position? _currentPosition;
  Placemark? _currentPlacemark;
  String? _currentAddress;
  List<_NearbyPlace> _nearbyPlaces = const [];
  Set<Marker> _markers = const {};
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorText;
  bool _isPermissionDeniedForever = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorText = null;
        _isPermissionDeniedForever = false;
      });
    }

    final position = await _getCurrentLocation();
    if (!mounted || position == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    Placemark? placemark;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        placemark = placemarks.first;
      }
    } catch (_) {}

    final address = await _getAddressFromLatLng(
      LatLng(position.latitude, position.longitude),
    );
    final nearbyPlaces = _buildNearbyPlaces(position, address, placemark);

    if (!mounted) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentPosition = position;
      _currentPlacemark = placemark;
      _currentAddress = address;
      _nearbyPlaces = nearbyPlaces;
      _markers = {
        Marker(
          markerId: const MarkerId('current_location'),
          position: currentLatLng,
          infoWindow: InfoWindow(title: 'Current location', snippet: address),
        ),
      };
      _isLoading = false;
    });

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: currentLatLng, zoom: 16),
      ),
    );
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _errorText = 'Turn on location services to share your location.';
          });
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _errorText = 'Location permission is required to continue.';
          });
        }
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isPermissionDeniedForever = true;
            _errorText =
                'Location permission is permanently denied. Enable it from app settings.';
          });
        }
        return null;
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Unable to fetch your current location right now.';
        });
      }
      return null;
    }
  }

  Future<String> _getAddressFromLatLng(LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isEmpty) {
        return _formatCoordinates(latLng.latitude, latLng.longitude);
      }

      final placemark = placemarks.first;
      final parts =
          [
                placemark.street,
                placemark.subLocality,
                placemark.locality,
                placemark.administrativeArea,
              ]
              .whereType<String>()
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toSet()
              .toList();

      return parts.isEmpty
          ? _formatCoordinates(latLng.latitude, latLng.longitude)
          : parts.join(', ');
    } catch (_) {
      return _formatCoordinates(latLng.latitude, latLng.longitude);
    }
  }

  Future<void> _sendLocationMessage(_NearbyPlace place) async {
    if (_isSending) return;

    setState(() => _isSending = true);
    try {
      await context.read<ChatCubit>().sendLocationMessage(
        widget.channelId,
        latitude: place.latitude,
        longitude: place.longitude,
        locationName: place.name,
        locationAddress: place.address,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startLiveLocationSharing(Duration duration) async {
    final position = _currentPosition;
    if (position == null || _isSending) return;

    setState(() => _isSending = true);
    try {
      final locationName = _currentPlacemark?.name?.trim().isNotEmpty == true
          ? _currentPlacemark!.name!.trim()
          : 'Live location';
      final locationAddress =
          _currentAddress ??
          _formatCoordinates(position.latitude, position.longitude);

      await context.read<ChatCubit>().startLiveLocationSharing(
        widget.channelId,
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: locationName,
        locationAddress: locationAddress,
        duration: duration,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showLiveLocationDurationSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final options = <({String label, Duration duration})>[
          (label: '15 minutes', duration: const Duration(minutes: 15)),
          (label: '1 hour', duration: const Duration(hours: 1)),
          (label: '8 hours', duration: const Duration(hours: 8)),
        ];

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share live location for',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your location will keep updating in this chat until the selected time ends.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map(
                  (option) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1F25D366),
                      child: Icon(
                        Icons.timer_outlined,
                        color: AppColors.accent,
                      ),
                    ),
                    title: Text(
                      option.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Share your real-time location',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startLiveLocationSharing(option.duration);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_NearbyPlace> _buildNearbyPlaces(
    Position position,
    String address,
    Placemark? placemark,
  ) {
    final primary =
        _firstNonEmpty([
          placemark?.name,
          placemark?.street,
          placemark?.subLocality,
          placemark?.locality,
        ]) ??
        'Current address';
    final secondary =
        _firstNonEmpty([
          placemark?.subLocality,
          placemark?.locality,
          placemark?.administrativeArea,
        ]) ??
        'Nearby area';
    final city =
        _firstNonEmpty([placemark?.locality, placemark?.administrativeArea]) ??
        'City center';

    return [
      _NearbyPlace(
        name: primary,
        address: address,
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      _NearbyPlace(
        name: '$secondary Landmark',
        address: 'Near $primary',
        latitude: position.latitude + 0.0012,
        longitude: position.longitude - 0.0011,
      ),
      _NearbyPlace(
        name: '$city Business Hub',
        address: '$secondary area',
        latitude: position.latitude - 0.0016,
        longitude: position.longitude + 0.0014,
      ),
      _NearbyPlace(
        name: '$city Cafe',
        address: 'Popular spot around $secondary',
        latitude: position.latitude + 0.0022,
        longitude: position.longitude + 0.0010,
      ),
    ];
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final currentPosition = _currentPosition;
    final currentAddress =
        _currentAddress ??
        (currentPosition == null
            ? 'Fetching current location...'
            : _formatCoordinates(
                currentPosition.latitude,
                currentPosition.longitude,
              ));

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        backgroundColor: AppColors.appBar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Send location',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _defaultCamera,
                  myLocationEnabled: currentPosition != null,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  buildingsEnabled: true,
                  markers: _markers,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_currentPosition != null) {
                      controller.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          16,
                        ),
                      );
                    }
                  },
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.22),
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.chatBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_errorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.incomingBubble,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _errorText!,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton(
                                onPressed: _initializeLocation,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.divider,
                                  ),
                                  foregroundColor: AppColors.textPrimary,
                                ),
                                child: const Text('Try again'),
                              ),
                              if (_isPermissionDeniedForever)
                                FilledButton(
                                  onPressed: Geolocator.openAppSettings,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Open settings'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _LocationOptionTile(
                    icon: Icons.send_rounded,
                    title: 'Send your current location',
                    subtitle: currentAddress,
                    enabled: currentPosition != null && !_isSending,
                    onTap: currentPosition == null
                        ? null
                        : () => _sendLocationMessage(
                            _NearbyPlace(
                              name:
                                  _firstNonEmpty([
                                    _currentPlacemark?.name,
                                    _currentPlacemark?.street,
                                    'Current location',
                                  ]) ??
                                  'Current location',
                              address: currentAddress,
                              latitude: currentPosition.latitude,
                              longitude: currentPosition.longitude,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  _LocationOptionTile(
                    icon: Icons.my_location_rounded,
                    title: 'Share live location',
                    subtitle: 'Share your real-time location for a duration',
                    enabled: currentPosition != null && !_isSending,
                    onTap: currentPosition == null
                        ? null
                        : _showLiveLocationDurationSheet,
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Nearby places',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._nearbyPlaces.map(
                    (place) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0x1625D366),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.accent,
                        ),
                      ),
                      title: Text(
                        place.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        place.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      onTap: _isSending
                          ? null
                          : () => _sendLocationMessage(place),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  const _LocationOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.incomingBubble,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0x1625D366),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            color: enabled ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.3),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _NearbyPlace {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const _NearbyPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}
