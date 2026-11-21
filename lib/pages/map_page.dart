import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';

import '../theme/app_theme.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Location _location = Location();
  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? _mapController;
  StreamSubscription<LocationData>? _locationSubscription;

  LatLng? _currentPosition;
  LatLng? _destination;

  bool _hasPermission = false;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isRouting = false;

  String? _errorMessage;
  String? _searchError;
  String? _routeError;
  String? _destinationName;

  double? _routeDistance;
  double? _routeDuration;
  // TURN-BY-TURN NAVIGATION
bool _isNavigating = false;

List<Map<String, dynamic>> _navigationSteps = [];

int _currentStepIndex = 0;

double? _distanceToNextTurn;

String _nextInstruction = 'Continue straight';

  List<Map<String, dynamic>> _searchResults = [];

  Set<Marker> _searchMarkers = {};
  Set<Polyline> _routePolylines = {};

  static const LatLng _kuwaitCenter = LatLng(29.3759, 47.9774);

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  // --------------------------------------------------
  // LOCATION INITIALIZATION
  // --------------------------------------------------

  Future<void> _initializeLocation() async {
    try {
      debugPrint('MAP GPS: Checking location service');
      bool serviceEnabled = await _location.serviceEnabled();

      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
      }
      debugPrint('MAP GPS: Location service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        throw Exception('Please enable your phone location service.');
      }

      PermissionStatus permission = await _location.hasPermission();

      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
      }

      if (permission != PermissionStatus.granted) {
        throw Exception(
          'Location permission is required to show your current position.',
        );
      }

      _hasPermission = true;
      debugPrint('MAP GPS: Setting location accuracy');
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000,
        distanceFilter: 10,
      );
      debugPrint('MAP GPS: Location settings configured');
      debugPrint('MAP GPS: Requesting current position');
      final locationData = await _location.getLocation();
      debugPrint(
        'MAP GPS: Received ${locationData.latitude}, ${locationData.longitude}',
      );

      _updatePosition(
        locationData.latitude,
        locationData.longitude,
        moveCamera: true,
      );

      await _locationSubscription?.cancel();

      _locationSubscription = _location.onLocationChanged.listen(
        (locationData) {
          _updatePosition(locationData.latitude, locationData.longitude);
        },
        onError: (error) {
          debugPrint('Map location error: $error');
        },
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _updatePosition(
  double? latitude,
  double? longitude, {
  bool moveCamera = false,
}) {
  if (latitude == null || longitude == null) return;

  final position = LatLng(latitude, longitude);

  if (!mounted) return;

  setState(() {
    _currentPosition = position;
  });

  // Update the next turn distance during navigation.
  _updateNavigation(position);

  if (_isNavigating) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: 18,
          tilt: 45,
        ),
      ),
    );
  } else if (moveCamera) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 16),
    );
  }
}

  // --------------------------------------------------
  // SEARCH PLACES AND STREETS
  // --------------------------------------------------

  Future<void> _searchPlaces(String query) async {
    final searchText = query.trim();

    if (searchText.isEmpty) {
      setState(() {
        _searchError = 'Please enter a street, area or place.';
        _searchResults = [];
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResults = [];
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': searchText,
        'format': 'jsonv2',
        'countrycodes': 'kw',
        'limit': '8',
        'addressdetails': '1',
      });

      final response = await http
          .get(
            uri,
            headers: {'Accept': 'application/json', 'Accept-Language': 'en'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Search service returned an error.');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception('Unexpected search response.');
      }

      final results = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (!mounted) return;

      setState(() {
        _searchResults = results;
        _searchError = results.isEmpty
            ? 'No places found. Try a different street name or area.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _searchResults = [];
        _searchError = 'Could not search right now. Check your internet connection and try again.';
      });

      debugPrint('Place search error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // SELECT DESTINATION
  // --------------------------------------------------

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final latitude = double.tryParse(result['lat']?.toString() ?? '');

    final longitude = double.tryParse(result['lon']?.toString() ?? '');

    if (latitude == null || longitude == null) return;

    final position = LatLng(latitude, longitude);

    final name = result['name']?.toString().trim();
    final displayName =
        result['display_name']?.toString() ?? 'Selected destination';

    final selectedName = name == null || name.isEmpty ? displayName : name;

    if (!mounted) return;

    setState(() {
      _destination = position;
      _destinationName = selectedName;

      _searchMarkers = {
        Marker(
          markerId: const MarkerId('searched_place'),
          position: position,
          infoWindow: InfoWindow(title: selectedName, snippet: displayName),
        ),
      };

      _searchController.text = selectedName;
      _searchResults = [];
      _searchError = null;

      _routePolylines = {};
      _routeDistance = null;
      _routeDuration = null;
      _routeError = null;
    });

    if (_currentPosition == null) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(position, 16),
      );

      if (mounted) {
        setState(() {
          _routeError = 'Your current location is not available. Try again when GPS is ready.';
        });
      }
      return;
    }

    await _getDrivingRoute();
  }

  // --------------------------------------------------
  // GET DRIVING ROUTE
  // --------------------------------------------------

  Future<void> _getDrivingRoute() async {
    final start = _currentPosition;
    final destination = _destination;

    if (start == null || destination == null) {
      setState(() {
        _routeError = 'Current location or destination is missing.';
      });
      return;
    }

    setState(() {
      _isRouting = true;
      _routeError = null;
      _routePolylines = {};
      _routeDistance = null;
      _routeDuration = null;
    });

    try {
      final coordinates =
          '${start.longitude},${start.latitude};'
          '${destination.longitude},${destination.latitude}';

      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$coordinates'
        '?overview=full&geometries=geojson&steps=true',
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('Routing service returned an error.');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> || decoded['code'] != 'Ok') {
        throw Exception('No driving route was found.');
      }

      final routes = decoded['routes'];

      if (routes is! List || routes.isEmpty) {
        throw Exception('No driving route was found.');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinatesList = geometry['coordinates'] as List;

      final routePoints = coordinatesList.map<LatLng>((coordinate) {
        return LatLng(
          (coordinate[1] as num).toDouble(),
          (coordinate[0] as num).toDouble(),
        );
      }).toList();

      if (routePoints.isEmpty) {
        throw Exception('The route could not be displayed.');
      }

      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();
      final legs = route['legs'] as List?;

if (legs == null || legs.isEmpty) {
  throw Exception('Driving instructions were not found.');
}

final firstLeg = legs.first as Map<String, dynamic>;
final rawSteps = firstLeg['steps'];

if (rawSteps is! List || rawSteps.isEmpty) {
  throw Exception('Driving instructions were not found.');
}

final navigationSteps = rawSteps
    .whereType<Map>()
    .map((step) => Map<String, dynamic>.from(step))
    .toList();

      if (!mounted) return;

      setState(() {
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('driving_route'),
            points: routePoints,
            color: AppTheme.olive,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };

        _routeDistance = distance;
        _routeDuration = duration;
        _navigationSteps = navigationSteps;
        _currentStepIndex = 0;
      });

      await _fitRouteOnMap(routePoints);
    } catch (error) {
      debugPrint('Driving route error: $error');

      if (!mounted) return;

      setState(() {
        _routeError =
            'Could not calculate the driving route. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRouting = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // FIT ROUTE INSIDE MAP
  // --------------------------------------------------

  Future<void> _fitRouteOnMap(List<LatLng> points) async {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    if (minLat == maxLat && minLng == maxLng) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 16),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  // --------------------------------------------------
  // CLEAR DESTINATION AND ROUTE
  // --------------------------------------------------

  void _clearRoute() {
    setState(() {
      _destination = null;
      _destinationName = null;
      _searchMarkers = {};
      _routePolylines = {};
      _routeDistance = null;
      _routeDuration = null;
      _routeError = null;
      _searchController.clear();
    });

    if (_currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPosition!, 16),
      );
    }
  }

  // --------------------------------------------------
  // FORMAT ROUTE INFORMATION
  // --------------------------------------------------
  double _distanceBetween(LatLng first, LatLng second) {
  const earthRadius = 6371000.0;

  final lat1 = first.latitude * math.pi / 180;
  final lat2 = second.latitude * math.pi / 180;

  final deltaLat = (second.latitude - first.latitude) * math.pi / 180;
  final deltaLng = (second.longitude - first.longitude) * math.pi / 180;

  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadius * c;
}
void _updateNavigation(LatLng position) {
  if (!_isNavigating || _navigationSteps.isEmpty) return;

  if (_currentStepIndex >= _navigationSteps.length) return;

  final step = _navigationSteps[_currentStepIndex];
  final maneuver = step['maneuver'] as Map<String, dynamic>?;

  if (maneuver == null) return;

  final rawLocation = maneuver['location'];

  if (rawLocation is! List || rawLocation.length < 2) return;

  final maneuverPoint = LatLng(
    (rawLocation[1] as num).toDouble(),
    (rawLocation[0] as num).toDouble(),
  );

  final distance = _distanceBetween(position, maneuverPoint);

  if (distance <= 35 &&
      _currentStepIndex < _navigationSteps.length - 1) {
    _currentStepIndex++;
    _updateNavigation(position);
    return;
  }

  if (!mounted) return;

  setState(() {
    _distanceToNextTurn = distance;
    _nextInstruction = _getInstruction(step);
  });
}
  String _getInstruction(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>?;

  if (maneuver == null) {
    return 'Continue straight';
  }

  final type = maneuver['type']?.toString() ?? '';
  final modifier = maneuver['modifier']?.toString() ?? '';

  switch (type) {
    case 'depart':
      return 'Start driving';

    case 'arrive':
      return 'You have arrived';

    case 'turn':
    case 'end of road':
      if (modifier.contains('left')) return 'Turn left';
      if (modifier.contains('right')) return 'Turn right';
      if (modifier == 'uturn') return 'Make a U-turn';
      return 'Continue straight';

    case 'new name':
    case 'continue':
      return 'Continue straight';

    case 'merge':
      return 'Merge onto the road';

    case 'fork':
      if (modifier.contains('left')) return 'Keep left at the fork';
      if (modifier.contains('right')) return 'Keep right at the fork';
      return 'Continue at the fork';

    case 'roundabout':
    case 'rotary':
      return 'Enter the roundabout';

    case 'on ramp':
      return 'Take the ramp';

    case 'off ramp':
      return 'Take the exit ramp';

    default:
      return 'Continue straight';
  }
}
  String _formatDistance(double? metres) {
    if (metres == null) return '';

    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }

    return '${metres.round()} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '';

    final minutes = (seconds / 60).ceil();

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $remainingMinutes min';
  }
  // --------------------------------------------------
// START AND END NAVIGATION
// --------------------------------------------------

Future<void> _startNavigation() async {
  if (_navigationSteps.isEmpty || _currentPosition == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please calculate a driving route first.'),
      ),
    );
    return;
  }

  setState(() {
    _isNavigating = true;
    _currentStepIndex =
        _navigationSteps.length > 1 ? 1 : 0;
    _nextInstruction =
        _getInstruction(_navigationSteps[_currentStepIndex]);
    _distanceToNextTurn = null;
  });

  _updateNavigation(_currentPosition!);

  await _mapController?.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: _currentPosition!,
        zoom: 18,
        tilt: 45,
      ),
    ),
  );
}

void _endNavigation() {
  setState(() {
    _isNavigating = false;
    _currentStepIndex = 0;
    _distanceToNextTurn = null;
    _nextInstruction = 'Continue straight';
  });

  if (_currentPosition != null) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentPosition!, 16),
    );
  }
}
  // --------------------------------------------------
  // CURRENT LOCATION BUTTON
  // --------------------------------------------------

  Future<void> _goToMyLocation() async {
    if (!_hasPermission) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await _initializeLocation();
      return;
    }

    try {
      final locationData = await _location.getLocation();

      final latitude = locationData.latitude;
      final longitude = locationData.longitude;

      _updatePosition(latitude, longitude, moveCamera: true);

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(latitude, longitude), zoom: 17),
        ),
      );
    } catch (error) {
      debugPrint('Could not get current location: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
    }
  }

  // --------------------------------------------------
  // DISPOSE
  // --------------------------------------------------

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // MAP PAGE UI
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition ?? _kuwaitCenter,
            zoom: _currentPosition == null ? 11 : 16,
          ),
          onMapCreated: (controller) {
            _mapController = controller;

            if (_currentPosition != null) {
              controller.animateCamera(
                CameraUpdate.newLatLngZoom(_currentPosition!, 16),
              );
            }
          },
          markers: _searchMarkers,
          polylines: _routePolylines,
          myLocationEnabled: _hasPermission,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
          trafficEnabled: true,
        ),

        // SEARCH BAR AND RESULTS
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      color: AppTheme.olive,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _searchPlaces,
                        decoration: const InputDecoration(
                          hintText: 'Search street, area or destination',
                          border: InputBorder.none,
                          hintStyle: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search places',
                      onPressed: _isSearching
                          ? null
                          : () => _searchPlaces(_searchController.text),
                      icon: _isSearching
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.olive,
                              ),
                            )
                          : const Icon(Icons.search, color: AppTheme.olive),
                    ),
                  ],
                ),
              ),

              // SEARCH RESULTS
              if (_searchResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];

                      final name = result['name']?.toString();
                      final address = result['display_name']?.toString() ?? '';

                      return ListTile(
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.olive,
                        ),
                        title: Text(
                          name == null || name.isEmpty ? address : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectSearchResult(result),
                      );
                    },
                  ),
                ),

              // SEARCH ERROR
              if (_searchError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    _searchError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),

        // LIVE NAVIGATION INSTRUCTION BANNER
if (_isNavigating)
  Positioned(
    top: 90,
    left: 16,
    right: 16,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.olive,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.turn_right,
            color: Colors.white,
            size: 36,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _nextInstruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _distanceToNextTurn == null
                      ? 'Calculating distance...'
                      : 'In ${_formatDistance(_distanceToNextTurn)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ), 
        // ROUTE INFORMATION
        if (_destination != null)
          Positioned(
            left: 16,
            right: 82,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppTheme.olive,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _destinationName ?? 'Selected destination',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Clear route',
                        onPressed: _clearRoute,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  if (_isRouting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.olive,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Calculating driving route...'),
                        ],
                      ),
                    )
                  else if (_routeError != null)
                    Text(
                      _routeError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    )
                  else if (_routeDistance != null &&
                      _routeDuration != null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car,
                          color: AppTheme.olive,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDistance(_routeDistance),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.access_time,
                          color: AppTheme.olive,
                          size: 19,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formatDuration(_routeDuration),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isNavigating
                            ? _endNavigation
                            : _startNavigation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isNavigating ? Colors.red : AppTheme.olive,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          _isNavigating
                              ? Icons.stop_circle_outlined
                              : Icons.navigation,
                        ),
                        label: Text(
                          _isNavigating
                              ? 'End Navigation'
                              : 'Start Navigation',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),


        // CURRENT LOCATION BUTTON
        Positioned(
          right: 16,
          bottom: _destination == null ? 24 : 105,
          child: FloatingActionButton(
            heroTag: 'map_current_location',
            onPressed: _goToMyLocation,
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.olive,
            elevation: 4,
            child: const Icon(Icons.my_location),
          ),
        ),

        // LOCATION LOADING INDICATOR
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: AppTheme.olive)),

        // LOCATION ERROR
        if (_errorMessage != null)
          Center(
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    color: AppTheme.olive,
                    size: 38,
                  ),
                  const SizedBox(height: 12),
                  Text(_errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _errorMessage = null;
                      });

                      _initializeLocation();
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
