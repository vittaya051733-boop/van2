import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import 'l10n/l10n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PickedLocation {
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
}

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.initialLocation,
  });

  final String title;
  final String confirmLabel;
  final PickedLocation? initialLocation;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const LatLng _bangkokCenter = LatLng(13.7563, 100.5018);

  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? _mapController;
  late LatLng _selectedPosition;
  late String _selectedLabel;
  String? _selectedSubtitle;
  bool _isSearching = false;
  bool _isLoadingLocation = false;
  bool _isResolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialLocation == null
        ? _bangkokCenter
        : LatLng(
            widget.initialLocation!.latitude,
            widget.initialLocation!.longitude,
          );
    _selectedLabel = widget.initialLocation?.title ?? L10n.selectedLocation;
    _selectedSubtitle = widget.initialLocation?.subtitle;

    if (widget.initialLocation == null) {
      unawaited(_getCurrentLocation());
    } else {
      unawaited(
        _resolveAddress(_selectedPosition, fallbackTitle: _selectedLabel),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final permissionGranted = await _ensureLocationPermission();
      if (!permissionGranted) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedPosition = target;
        _selectedLabel = L10n.currentLocation;
        _selectedSubtitle = null;
      });

      await _moveCamera(target);
      await _resolveAddress(target, fallbackTitle: L10n.currentLocation);
    } catch (error) {
      _showSnackBar(L10n.locationFetchFailed(error));
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar(L10n.enableLocationServices);
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar(L10n.grantLocationPermission);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(L10n.openLocationSettings);
      return false;
    }

    return true;
  }

  Future<void> _moveCamera(LatLng target) async {
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, 16),
    );
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Future<void> _searchByText(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);

    try {
      final locations = await locationFromAddress(trimmedQuery);
      if (locations.isEmpty) {
        _showSnackBar(L10n.locationNotFound);
        return;
      }

      final first = locations.first;
      final target = LatLng(first.latitude, first.longitude);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedPosition = target;
        _selectedLabel = trimmedQuery;
        _selectedSubtitle = null;
      });

      await _moveCamera(target);
      await _resolveAddress(target, fallbackTitle: trimmedQuery);
    } catch (error) {
      _showSnackBar(L10n.placeSearchFailed(error));
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _resolveAddress(
    LatLng position, {
    required String fallbackTitle,
  }) async {
    setState(() => _isResolvingAddress = true);

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted) {
        return;
      }

      if (placemarks.isEmpty) {
        setState(() {
          _selectedLabel = fallbackTitle;
          _selectedSubtitle = null;
        });
        return;
      }

      final place = placemarks.first;
      final titleParts = <String>[
        if ((place.name ?? '').trim().isNotEmpty) place.name!.trim(),
        if ((place.subLocality ?? '').trim().isNotEmpty)
          place.subLocality!.trim(),
      ];
      final subtitleParts = <String>[
        if ((place.locality ?? '').trim().isNotEmpty) place.locality!.trim(),
        if ((place.administrativeArea ?? '').trim().isNotEmpty)
          place.administrativeArea!.trim(),
        if ((place.country ?? '').trim().isNotEmpty) place.country!.trim(),
      ];

      setState(() {
        _selectedLabel = titleParts.isEmpty
            ? fallbackTitle
            : titleParts.join(', ');
        _selectedSubtitle = subtitleParts.isEmpty
            ? null
            : subtitleParts.join(', ');
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedLabel = fallbackTitle;
        _selectedSubtitle = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  Future<void> _handleMapPositionChanged(
    LatLng position, {
    required String fallbackTitle,
  }) async {
    setState(() {
      _selectedPosition = position;
      _selectedLabel = fallbackTitle;
      _selectedSubtitle = null;
    });
    await _resolveAddress(position, fallbackTitle: fallbackTitle);
  }

  PickedLocation _buildPickedLocation() {
    return PickedLocation(
      latitude: _selectedPosition.latitude,
      longitude: _selectedPosition.longitude,
      title: _selectedLabel,
      subtitle: _selectedSubtitle,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildMapCanvas() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _selectedPosition,
        zoom: 16,
      ),
      onMapCreated: _handleMapCreated,
      onTap: (position) {
        unawaited(
          _handleMapPositionChanged(
            position,
            fallbackTitle: L10n.selectedLocation,
          ),
        );
      },
      markers: <Marker>{
        Marker(
          markerId: const MarkerId('selected'),
          position: _selectedPosition,
          draggable: true,
          onDragEnd: (position) {
            unawaited(
              _handleMapPositionChanged(
                position,
                fallbackTitle: L10n.selectedLocation,
              ),
            );
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF9A3412),
        elevation: 0,
        title: Text(widget.title),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(_buildPickedLocation());
            },
            icon: const Icon(Icons.check_circle_outline),
            label: Text(L10n.confirm),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _searchByText,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: L10n.searchPlaceOrAddress,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            )),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                _buildMapCanvas(),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _selectedLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                          if (_selectedSubtitle != null) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              _selectedSubtitle!,
                              style: const TextStyle(color: Color(0xFF7C2D12)),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Lat ${_selectedPosition.latitude.toStringAsFixed(6)} • Lng ${_selectedPosition.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          if (_isResolvingAddress) ...<Widget>[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 2),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 96,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                    child: _isLoadingLocation
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.my_location,
                            color: Color(0xFFF57C00),
                          ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_buildPickedLocation());
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: Text(widget.confirmLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}
