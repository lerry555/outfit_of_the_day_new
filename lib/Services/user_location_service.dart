import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'hourly_weather_service.dart';
import 'reverse_geocode_service.dart';

typedef UserLocationListener = void Function(String cityLabel);

/// Zdieľaná poloha usera v celej appke (Home, Stylist chat…).
/// Počasie a outfit idú podľa GPS. Martin len ak GPS zlyhá / je zamietnuté.
class UserLocationService {
  UserLocationService._();

  static final UserLocationService instance = UserLocationService._();

  String _cityLabel = HourlyWeatherService.defaultWeatherCityShortLabel;
  double? _latitude;
  double? _longitude;
  bool _resolveAttempted = false;
  bool _permissionDenied = false;
  Future<void>? _resolveInFlight;
  final List<UserLocationListener> _listeners = <UserLocationListener>[];

  /// Mesto pre UI a weather API (napr. „London“, „Žilina“ alebo „London, United Kingdom“).
  String get cityLabel => _cityLabel.isNotEmpty
      ? _cityLabel
      : HourlyWeatherService.defaultWeatherCityShortLabel;

  String get cityShortLabel {
    final label = cityLabel;
    final comma = label.indexOf(',');
    if (comma <= 0) return label.trim();
    return label.substring(0, comma).trim();
  }

  double? get latitude => _latitude;
  double? get longitude => _longitude;
  bool get hasGpsFix => _latitude != null && _longitude != null;
  bool get isReadyForWeather => _resolveAttempted;
  bool get permissionDenied => _permissionDenied;

  void addListener(UserLocationListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(UserLocationListener listener) {
    _listeners.remove(listener);
  }

  /// Spustí GPS + reverse geocode (raz). Opakované volania čakajú na ten istý future.
  Future<void> ensureResolved() {
    final inFlight = _resolveInFlight;
    if (inFlight != null) return inFlight;
    final future = _resolveImpl();
    _resolveInFlight = future;
    future.whenComplete(() => _resolveInFlight = null);
    return future;
  }

  Future<void> _resolveImpl() async {
    final previousCity = _cityLabel;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _permissionDenied = true;
        if (_cityLabel.isEmpty) {
          _cityLabel = HourlyWeatherService.defaultWeatherCityShortLabel;
        }
        debugPrint('[USER_LOCATION] permission_denied fallback=${_cityLabel}');
        _resolveAttempted = true;
        _notifyIfCityChanged(previousCity);
        return;
      }
      // Prefer the cached fix. Besides being faster for Home/Stylist startup,
      // this avoids repeatedly registering a GNSS/NMEA listener merely to
      // refresh weather. Some Android emulator images can block the platform
      // main thread while that listener is synchronously unregistered.
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        // Startup weather resolution is best-effort. Do not start an active
        // GNSS session from this shared Home/Stylist service: on affected
        // Android builds the platform blocks while unregistering its NMEA
        // callback and makes the whole Flutter activity ANR. Flows that
        // explicitly require live location still own that request themselves.
        debugPrint(
          '[USER_LOCATION] cached_fix_unavailable '
          'fallback=$_cityLabel',
        );
        return;
      }
      final city = await ReverseGeocodeService.cityNameFromLatLon(
        position.latitude,
        position.longitude,
      );
      _latitude = position.latitude;
      _longitude = position.longitude;
      if (city != null && city.trim().isNotEmpty) {
        _cityLabel = city.trim();
      } else if (_cityLabel.isEmpty) {
        _cityLabel = HourlyWeatherService.defaultWeatherCityShortLabel;
      }
      debugPrint(
        '[USER_LOCATION] resolved city=$_cityLabel '
        'lat=${position.latitude} lon=${position.longitude}',
      );
    } catch (error) {
      if (_cityLabel.isEmpty) {
        _cityLabel = HourlyWeatherService.defaultWeatherCityShortLabel;
      }
      debugPrint(
        '[USER_LOCATION] resolve_failed fallback=$_cityLabel error=$error',
      );
    } finally {
      _resolveAttempted = true;
      _notifyIfCityChanged(previousCity);
    }
  }

  void _notifyIfCityChanged(String previousCity) {
    if (previousCity == _cityLabel) return;
    final listeners = List<UserLocationListener>.from(_listeners);
    for (final listener in listeners) {
      listener(_cityLabel);
    }
  }
}
