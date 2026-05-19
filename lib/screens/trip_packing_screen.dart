import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../Services/airport_record.dart';
import '../Services/airport_repository.dart';
import '../Services/destination_search_service.dart';
import '../Services/flight_arrival_estimator.dart';
import '../Services/flight_duration_estimator.dart';
import '../Services/trip_flight_models.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/reverse_geocode_service.dart';
import '../Services/trip_packing_service.dart';
import '../utils/luxury_weather_emoji.dart';
import '../widgets/home/home_glass_surface.dart';
import '../widgets/home/home_luxury_palette.dart';

/// „Čo si zbaliť?“ — prvý beh bez AI; vizuál v štýle Home (dark / glass / gold).
class TripPackingScreen extends StatefulWidget {
  const TripPackingScreen({super.key});

  @override
  State<TripPackingScreen> createState() => _TripPackingScreenState();
}

class _TripPackingScreenState extends State<TripPackingScreen> {
  final ScrollController _scrollController = ScrollController();

  final _destinationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();
  Timer? _destinationDebounce;
  DateTime? _outboundDeparture;
  DateTime? _outboundArrival;
  DateTime? _returnDeparture;
  DateTime? _returnArrival;

  final _planeOutboundOriginCtrl = TextEditingController();
  final _planeOutboundDestCtrl = TextEditingController();
  final _planeReturnOriginCtrl = TextEditingController();
  final _planeReturnDestCtrl = TextEditingController();
  final _roadOutboundOriginCtrl = TextEditingController();
  final _roadReturnOriginCtrl = TextEditingController();

  DestinationSuggestion? _selectedDestination;
  final Set<TripKind> _tripKinds = {TripKind.cityBreak};
  TripTransport _transport = TripTransport.plane;
  final Set<TripTravelStyle> _travelStyles = {};
  bool _roadOutboundUserEdited = false;
  bool _roadReturnUserEdited = false;
  bool _muteRoadOutboundListener = false;
  bool _muteRoadReturnListener = false;
  /// Set only after GPS city was written to „Odkiaľ vyrážaš“ — never block retries on failed/incomplete attempts.
  bool _gpsPrefillSucceeded = false;
  bool _gpsPrefillInFlight = false;

  bool _loading = false;
  TripPackingPlaceholderResult? _result;
  List<DestinationSuggestion> _destinationSuggestions = const [];
  bool _destinationLoading = false;
  bool _destinationNoResults = false;

  static final _dateTimeFmt = DateFormat('d. M. yyyy, HH:mm', 'sk');

  bool _mutePlaneReturnMirror = false;

  /// Arrival airport auto-selected vs manually edited (destination change logic).
  bool _outboundArrAirportAutoSelected = false;
  bool _outboundArrAirportManuallyEdited = false;
  String? _outboundArrAutoFillDestKey;

  /// Spiatočná trasa: manuálna úprava po poliach (neblokuje druhé pole).
  bool _returnDepartureManuallyEdited = false;
  bool _returnHomeArrivalManuallyEdited = false;

  /// Zobrazenie ručného výberu príchodu / príletu (lietadlo + auto); voliteľné rozšírenie (vlak/autobus).
  bool _manualUiOutboundArrival = false;
  bool _manualUiReturnArrival = false;
  bool _optionalOutboundArrivalOpen = false;
  bool _optionalReturnArrivalOpen = false;

  TripArrivalTimeSource _outboundArrivalSource = TripArrivalTimeSource.unknown;
  TripArrivalTimeSource _returnArrivalSource = TripArrivalTimeSource.unknown;

  AirportRecord? _outboundDepAirport;
  AirportRecord? _outboundArrAirport;
  AirportRecord? _returnDepAirport;
  AirportRecord? _returnArrAirport;
  FlightArrivalEstimate? _outboundFlightEstimate;
  FlightArrivalEstimate? _returnFlightEstimate;
  Timer? _outboundFlightDebounce;
  Timer? _returnFlightDebounce;

  void _onOutboundDepPlaneFieldChanged() {
    _syncReturnFlightFromOutbound();
    _applyPlaneOutboundArrivalEstimate();
    _applyPlaneReturnArrivalEstimate();
  }

  void _onOutboundArrPlaneFieldChanged() {
    _outboundArrAirportAutoSelected = false;
    _outboundArrAirportManuallyEdited = true;
    _syncReturnFlightFromOutbound();
    _applyPlaneOutboundArrivalEstimate();
    _applyPlaneReturnArrivalEstimate();
  }

  String _destinationContextKey(DestinationSuggestion? dest, String fallbackText) {
    if (dest != null) {
      return '${dest.name}|${dest.country}|${dest.latitude.toStringAsFixed(2)}|${dest.longitude.toStringAsFixed(2)}';
    }
    return DestinationSearchService.normalizeQuery(fallbackText);
  }

  bool _destinationContextChanged(String? previousKey, String newKey) {
    if (previousKey == null || previousKey.isEmpty) return false;
    if (previousKey == newKey) return false;
    final prevNorm = DestinationSearchService.normalizeQuery(previousKey);
    final newNorm = DestinationSearchService.normalizeQuery(newKey);
    if (prevNorm == newNorm) return false;
    if (prevNorm.length >= 3 && newNorm.length >= 3) {
      if (prevNorm.contains(newNorm) || newNorm.contains(prevNorm)) return false;
    }
    return true;
  }

  Future<bool> _confirmReplaceAirportForNewDestination() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HomeLuxuryPalette.bgTop,
        title: Text(
          'Zmeniť letisko?',
          style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.96)),
        ),
        content: Text(
          'Zmeniť letisko podľa novej destinácie?',
          style: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.88)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Ponechať',
              style: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.9)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Zmeniť',
              style: TextStyle(color: HomeLuxuryPalette.accent),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _onReturnDepPlaneFieldChanged() {
    if (_mutePlaneReturnMirror) return;
    _returnDepartureManuallyEdited = true;
    _applyPlaneReturnArrivalEstimate();
  }

  void _onReturnHomeArrPlaneFieldChanged() {
    if (_mutePlaneReturnMirror) return;
    _returnHomeArrivalManuallyEdited = true;
    _applyPlaneReturnArrivalEstimate();
  }

  bool get _canAutoFillOutboundArrivalAirport {
    if (_outboundArrAirportManuallyEdited && !_outboundArrAirportAutoSelected) {
      return false;
    }
    if (_outboundArrAirport != null &&
        !_outboundArrAirportAutoSelected &&
        !_outboundArrAirportManuallyEdited) {
      return false;
    }
    if (_outboundArrAirport == null &&
        _planeOutboundDestCtrl.text.trim().isNotEmpty &&
        !_outboundArrAirportAutoSelected) {
      return false;
    }
    return true;
  }

  /// Spiatočný let: odlet z B (kam prilietaš tam), príchod domov na A (odkiaľ letíš tam).
  void _syncReturnFlightFromOutbound() {
    if (_transport != TripTransport.plane) return;

    final saved = _scrollOffsetOrZero();
    final oText = _planeOutboundOriginCtrl.text.trim();
    final dText = _planeOutboundDestCtrl.text.trim();

    _mutePlaneReturnMirror = true;
    try {
      if (!_returnDepartureManuallyEdited) {
        if (dText.isEmpty && _outboundArrAirport == null) {
          _planeReturnOriginCtrl.clear();
        } else {
          final label = _outboundArrAirport?.displayTitle ?? dText;
          if (_planeReturnOriginCtrl.text != label) {
            _planeReturnOriginCtrl.text = label;
            _planeReturnOriginCtrl.selection =
                TextSelection.collapsed(offset: label.length);
          }
        }
      }
      if (!_returnHomeArrivalManuallyEdited) {
        if (oText.isEmpty && _outboundDepAirport == null) {
          _planeReturnDestCtrl.clear();
        } else {
          final label = _outboundDepAirport?.displayTitle ?? oText;
          if (_planeReturnDestCtrl.text != label) {
            _planeReturnDestCtrl.text = label;
            _planeReturnDestCtrl.selection = TextSelection.collapsed(offset: label.length);
          }
        }
      }
    } finally {
      _mutePlaneReturnMirror = false;
    }

    if (mounted) {
      setState(() {
        if (!_returnDepartureManuallyEdited) {
          _returnDepAirport = _outboundArrAirport;
        }
        if (!_returnHomeArrivalManuallyEdited) {
          _returnArrAirport = _outboundDepAirport;
        }
      });
    }
    _restoreScrollOffset(saved);
  }

  TripFlightPlanConfidence _mapFlightConf(FlightEstimateConfidence c) {
    switch (c) {
      case FlightEstimateConfidence.high:
        return TripFlightPlanConfidence.high;
      case FlightEstimateConfidence.medium:
        return TripFlightPlanConfidence.medium;
      case FlightEstimateConfidence.low:
        return TripFlightPlanConfidence.low;
    }
  }

  String _formatBlockDurationSk(int totalMin) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h > 0 && m > 0) return 'cca $h h $m min';
    if (h > 0) return 'cca $h h';
    return 'cca $m min';
  }

  Future<void> _recalculateOutboundPlaneArrival() async {
    if (!mounted) return;
    if (_transport != TripTransport.plane) return;
    if (_outboundArrivalSource == TripArrivalTimeSource.manual) return;

    final saved = _scrollOffsetOrZero();
    await AirportRepository.ensureLoaded();
    if (!mounted) return;

    final from = _outboundDepAirport ?? await AirportRepository.resolveBest(_planeOutboundOriginCtrl.text);
    final to = _outboundArrAirport ?? await AirportRepository.resolveBest(_planeOutboundDestCtrl.text);

    if (!mounted) return;

    if (_outboundDeparture == null || from == null || to == null || from.iata == to.iata) {
      setState(() {
        _outboundFlightEstimate = null;
        _outboundArrival = null;
        _outboundArrivalSource = TripArrivalTimeSource.unknown;
      });
      _restoreScrollOffset(saved);
      return;
    }

    final est = FlightArrivalEstimator.estimate(
      from: from,
      to: to,
      departureWallClock: _outboundDeparture!,
    );
    if (!mounted) return;
    setState(() {
      _outboundFlightEstimate = est;
      _outboundArrival = est.estimatedArrivalLocalNaive;
      _outboundArrivalSource = TripArrivalTimeSource.autoEstimated;
    });
    _restoreScrollOffset(saved);
  }

  Future<void> _recalculateReturnPlaneArrival() async {
    if (!mounted) return;
    if (_transport != TripTransport.plane) return;
    if (_returnArrivalSource == TripArrivalTimeSource.manual) return;

    final saved = _scrollOffsetOrZero();
    await AirportRepository.ensureLoaded();
    if (!mounted) return;

    final from = _returnDepAirport ?? await AirportRepository.resolveBest(_planeReturnOriginCtrl.text);
    final to = _returnArrAirport ?? await AirportRepository.resolveBest(_planeReturnDestCtrl.text);

    if (!mounted) return;

    if (_returnDeparture == null || from == null || to == null || from.iata == to.iata) {
      setState(() {
        _returnFlightEstimate = null;
        _returnArrival = null;
        _returnArrivalSource = TripArrivalTimeSource.unknown;
      });
      _restoreScrollOffset(saved);
      return;
    }

    final est = FlightArrivalEstimator.estimate(
      from: from,
      to: to,
      departureWallClock: _returnDeparture!,
    );
    if (!mounted) return;
    setState(() {
      _returnFlightEstimate = est;
      _returnArrival = est.estimatedArrivalLocalNaive;
      _returnArrivalSource = TripArrivalTimeSource.autoEstimated;
    });
    _restoreScrollOffset(saved);
  }

  void _applyPlaneOutboundArrivalEstimate() {
    if (_transport != TripTransport.plane) return;
    if (_outboundArrivalSource == TripArrivalTimeSource.manual) return;
    _outboundFlightDebounce?.cancel();
    _outboundFlightDebounce = Timer(const Duration(milliseconds: 220), () {
      _recalculateOutboundPlaneArrival();
    });
  }

  void _applyPlaneReturnArrivalEstimate() {
    if (_transport != TripTransport.plane) return;
    if (_returnArrivalSource == TripArrivalTimeSource.manual) return;
    _returnFlightDebounce?.cancel();
    _returnFlightDebounce = Timer(const Duration(milliseconds: 220), () {
      _recalculateReturnPlaneArrival();
    });
  }

  /// Po výbere destinácie cesty alebo prepnutí na lietadlo: „Kam prilietaš“ z najlepšieho letiska.
  Future<void> _tryPrefillOutboundArrivalAirportFromDestination({
    bool forceReplace = false,
  }) async {
    if (_transport != TripTransport.plane) return;
    if (!forceReplace && !_canAutoFillOutboundArrivalAirport) return;
    final dest = _selectedDestination?.displayName ?? _destinationCtrl.text.trim();
    if (dest.length < 2) return;
    final norm = DestinationSearchService.normalizeQuery(dest);
    if (norm.length < 2) return;

    final newDestKey = _destinationContextKey(_selectedDestination, dest);
    var mayReplace = forceReplace;
    if (!mayReplace &&
        _outboundArrAirportManuallyEdited &&
        !_outboundArrAirportAutoSelected &&
        _outboundArrAirport != null) {
      if (_destinationContextChanged(_outboundArrAutoFillDestKey, newDestKey)) {
        final replace = await _confirmReplaceAirportForNewDestination();
        if (!mounted || !replace) return;
        mayReplace = true;
        _outboundArrAirportManuallyEdited = false;
      } else {
        return;
      }
    }

    final saved = _scrollOffsetOrZero();
    try {
      await AirportRepository.ensureLoaded();
      if (!mounted || _transport != TripTransport.plane) return;
      if (!mayReplace && !_canAutoFillOutboundArrivalAirport) return;

      final sel = _selectedDestination;
      final best = await AirportRepository.matchBestForTripDestination(
        displayName: dest,
        cityName: sel?.name,
        adminRegion: sel?.adminRegion,
        countryName: sel?.country,
        latitude: sel?.latitude,
        longitude: sel?.longitude,
        population: sel?.population,
        featureCode: sel?.featureCode,
      );
      if (!mounted || _transport != TripTransport.plane) return;
      if (!mayReplace && !_canAutoFillOutboundArrivalAirport) return;
      if (best == null) {
        if (kDebugMode) {
          debugPrint('[TRIP_PACKING] planeArrivalPrefill: no confident airport for destination');
        }
        if (_outboundArrAirportAutoSelected) {
          _planeOutboundDestCtrl.removeListener(_onOutboundArrPlaneFieldChanged);
          try {
            setState(() {
              _outboundArrAirport = null;
              _planeOutboundDestCtrl.clear();
              _outboundArrAirportAutoSelected = false;
              _outboundArrAirportManuallyEdited = false;
              _outboundArrAutoFillDestKey = null;
            });
          } finally {
            _planeOutboundDestCtrl.addListener(_onOutboundArrPlaneFieldChanged);
          }
          _syncReturnFlightFromOutbound();
          _applyPlaneOutboundArrivalEstimate();
          _applyPlaneReturnArrivalEstimate();
        }
        _restoreScrollOffset(saved);
        return;
      }

      _planeOutboundDestCtrl.removeListener(_onOutboundArrPlaneFieldChanged);
      try {
        setState(() {
          _outboundArrAirport = best;
          _outboundArrAirportAutoSelected = true;
          _outboundArrAirportManuallyEdited = false;
          _outboundArrAutoFillDestKey = newDestKey;
          _planeOutboundDestCtrl.text = best.displayTitle;
          _planeOutboundDestCtrl.selection =
              TextSelection.collapsed(offset: best.displayTitle.length);
        });
      } finally {
        _planeOutboundDestCtrl.addListener(_onOutboundArrPlaneFieldChanged);
      }
      _restoreScrollOffset(saved);
      _syncReturnFlightFromOutbound();
      _applyPlaneOutboundArrivalEstimate();
      _applyPlaneReturnArrivalEstimate();
    } catch (e, st) {
      debugPrint('[TRIP_PACKING] planeArrivalPrefill failed: $e\n$st');
      if (mounted) _restoreScrollOffset(saved);
    }
  }

  bool get _roadLikeTransport =>
      _transport == TripTransport.car ||
      _transport == TripTransport.train ||
      _transport == TripTransport.bus;

  void _onRoadOutboundChanged() {
    if (_muteRoadOutboundListener) return;
    _roadOutboundUserEdited = true;
  }

  void _onRoadReturnChanged() {
    if (_muteRoadReturnListener) return;
    _roadReturnUserEdited = true;
  }

  void _prefillReturnFromDestination() {
    if (!_roadLikeTransport) return;
    if (_roadReturnUserEdited) return;
    final raw = _selectedDestination?.displayName ?? _destinationCtrl.text.trim();
    if (raw.isEmpty) return;
    final first = raw.split(',').first.trim();
    if (first.isEmpty) return;
    _muteRoadReturnListener = true;
    _roadReturnOriginCtrl.text = first;
    _muteRoadReturnListener = false;
  }

  void _gpsPrefillLog(String msg) {
    debugPrint('[GPS_PREFILL] $msg');
  }

  void _showDebugGpsFailureSnack() {
    if (!kDebugMode || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nepodarilo sa zistiť aktuálne mesto.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Fallback zhodný s predvoleným mestom počasia v aplikácii ([HourlyWeatherService]).
  bool _applyFallbackDepartureCity(String reason) {
    if (_roadOutboundUserEdited) {
      _gpsPrefillLog('fallback skipped reason=user_edited ($reason)');
      return false;
    }
    if (_roadOutboundOriginCtrl.text.trim().isNotEmpty) {
      _gpsPrefillLog('fallback skipped reason=field_nonempty ($reason)');
      return false;
    }
    final label = HourlyWeatherService.defaultWeatherCityShortLabel;
    _gpsPrefillLog('fallback_apply label=$label context=$reason');
    _muteRoadOutboundListener = true;
    _roadOutboundOriginCtrl.text = label;
    _muteRoadOutboundListener = false;
    _gpsPrefillSucceeded = true;
    _gpsPrefillLog('wroteController=true value="$label" (fallback)');
    setState(() {});
    return true;
  }

  Future<void> _gpsFinishWithoutCoordinateCity(String context) async {
    _gpsPrefillLog('finish_without_coordinate_city context=$context');
    if (!mounted) return;
    final filled = _applyFallbackDepartureCity(context);
    if (!filled && kDebugMode && mounted) {
      _showDebugGpsFailureSnack();
    }
  }

  Future<void> _tryPrefillRoadOutboundFromGps({String trigger = 'unknown'}) async {
    _gpsPrefillLog(
      'trigger=$trigger transport=${_transport.name} roadLike=$_roadLikeTransport '
      'userEdited=$_roadOutboundUserEdited field="${_roadOutboundOriginCtrl.text}" '
      'succeeded=$_gpsPrefillSucceeded inFlight=$_gpsPrefillInFlight',
    );

    if (!mounted) {
      _gpsPrefillLog('skipped reason=unmounted');
      return;
    }
    if (!_roadLikeTransport) {
      _gpsPrefillLog('skipped reason=not_road_transport');
      return;
    }
    if (_roadOutboundUserEdited) {
      _gpsPrefillLog('skipped reason=user_edited');
      return;
    }
    if (_roadOutboundOriginCtrl.text.trim().isNotEmpty) {
      _gpsPrefillLog('skipped reason=field_non_empty');
      return;
    }
    if (_gpsPrefillSucceeded) {
      _gpsPrefillLog('skipped reason=already_succeeded');
      return;
    }
    if (_gpsPrefillInFlight) {
      _gpsPrefillLog('skipped reason=in_flight');
      return;
    }

    _gpsPrefillLog('shouldRun=true');
    _gpsPrefillInFlight = true;
    var gpsResolvedFromDevice = false;

    try {
      final permBefore = await Geolocator.checkPermission();
      _gpsPrefillLog('permissionBefore=$permBefore');

      final serviceOn = await Geolocator.isLocationServiceEnabled();
      _gpsPrefillLog('serviceEnabled=$serviceOn');
      if (!serviceOn) {
        _gpsPrefillLog('skipped reason=location_service_disabled');
        await _gpsFinishWithoutCoordinateCity('location_service_disabled');
        return;
      }

      var permAfter = permBefore;
      if (permBefore == LocationPermission.denied) {
        permAfter = await Geolocator.requestPermission();
      }
      _gpsPrefillLog('permissionAfter=$permAfter');

      if (permAfter == LocationPermission.denied ||
          permAfter == LocationPermission.deniedForever) {
        _gpsPrefillLog('skipped reason=permission_denied');
        await _gpsFinishWithoutCoordinateCity('permission_denied');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('gps_timeout'),
      );
      _gpsPrefillLog('position lat=${pos.latitude} lon=${pos.longitude}');

      final resolved = await ReverseGeocodeService.resolveCityLabelWithDetails(
        pos.latitude,
        pos.longitude,
      ).timeout(const Duration(seconds: 12));

      if (resolved == null) {
        _gpsPrefillLog('reverseGeocode result=null');
        _gpsPrefillLog('chosenCity=null');
        await _gpsFinishWithoutCoordinateCity('reverse_geocode_null');
        return;
      }

      _gpsPrefillLog('reverseGeocode result=${resolved.debugLine}');

      final city = resolved.cityLabel?.trim();
      _gpsPrefillLog('chosenCity=${city ?? "(empty)"}');

      if (!mounted) return;

      if (city == null || city.isEmpty) {
        _gpsPrefillLog('skipped reason=chosen_city_empty');
        await _gpsFinishWithoutCoordinateCity('chosen_city_empty');
        return;
      }

      gpsResolvedFromDevice = true;
      _gpsPrefillSucceeded = true;
      _muteRoadOutboundListener = true;
      _roadOutboundOriginCtrl.text = city;
      _muteRoadOutboundListener = false;
      _gpsPrefillLog('wroteController=true value="$city"');
      setState(() {});
    } catch (e, st) {
      _gpsPrefillLog('exception error=$e');
      debugPrint('$st');
      await _gpsFinishWithoutCoordinateCity('exception');
    } finally {
      _gpsPrefillInFlight = false;
      _gpsPrefillLog('done gpsResolvedFromDevice=$gpsResolvedFromDevice');
    }
  }

  void _toggleTripKind(TripKind k) {
    setState(() {
      if (_tripKinds.contains(k)) {
        if (_tripKinds.length > 1) _tripKinds.remove(k);
      } else {
        _tripKinds.add(k);
      }
    });
  }

  void _toggleTravelStyle(TripTravelStyle s) {
    setState(() {
      if (_travelStyles.contains(s)) {
        _travelStyles.remove(s);
      } else {
        _travelStyles.add(s);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _planeOutboundOriginCtrl.addListener(_onOutboundDepPlaneFieldChanged);
    _planeOutboundDestCtrl.addListener(_onOutboundArrPlaneFieldChanged);
    _planeReturnOriginCtrl.addListener(_onReturnDepPlaneFieldChanged);
    _planeReturnDestCtrl.addListener(_onReturnHomeArrPlaneFieldChanged);
    _roadOutboundOriginCtrl.addListener(_onRoadOutboundChanged);
    _roadReturnOriginCtrl.addListener(_onRoadReturnChanged);
    _destinationFocus.addListener(() {
      if (!_destinationFocus.hasFocus) {
        _prefillReturnFromDestination();
      }
      if (_destinationFocus.hasFocus && _destinationCtrl.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _destinationCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _destinationCtrl.text.length,
          );
        });
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _tryPrefillRoadOutboundFromGps(trigger: 'init'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AirportRepository.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _outboundFlightDebounce?.cancel();
    _returnFlightDebounce?.cancel();
    _planeOutboundOriginCtrl.removeListener(_onOutboundDepPlaneFieldChanged);
    _planeOutboundDestCtrl.removeListener(_onOutboundArrPlaneFieldChanged);
    _planeReturnOriginCtrl.removeListener(_onReturnDepPlaneFieldChanged);
    _planeReturnDestCtrl.removeListener(_onReturnHomeArrPlaneFieldChanged);
    _roadOutboundOriginCtrl.removeListener(_onRoadOutboundChanged);
    _roadReturnOriginCtrl.removeListener(_onRoadReturnChanged);
    _destinationDebounce?.cancel();
    _destinationCtrl.dispose();
    _notesCtrl.dispose();
    _planeOutboundOriginCtrl.dispose();
    _planeOutboundDestCtrl.dispose();
    _planeReturnOriginCtrl.dispose();
    _planeReturnDestCtrl.dispose();
    _roadOutboundOriginCtrl.dispose();
    _roadReturnOriginCtrl.dispose();
    _destinationFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Po novom výsledku alebo návrate na formulár vždy začni od vrchu stránky.
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
      debugPrint('[TRIP_SCROLL] resetToTop');
    });
  }

  double _scrollOffsetOrZero() {
    if (!_scrollController.hasClients) return 0;
    return _scrollController.offset;
  }

  void _restoreScrollOffset(double saved) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(saved.clamp(0.0, max));
    });
  }

  Future<void> _pickTripDateTime(void Function(DateTime v) assign, {DateTime? current}) async {
    final savedOffset = _scrollOffsetOrZero();
    final now = DateTime.now();
    final initial = current ?? now;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: HomeLuxuryPalette.accent,
            surface: HomeLuxuryPalette.surface,
            onSurface: HomeLuxuryPalette.textPrimary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: HomeLuxuryPalette.surface),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? pickedDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: HomeLuxuryPalette.accent,
            surface: HomeLuxuryPalette.surface,
            onSurface: HomeLuxuryPalette.textPrimary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: HomeLuxuryPalette.surface),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      assign(DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ));
    });
    _restoreScrollOffset(savedOffset);
  }

  void _updateDestinationSuggestions(String query) {
    _destinationDebounce?.cancel();
    _selectedDestination = null;
    final normalized = DestinationSearchService.normalizeQuery(query);
    if (normalized.length < 2) {
      setState(() {
        _destinationSuggestions = const [];
        _destinationLoading = false;
        _destinationNoResults = false;
      });
      return;
    }
    setState(() {
      _destinationLoading = true;
      _destinationNoResults = false;
    });
    _destinationDebounce = Timer(const Duration(milliseconds: 380), () async {
      final snapshot = query.trim();
      final out = await DestinationSearchService.search(snapshot);
      if (!mounted || _destinationCtrl.text.trim() != snapshot) return;
      setState(() {
        _destinationLoading = false;
        _destinationSuggestions = out;
        _destinationNoResults = out.isEmpty;
      });
    });
  }

  bool _validate() {
    final dest = _destinationCtrl.text.trim();
    if (dest.isEmpty) {
      _toast('Zadaj destináciu alebo mesto.');
      return false;
    }
    if (_outboundDeparture == null || _returnDeparture == null) {
      _toast('Vyplň čas odchodu tam a čas odchodu späť.');
      return false;
    }
    if (_outboundArrival != null && !_outboundArrival!.isAfter(_outboundDeparture!)) {
      _toast('Príchod tam musí byť po odchode tam.');
      return false;
    }
    if (_returnArrival != null && !_returnArrival!.isAfter(_returnDeparture!)) {
      _toast('Príchod domov musí byť po odchode späť.');
      return false;
    }
    final outboundEnd = _outboundArrival ?? _outboundDeparture!;
    if (!_returnDeparture!.isAfter(outboundEnd)) {
      _toast('Odchod späť musí byť neskôr ako koniec cesty tam (príchod tam alebo odchod tam).');
      return false;
    }
    if (_transport == TripTransport.plane && _planeOutboundOriginCtrl.text.trim().isEmpty) {
      _toast('Zadaj odkiaľ letíš.');
      return false;
    }
    if (_transport == TripTransport.plane && _planeOutboundDestCtrl.text.trim().isEmpty) {
      _toast('Zadaj kam prilietaš.');
      return false;
    }
    if ((_transport == TripTransport.car ||
            _transport == TripTransport.train ||
            _transport == TripTransport.bus) &&
        _roadOutboundOriginCtrl.text.trim().isEmpty) {
      _toast('Zadaj odkiaľ vyrážaš (cesta tam).');
      return false;
    }
    return true;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _onSubmit() async {
    await AirportRepository.ensureLoaded();
    if (_transport == TripTransport.plane) {
      final fo = _outboundDepAirport ?? await AirportRepository.resolveBest(_planeOutboundOriginCtrl.text);
      final ta = _outboundArrAirport ?? await AirportRepository.resolveBest(_planeOutboundDestCtrl.text);
      final rFrom = _returnDepAirport ?? await AirportRepository.resolveBest(_planeReturnOriginCtrl.text);
      final rTo = _returnArrAirport ?? await AirportRepository.resolveBest(_planeReturnDestCtrl.text);

      if (fo == null || ta == null || rFrom == null || rTo == null) {
        _toast(
          'Prílet zatiaľ nevieme odhadnúť. Vyber presnejšie letisko alebo zadaj prílet manuálne.',
        );
        return;
      }

      if (_outboundArrivalSource != TripArrivalTimeSource.manual && _outboundArrival == null) {
        _toast(
          'Prílet zatiaľ nevieme odhadnúť. Vyber presnejšie letisko alebo zadaj prílet manuálne.',
        );
        return;
      }
      if (_outboundArrivalSource == TripArrivalTimeSource.manual && _outboundArrival == null) {
        _toast('Vyplň čas príletu tam.');
        return;
      }

      if (_returnArrivalSource != TripArrivalTimeSource.manual && _returnArrival == null) {
        _toast(
          'Prílet zatiaľ nevieme odhadnúť. Vyber presnejšie letisko alebo zadaj prílet manuálne.',
        );
        return;
      }
      if (_returnArrivalSource == TripArrivalTimeSource.manual && _returnArrival == null) {
        _toast('Vyplň čas spiatočného príletu.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _outboundDepAirport = fo;
        _outboundArrAirport = ta;
        _returnDepAirport = rFrom;
        _returnArrAirport = rTo;
      });
    }

    if (!_validate()) return;

    final destText = _destinationCtrl.text.trim();
    final destDisplay = _selectedDestination?.displayName ?? destText;

    String? outOrig;
    String? outDest;
    String? retOrig;
    String? retDest;

    if (_transport == TripTransport.plane) {
      outOrig = _planeOutboundOriginCtrl.text.trim();
      outDest = _planeOutboundDestCtrl.text.trim();
      retOrig =
          _planeReturnOriginCtrl.text.trim().isEmpty ? outDest : _planeReturnOriginCtrl.text.trim();
      retDest =
          _planeReturnDestCtrl.text.trim().isEmpty ? outOrig : _planeReturnDestCtrl.text.trim();
    } else {
      outOrig = _roadOutboundOriginCtrl.text.trim();
      outDest = destText;
      retOrig =
          _roadReturnOriginCtrl.text.trim().isEmpty ? destDisplay : _roadReturnOriginCtrl.text.trim();
      retDest = _roadOutboundOriginCtrl.text.trim();
    }

    final input = TripPlanInput(
      userId: FirebaseAuth.instance.currentUser?.uid,
      destinationText: destText,
      selectedDestinationName: _selectedDestination?.name,
      destinationCountry: _selectedDestination?.country,
      destinationLatitude: _selectedDestination?.latitude,
      destinationLongitude: _selectedDestination?.longitude,
      outboundOriginLabel: outOrig.isEmpty ? null : outOrig,
      outboundDestinationLabel: outDest.isEmpty ? null : outDest,
      returnOriginLabel: retOrig.isEmpty ? null : retOrig,
      returnDestinationLabel: retDest.isEmpty ? null : retDest,
      tripKinds: Set<TripKind>.from(_tripKinds),
      transport: _transport,
      travelStyles: Set<TripTravelStyle>.from(_travelStyles),
      activityNotes: _notesCtrl.text.trim(),
      outboundDeparture: _outboundDeparture,
      outboundArrival: _outboundArrival,
      returnDeparture: _returnDeparture,
      returnArrival: _returnArrival,
      outboundArrivalTimeSource: _outboundArrivalSource,
      returnArrivalTimeSource: _returnArrivalSource,
      planeOutboundDepartureIata: _transport == TripTransport.plane ? _outboundDepAirport?.iata : null,
      planeOutboundArrivalIata: _transport == TripTransport.plane ? _outboundArrAirport?.iata : null,
      planeReturnDepartureIata: _transport == TripTransport.plane ? _returnDepAirport?.iata : null,
      planeReturnArrivalIata: _transport == TripTransport.plane ? _returnArrAirport?.iata : null,
      planeOutboundEstimatedFlightDurationMinutes:
          _transport == TripTransport.plane ? _outboundFlightEstimate?.duration.estimatedDurationMinutes : null,
      planeOutboundEstimatedDistanceKm:
          _transport == TripTransport.plane ? _outboundFlightEstimate?.duration.distanceKm : null,
      planeOutboundEstimateConfidence: _transport == TripTransport.plane && _outboundFlightEstimate != null
          ? _mapFlightConf(_outboundFlightEstimate!.duration.confidence)
          : TripFlightPlanConfidence.unknown,
      planeOutboundEstimatedArrivalTimezone:
          _transport == TripTransport.plane ? _outboundFlightEstimate?.estimatedArrivalTimezoneIana : null,
      planeOutboundTimezoneConfidence: _transport == TripTransport.plane && _outboundFlightEstimate != null
          ? _outboundFlightEstimate!.timezoneConfidence
          : TripTimezoneConfidence.unknown,
      planeReturnEstimatedFlightDurationMinutes:
          _transport == TripTransport.plane ? _returnFlightEstimate?.duration.estimatedDurationMinutes : null,
      planeReturnEstimatedDistanceKm:
          _transport == TripTransport.plane ? _returnFlightEstimate?.duration.distanceKm : null,
      planeReturnEstimateConfidence: _transport == TripTransport.plane && _returnFlightEstimate != null
          ? _mapFlightConf(_returnFlightEstimate!.duration.confidence)
          : TripFlightPlanConfidence.unknown,
      planeReturnEstimatedArrivalTimezone:
          _transport == TripTransport.plane ? _returnFlightEstimate?.estimatedArrivalTimezoneIana : null,
      planeReturnTimezoneConfidence: _transport == TripTransport.plane && _returnFlightEstimate != null
          ? _returnFlightEstimate!.timezoneConfidence
          : TripTimezoneConfidence.unknown,
    );

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final out = await TripPackingService.generatePlaceholderPlan(input);
      if (!mounted) return;
      setState(() => _result = out);
      _scrollToTop();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _resetResult() {
    setState(() => _result = null);
    _scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeLuxuryPalette.bgBottom,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HomeLuxuryPalette.bgTop,
                    HomeLuxuryPalette.bgMid,
                    HomeLuxuryPalette.bgBottom,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            color: HomeLuxuryPalette.accent.withOpacity(0.92), size: 20),
                        splashRadius: 22,
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const PageStorageKey<String>('trip_packing_form_scroll'),
                    controller: _scrollController,
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Čo si zbaliť?',
                          style: HomeLuxuryPalette.titleLarge.copyWith(
                            fontSize: 28,
                            letterSpacing: -0.6,
                            color: HomeLuxuryPalette.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (_result == null) ...[
                          _DestinationCard(
                            controller: _destinationCtrl,
                            focusNode: _destinationFocus,
                            suggestions: _destinationSuggestions,
                            onChanged: _updateDestinationSuggestions,
                            loading: _destinationLoading,
                            showNoResults: _destinationNoResults,
                            onSuggestionTap: (value) async {
                              final s = _scrollOffsetOrZero();
                              final prevDestKey = _outboundArrAutoFillDestKey;
                              _selectedDestination = value;
                              _destinationCtrl.text = value.displayName;
                              _destinationCtrl.selection = TextSelection.collapsed(
                                offset: value.displayName.length,
                              );
                              setState(() {
                                _destinationSuggestions = const [];
                                _destinationLoading = false;
                                _destinationNoResults = false;
                              });
                              _restoreScrollOffset(s);
                              _prefillReturnFromDestination();
                              if (_transport == TripTransport.plane) {
                                final newKey = _destinationContextKey(value, value.displayName);
                                final force = _outboundArrAirportAutoSelected &&
                                    _destinationContextChanged(prevDestKey, newKey);
                                await _tryPrefillOutboundArrivalAirportFromDestination(
                                  forceReplace: force,
                                );
                              }
                              if (mounted) FocusScope.of(context).unfocus();
                            },
                          ),
                          const SizedBox(height: 14),
                          _TransportSection(
                            selected: _transport,
                            onChanged: (v) {
                              final scrollSaved = _scrollOffsetOrZero();
                              final prev = _transport;
                              debugPrint('[GPS_PREFILL] transport selected=${v.name}');
                              setState(() {
                                _outboundDepAirport = null;
                                _outboundArrAirport = null;
                                _returnDepAirport = null;
                                _returnArrAirport = null;
                                _outboundArrAirportAutoSelected = false;
                                _outboundArrAirportManuallyEdited = false;
                                _outboundArrAutoFillDestKey = null;
                                _returnDepartureManuallyEdited = false;
                                _returnHomeArrivalManuallyEdited = false;
                                _outboundFlightEstimate = null;
                                _returnFlightEstimate = null;
                                if (prev == TripTransport.plane && v != TripTransport.plane) {
                                  if (_outboundArrivalSource == TripArrivalTimeSource.autoEstimated) {
                                    _outboundArrival = null;
                                    _outboundArrivalSource = TripArrivalTimeSource.unknown;
                                  }
                                  if (_returnArrivalSource == TripArrivalTimeSource.autoEstimated) {
                                    _returnArrival = null;
                                    _returnArrivalSource = TripArrivalTimeSource.unknown;
                                  }
                                }
                                _manualUiOutboundArrival = false;
                                _manualUiReturnArrival = false;
                                _optionalOutboundArrivalOpen = false;
                                _optionalReturnArrivalOpen = false;
                                _transport = v;
                                if (_roadLikeTransport &&
                                    _roadOutboundOriginCtrl.text.trim().isEmpty &&
                                    !_roadOutboundUserEdited) {
                                  _gpsPrefillSucceeded = false;
                                }
                              });
                              _restoreScrollOffset(scrollSaved);
                              if (_roadLikeTransport) {
                                _prefillReturnFromDestination();
                                if (_roadOutboundOriginCtrl.text.trim().isEmpty &&
                                    !_roadOutboundUserEdited) {
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _tryPrefillRoadOutboundFromGps(
                                      trigger: 'transport_${v.name}',
                                    ),
                                  );
                                }
                              }
                              if (v == TripTransport.plane) {
                                WidgetsBinding.instance.addPostFrameCallback((_) async {
                                  if (!mounted) return;
                                  await _tryPrefillOutboundArrivalAirportFromDestination();
                                  if (!mounted) return;
                                  _applyPlaneOutboundArrivalEstimate();
                                  _applyPlaneReturnArrivalEstimate();
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          _TransportDetailsCard(
                            transport: _transport,
                            planeOutboundOriginController: _planeOutboundOriginCtrl,
                            planeOutboundDestController: _planeOutboundDestCtrl,
                            planeReturnOriginController: _planeReturnOriginCtrl,
                            planeReturnDestController: _planeReturnDestCtrl,
                            roadOutboundOriginController: _roadOutboundOriginCtrl,
                            roadReturnOriginController: _roadReturnOriginCtrl,
                            outboundDeparture: _outboundDeparture,
                            outboundArrival: _outboundArrival,
                            returnDeparture: _returnDeparture,
                            returnArrival: _returnArrival,
                            outboundArrivalSource: _outboundArrivalSource,
                            returnArrivalSource: _returnArrivalSource,
                            manualUiOutboundArrival: _manualUiOutboundArrival,
                            manualUiReturnArrival: _manualUiReturnArrival,
                            optionalOutboundArrivalOpen: _optionalOutboundArrivalOpen,
                            optionalReturnArrivalOpen: _optionalReturnArrivalOpen,
                            formatDateTime: (d) => _dateTimeFmt.format(d),
                            formatBlockDurationSk: _formatBlockDurationSk,
                            airportOutboundDep: _outboundDepAirport,
                            airportOutboundArr: _outboundArrAirport,
                            airportReturnDep: _returnDepAirport,
                            airportReturnArr: _returnArrAirport,
                            outboundFlightEstimate: _outboundFlightEstimate,
                            returnFlightEstimate: _returnFlightEstimate,
                            outboundPlaneCannotEstimate: _transport == TripTransport.plane &&
                                !_manualUiOutboundArrival &&
                                _outboundDeparture != null &&
                                _planeOutboundOriginCtrl.text.trim().isNotEmpty &&
                                _planeOutboundDestCtrl.text.trim().isNotEmpty &&
                                _outboundArrivalSource != TripArrivalTimeSource.manual &&
                                _outboundFlightEstimate == null &&
                                _outboundArrival == null,
                            returnPlaneCannotEstimate: _transport == TripTransport.plane &&
                                !_manualUiReturnArrival &&
                                _returnDeparture != null &&
                                _planeReturnOriginCtrl.text.trim().isNotEmpty &&
                                _planeReturnDestCtrl.text.trim().isNotEmpty &&
                                _returnArrivalSource != TripArrivalTimeSource.manual &&
                                _returnFlightEstimate == null &&
                                _returnArrival == null,
                            tripDestinationCityLabel: _selectedDestination?.name,
                            onOutboundDepAirportChanged: (a) {
                              final s = _scrollOffsetOrZero();
                              setState(() => _outboundDepAirport = a);
                              _syncReturnFlightFromOutbound();
                              _applyPlaneOutboundArrivalEstimate();
                              _applyPlaneReturnArrivalEstimate();
                              _restoreScrollOffset(s);
                            },
                            onOutboundArrAirportChanged: (a) {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _outboundArrAirport = a;
                                if (a != null) {
                                  _outboundArrAirportAutoSelected = false;
                                  _outboundArrAirportManuallyEdited = true;
                                }
                              });
                              _syncReturnFlightFromOutbound();
                              _applyPlaneOutboundArrivalEstimate();
                              _applyPlaneReturnArrivalEstimate();
                              _restoreScrollOffset(s);
                            },
                            onReturnDepAirportChanged: (a) {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _returnDepAirport = a;
                                _returnDepartureManuallyEdited = true;
                              });
                              _restoreScrollOffset(s);
                            },
                            onReturnArrAirportChanged: (a) {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _returnArrAirport = a;
                                _returnHomeArrivalManuallyEdited = true;
                              });
                              _restoreScrollOffset(s);
                            },
                            onRequestManualOutboundArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() => _manualUiOutboundArrival = true);
                              _restoreScrollOffset(s);
                            },
                            onRequestManualReturnArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() => _manualUiReturnArrival = true);
                              _restoreScrollOffset(s);
                            },
                            onToggleOptionalOutboundArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() => _optionalOutboundArrivalOpen = !_optionalOutboundArrivalOpen);
                              _restoreScrollOffset(s);
                            },
                            onToggleOptionalReturnArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() => _optionalReturnArrivalOpen = !_optionalReturnArrivalOpen);
                              _restoreScrollOffset(s);
                            },
                            onPickOutboundDeparture: () {
                              _pickTripDateTime(
                                (v) => _outboundDeparture = v,
                                current: _outboundDeparture,
                              ).then((_) {
                                if (mounted) _applyPlaneOutboundArrivalEstimate();
                              });
                            },
                            onPickOutboundArrival: () {
                              _pickTripDateTime(
                                (v) => _outboundArrival = v,
                                current: _outboundArrival,
                              ).then((_) {
                                if (!mounted) return;
                                final s = _scrollOffsetOrZero();
                                setState(() => _outboundArrivalSource = TripArrivalTimeSource.manual);
                                _restoreScrollOffset(s);
                              });
                            },
                            onPickReturnDeparture: () {
                              _pickTripDateTime(
                                (v) => _returnDeparture = v,
                                current: _returnDeparture,
                              ).then((_) {
                                if (mounted) _applyPlaneReturnArrivalEstimate();
                              });
                            },
                            onPickReturnArrival: () {
                              _pickTripDateTime(
                                (v) => _returnArrival = v,
                                current: _returnArrival,
                              ).then((_) {
                                if (!mounted) return;
                                final s = _scrollOffsetOrZero();
                                setState(() => _returnArrivalSource = TripArrivalTimeSource.manual);
                                _restoreScrollOffset(s);
                              });
                            },
                            onClearOutboundDeparture: () {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _outboundDeparture = null;
                                if (_transport == TripTransport.plane &&
                                    _outboundArrivalSource != TripArrivalTimeSource.manual) {
                                  _outboundArrival = null;
                                  _outboundArrivalSource = TripArrivalTimeSource.unknown;
                                  _outboundFlightEstimate = null;
                                }
                              });
                              _restoreScrollOffset(s);
                            },
                            onClearOutboundArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _outboundArrival = null;
                                _outboundArrivalSource = TripArrivalTimeSource.unknown;
                                _manualUiOutboundArrival = false;
                                _outboundFlightEstimate = null;
                              });
                              _restoreScrollOffset(s);
                              _applyPlaneOutboundArrivalEstimate();
                            },
                            onClearReturnDeparture: () {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _returnDeparture = null;
                                if (_transport == TripTransport.plane &&
                                    _returnArrivalSource != TripArrivalTimeSource.manual) {
                                  _returnArrival = null;
                                  _returnArrivalSource = TripArrivalTimeSource.unknown;
                                  _returnFlightEstimate = null;
                                }
                              });
                              _restoreScrollOffset(s);
                            },
                            onClearReturnArrival: () {
                              final s = _scrollOffsetOrZero();
                              setState(() {
                                _returnArrival = null;
                                _returnArrivalSource = TripArrivalTimeSource.unknown;
                                _manualUiReturnArrival = false;
                                _returnFlightEstimate = null;
                              });
                              _restoreScrollOffset(s);
                              _applyPlaneReturnArrivalEstimate();
                            },
                          ),
                          const SizedBox(height: 14),
                          _TripKindSection(
                            selected: _tripKinds,
                            onToggle: _toggleTripKind,
                          ),
                          const SizedBox(height: 14),
                          _NotesSection(controller: _notesCtrl),
                          const SizedBox(height: 14),
                          _TravelStyleSection(
                            selected: _travelStyles,
                            onToggle: _toggleTravelStyle,
                          ),
                          const SizedBox(height: 28),
                          _GoldCta(onPressed: _loading ? null : _onSubmit),
                        ] else ...[
                          _PlaceholderResultView(
                            result: _result!,
                            onEdit: _resetResult,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading) _loadingOverlay(),
        ],
      ),
    );
  }

  Widget _loadingOverlay() {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.black.withOpacity(0.45),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: HomeLuxuryPalette.border),
                color: HomeLuxuryPalette.surface.withOpacity(0.72),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: HomeLuxuryPalette.accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Pripravujem návrh…',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.onChanged,
    required this.loading,
    required this.showNoResults,
    required this.onSuggestionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<DestinationSuggestion> suggestions;
  final ValueChanged<String> onChanged;
  final bool loading;
  final bool showNoResults;
  final ValueChanged<DestinationSuggestion> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined, color: HomeLuxuryPalette.accent.withOpacity(0.88), size: 20),
              const SizedBox(width: 8),
              Text(
                'Kam cestuješ?',
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onTap: () {
              if (controller.text.isEmpty) return;
              controller.selection =
                  TextSelection(baseOffset: 0, extentOffset: controller.text.length);
            },
            style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.96), fontSize: 15),
            cursorColor: HomeLuxuryPalette.accent,
            decoration: InputDecoration(
              hintText: 'Mesto alebo destinácia',
              hintStyle: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.65)),
              filled: true,
              fillColor: HomeLuxuryPalette.bgTop.withOpacity(0.42),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.accent.withOpacity(0.55), width: 1.2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: HomeLuxuryPalette.accent.withOpacity(0.85),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Hľadám…',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ] else if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HomeLuxuryPalette.border),
                color: HomeLuxuryPalette.bgTop.withOpacity(0.36),
              ),
              child: Column(
                children: [
                  for (final suggestion in suggestions)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSuggestionTap(suggestion),
                        splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 16, color: HomeLuxuryPalette.accent.withOpacity(0.82)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SuggestionText(
                                  suggestion: suggestion,
                                  query: controller.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ] else if (showNoResults) ...[
            const SizedBox(height: 10),
            Text(
              'Nenašiel som miesto. Skús napísať názov mesta inak.',
              style: TextStyle(
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.8),
                fontSize: 12.3,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionText extends StatelessWidget {
  const _SuggestionText({
    required this.suggestion,
    required this.query,
  });

  final DestinationSuggestion suggestion;
  final String query;

  @override
  Widget build(BuildContext context) {
    final q = DestinationSearchService.normalizeQuery(query);
    final highlight = q.isNotEmpty &&
        DestinationSearchService.normalizeQuery(suggestion.displayName).contains(q);
    final secondLine = suggestion.adminRegion != null &&
            suggestion.adminRegion!.isNotEmpty &&
            suggestion.adminRegion != suggestion.name
        ? '${suggestion.adminRegion}, ${suggestion.country}'
        : suggestion.country;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          suggestion.name,
          style: TextStyle(
            color: highlight
                ? HomeLuxuryPalette.textPrimary.withOpacity(0.98)
                : HomeLuxuryPalette.textPrimary.withOpacity(0.9),
            fontSize: 13.6,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          secondLine,
          style: TextStyle(
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.8),
            fontSize: 11.8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}


class _TravelDateTimeRow extends StatelessWidget {
  const _TravelDateTimeRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HomeLuxuryPalette.accent.withOpacity(0.35)),
                  color: HomeLuxuryPalette.bgTop.withOpacity(0.35),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded,
                        size: 16, color: HomeLuxuryPalette.accent.withOpacity(0.88)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value ?? 'Vybrať dátum a čas',
                        style: TextStyle(
                          color: value != null
                              ? HomeLuxuryPalette.textPrimary.withOpacity(0.95)
                              : HomeLuxuryPalette.textSecondary.withOpacity(0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 6),
          IconButton(
            onPressed: onClear,
            splashRadius: 20,
            icon: Icon(Icons.close_rounded,
                size: 18, color: HomeLuxuryPalette.textSecondary.withOpacity(0.65)),
          ),
        ],
      ],
    );
  }
}

class _TripKindSection extends StatelessWidget {
  const _TripKindSection({
    required this.selected,
    required this.onToggle,
  });

  final Set<TripKind> selected;
  final ValueChanged<TripKind> onToggle;

  static const _options = <(TripKind, String)>[
    (TripKind.holiday, 'Dovolenka'),
    (TripKind.cityBreak, 'Výlet do mesta'),
    (TripKind.business, 'Pracovná cesta'),
    (TripKind.hiking, 'Turistika'),
    (TripKind.beach, 'Pláž'),
    (TripKind.festival, 'Festival'),
  ];

  @override
  Widget build(BuildContext context) {
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Typ cesty',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Môžeš vybrať viac typov naraz (napr. dovolenka + pláž + turistika). Aspoň jeden musí zostať.',
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                _ChoiceChip(
                  label: o.$2,
                  selected: selected.contains(o.$1),
                  onTap: () => onToggle(o.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransportSection extends StatelessWidget {
  const _TransportSection({
    required this.selected,
    required this.onChanged,
  });

  final TripTransport selected;
  final ValueChanged<TripTransport> onChanged;

  static const _options = <(TripTransport, String)>[
    (TripTransport.plane, 'Lietadlo'),
    (TripTransport.car, 'Auto'),
    (TripTransport.train, 'Vlak'),
    (TripTransport.bus, 'Autobus'),
  ];

  @override
  Widget build(BuildContext context) {
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Doprava',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                _ChoiceChip(
                  label: o.$2,
                  selected: selected == o.$1,
                  onTap: () => onChanged(o.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmartCityField extends StatefulWidget {
  const _SmartCityField({
    required this.controller,
    required this.hint,
    this.label,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;

  @override
  State<_SmartCityField> createState() => _SmartCityFieldState();
}

class _SmartCityFieldState extends State<_SmartCityField> {
  Timer? _debounce;
  List<DestinationSuggestion> _suggestions = const [];
  bool _loading = false;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
      if (_focus.hasFocus && widget.controller.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: widget.controller.text.length,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final normalized = DestinationSearchService.normalizeQuery(raw);
    if (normalized.length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() => _loading = true);
    final snapshot = raw.trim();
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      final out = await DestinationSearchService.search(snapshot);
      if (!mounted || widget.controller.text.trim() != snapshot) return;
      setState(() {
        _loading = false;
        _suggestions = out;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onChanged,
          onTap: () {
            if (widget.controller.text.isEmpty) return;
            widget.controller.selection =
                TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
          },
          style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.96), fontSize: 14.5),
          cursorColor: HomeLuxuryPalette.accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.55)),
            filled: true,
            fillColor: HomeLuxuryPalette.bgTop.withOpacity(0.42),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.accent.withOpacity(0.55), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: HomeLuxuryPalette.accent.withOpacity(0.85),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hľadám…',
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ] else if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeLuxuryPalette.border),
              color: HomeLuxuryPalette.bgTop.withOpacity(0.36),
            ),
            child: Column(
              children: [
                for (final suggestion in _suggestions)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        widget.controller.text = suggestion.displayName;
                        widget.controller.selection = TextSelection.collapsed(
                          offset: suggestion.displayName.length,
                        );
                        setState(() => _suggestions = const []);
                      },
                      splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 16, color: HomeLuxuryPalette.accent.withOpacity(0.82)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SuggestionText(
                                suggestion: suggestion,
                                query: widget.controller.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OurAirportsAirportField extends StatefulWidget {
  const _OurAirportsAirportField({
    required this.controller,
    required this.hint,
    required this.onAirportChanged,
    this.boundAirport,
    this.label,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final AirportRecord? boundAirport;
  final ValueChanged<AirportRecord?> onAirportChanged;

  @override
  State<_OurAirportsAirportField> createState() => _OurAirportsAirportFieldState();
}

class _OurAirportsAirportFieldState extends State<_OurAirportsAirportField> {
  Timer? _debounce;
  List<AirportRecord> _suggestions = const [];
  bool _loading = false;
  late final FocusNode _focus;
  bool _suppressChanged = false;

  bool _textMatchesBound() {
    final b = widget.boundAirport;
    if (b == null) return false;
    return widget.controller.text.trim() == b.displayTitle;
  }

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
      if (_focus.hasFocus && widget.controller.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: widget.controller.text.length,
          );
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AirportRepository.ensureLoaded().then((_) {
        if (mounted && AirportRepository.loadFailureMessage != null) {
          setState(() {});
        }
      });
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String raw) {
    if (_suppressChanged) return;
    if (!_textMatchesBound()) {
      widget.onAirportChanged(null);
    }
    _debounce?.cancel();
    final normalized = DestinationSearchService.normalizeQuery(raw);
    if (normalized.length < 2) {
      setState(() {
        _loading = false;
        _suggestions = const [];
      });
      return;
    }
    setState(() => _loading = true);
    final snapshot = raw.trim();
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      var results = const <AirportRecord>[];
      try {
        await AirportRepository.ensureLoaded();
        if (!mounted) return;
        if (widget.controller.text.trim() != snapshot) {
          setState(() => _loading = false);
          return;
        }
        results = await AirportRepository.search(snapshot, limit: 14);
      } catch (e, st) {
        debugPrint('[AIRPORT_FIELD] search pipeline failed: $e\n$st');
        results = const [];
      }
      if (!mounted) return;
      if (widget.controller.text.trim() != snapshot) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _suggestions = results;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onChanged,
          onTap: () {
            if (widget.controller.text.isEmpty) return;
            widget.controller.selection =
                TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
          },
          style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.96), fontSize: 14.5),
          cursorColor: HomeLuxuryPalette.accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.55)),
            filled: true,
            fillColor: HomeLuxuryPalette.bgTop.withOpacity(0.42),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: HomeLuxuryPalette.accent.withOpacity(0.55), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: HomeLuxuryPalette.accent.withOpacity(0.85),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hľadám letiská…',
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ] else if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeLuxuryPalette.border),
              color: HomeLuxuryPalette.bgTop.withOpacity(0.36),
            ),
            child: Column(
              children: [
                for (final a in _suggestions)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        _suppressChanged = true;
                        widget.controller.text = a.displayTitle;
                        widget.controller.selection =
                            TextSelection.collapsed(offset: a.displayTitle.length);
                        widget.onAirportChanged(a);
                        setState(() => _suggestions = const []);
                        FocusScope.of(context).unfocus();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _suppressChanged = false;
                        });
                      },
                      splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.local_airport_rounded,
                                size: 16, color: HomeLuxuryPalette.accent.withOpacity(0.82)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.displayTitle,
                                    style: TextStyle(
                                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                                      fontSize: 13.6,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    a.displaySubtitle,
                                    style: TextStyle(
                                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.8),
                                      fontSize: 11.8,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (AirportRepository.loadFailureMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            AirportRepository.loadFailureMessage!,
            style: TextStyle(
              color: const Color(0xFFE8A598).withOpacity(0.95),
              fontSize: 12.6,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _LuxuryActionLink extends StatelessWidget {
  const _LuxuryActionLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.92),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationThickness: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoArrivalEstimateCard extends StatelessWidget {
  const _AutoArrivalEstimateCard({
    required this.title,
    required this.formattedDateTime,
    this.arrivalLocalCity,
    required this.subtitle,
    this.warnings = const [],
  });

  final String title;
  final String formattedDateTime;
  /// Mesto príchodového letiska; ak null/prázdne — „destinácii“.
  final String? arrivalLocalCity;
  final String subtitle;
  final List<String> warnings;

  String get _localTimePhrase {
    final c = arrivalLocalCity?.trim();
    if (c != null && c.isNotEmpty) return 'miestneho času v $c';
    return 'miestneho času v destinácii';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeLuxuryPalette.accent.withOpacity(0.28)),
        color: HomeLuxuryPalette.bgTop.withOpacity(0.38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
              fontSize: 11.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$formattedDateTime $_localTimePhrase',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.72),
              fontSize: 11.2,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
          for (final w in warnings) ...[
            const SizedBox(height: 6),
            Text(
              w,
              style: TextStyle(
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransportDetailsCard extends StatelessWidget {
  const _TransportDetailsCard({
    required this.transport,
    required this.planeOutboundOriginController,
    required this.planeOutboundDestController,
    required this.planeReturnOriginController,
    required this.planeReturnDestController,
    required this.roadOutboundOriginController,
    required this.roadReturnOriginController,
    required this.outboundDeparture,
    required this.outboundArrival,
    required this.returnDeparture,
    required this.returnArrival,
    required this.outboundArrivalSource,
    required this.returnArrivalSource,
    required this.manualUiOutboundArrival,
    required this.manualUiReturnArrival,
    required this.optionalOutboundArrivalOpen,
    required this.optionalReturnArrivalOpen,
    required this.formatDateTime,
    required this.onRequestManualOutboundArrival,
    required this.onRequestManualReturnArrival,
    required this.onToggleOptionalOutboundArrival,
    required this.onToggleOptionalReturnArrival,
    required this.onPickOutboundDeparture,
    required this.onPickOutboundArrival,
    required this.onPickReturnDeparture,
    required this.onPickReturnArrival,
    required this.onClearOutboundDeparture,
    required this.onClearOutboundArrival,
    required this.onClearReturnDeparture,
    required this.onClearReturnArrival,
    this.airportOutboundDep,
    this.airportOutboundArr,
    this.airportReturnDep,
    this.airportReturnArr,
    required this.onOutboundDepAirportChanged,
    required this.onOutboundArrAirportChanged,
    required this.onReturnDepAirportChanged,
    required this.onReturnArrAirportChanged,
    this.outboundFlightEstimate,
    this.returnFlightEstimate,
    required this.formatBlockDurationSk,
    required this.outboundPlaneCannotEstimate,
    required this.returnPlaneCannotEstimate,
    this.tripDestinationCityLabel,
  });

  final TripTransport transport;
  final TextEditingController planeOutboundOriginController;
  final TextEditingController planeOutboundDestController;
  final TextEditingController planeReturnOriginController;
  final TextEditingController planeReturnDestController;
  final TextEditingController roadOutboundOriginController;
  final TextEditingController roadReturnOriginController;
  final DateTime? outboundDeparture;
  final DateTime? outboundArrival;
  final DateTime? returnDeparture;
  final DateTime? returnArrival;
  final TripArrivalTimeSource outboundArrivalSource;
  final TripArrivalTimeSource returnArrivalSource;
  final bool manualUiOutboundArrival;
  final bool manualUiReturnArrival;
  final bool optionalOutboundArrivalOpen;
  final bool optionalReturnArrivalOpen;
  final String Function(DateTime) formatDateTime;
  final String Function(int totalMinutes) formatBlockDurationSk;
  final AirportRecord? airportOutboundDep;
  final AirportRecord? airportOutboundArr;
  final AirportRecord? airportReturnDep;
  final AirportRecord? airportReturnArr;
  final ValueChanged<AirportRecord?> onOutboundDepAirportChanged;
  final ValueChanged<AirportRecord?> onOutboundArrAirportChanged;
  final ValueChanged<AirportRecord?> onReturnDepAirportChanged;
  final ValueChanged<AirportRecord?> onReturnArrAirportChanged;
  final FlightArrivalEstimate? outboundFlightEstimate;
  final FlightArrivalEstimate? returnFlightEstimate;
  final bool outboundPlaneCannotEstimate;
  final bool returnPlaneCannotEstimate;
  final String? tripDestinationCityLabel;
  final VoidCallback onRequestManualOutboundArrival;
  final VoidCallback onRequestManualReturnArrival;
  final VoidCallback onToggleOptionalOutboundArrival;
  final VoidCallback onToggleOptionalReturnArrival;
  final VoidCallback onPickOutboundDeparture;
  final VoidCallback onPickOutboundArrival;
  final VoidCallback onPickReturnDeparture;
  final VoidCallback onPickReturnArrival;
  final VoidCallback onClearOutboundDeparture;
  final VoidCallback onClearOutboundArrival;
  final VoidCallback onClearReturnDeparture;
  final VoidCallback onClearReturnArrival;

  bool get _roadLike =>
      transport == TripTransport.car ||
      transport == TripTransport.train ||
      transport == TripTransport.bus;

  String get _sectionBlurb {
    switch (transport) {
      case TripTransport.plane:
        return 'Zadaj odlety; prílet dopočítame po zadaní letísk a času odletu. Spiatočný let rovnako.';
      case TripTransport.car:
        return 'Odchody stačia. Príchod z trasy dopočítame automaticky (zatiaľ orientačne).';
      case TripTransport.train:
      case TripTransport.bus:
        return 'Odchody sú povinné. Príchody sú voliteľné — rozšíriš ich len keď treba.';
    }
  }

  bool _showPlaneManualOutboundArrival() => manualUiOutboundArrival;

  bool _showPlaneManualReturnArrival() => manualUiReturnArrival;

  bool _showRoadOutboundArrivalRow() {
    if (transport == TripTransport.train || transport == TripTransport.bus) {
      return optionalOutboundArrivalOpen;
    }
    if (transport == TripTransport.car) {
      return manualUiOutboundArrival ||
          (outboundArrival != null && outboundArrivalSource == TripArrivalTimeSource.manual);
    }
    return false;
  }

  bool _showRoadReturnArrivalRow() {
    if (transport == TripTransport.train || transport == TripTransport.bus) {
      return optionalReturnArrivalOpen;
    }
    if (transport == TripTransport.car) {
      return manualUiReturnArrival ||
          (returnArrival != null && returnArrivalSource == TripArrivalTimeSource.manual);
    }
    return false;
  }

  Widget _mutedLine(String text) {
    return Text(
      text,
      style: TextStyle(
        color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
        fontSize: 11.8,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  List<Widget> _planeOutboundArrivalArea() {
    if (_showPlaneManualOutboundArrival()) {
      return [
        const SizedBox(height: 8),
        _TravelDateTimeRow(
          label: 'Prílet',
          value: outboundArrival != null ? formatDateTime(outboundArrival!) : null,
          onTap: onPickOutboundArrival,
          onClear: outboundArrival != null ? onClearOutboundArrival : null,
        ),
      ];
    }
    if (outboundDeparture == null) {
      return [
        const SizedBox(height: 8),
        _mutedLine('Najprv vyber dátum a čas odletu.'),
      ];
    }
    final o = planeOutboundOriginController.text.trim();
    final d = planeOutboundDestController.text.trim();
    if (o.isEmpty || d.isEmpty) {
      return [
        const SizedBox(height: 8),
        _mutedLine('Pre odhad príletu doplň obe polia (odkiaľ letíš / kam prilietaš).'),
      ];
    }
    if (outboundPlaneCannotEstimate) {
      return [
        const SizedBox(height: 8),
        _mutedLine(
          'Prílet zatiaľ nevieme odhadnúť. Vyber presnejšie letisko alebo zadaj prílet manuálne.',
        ),
        _LuxuryActionLink(label: 'Upraviť prílet manuálne', onTap: onRequestManualOutboundArrival),
      ];
    }
    if (outboundFlightEstimate != null &&
        outboundArrival != null &&
        outboundArrivalSource == TripArrivalTimeSource.autoEstimated) {
      final fe = outboundFlightEstimate!;
      final warns = <String>[];
      if (fe.duration.warningText != null) warns.add(fe.duration.warningText!);
      if (fe.extraWarningSk != null) warns.add(fe.extraWarningSk!);
      return [
        const SizedBox(height: 10),
        _AutoArrivalEstimateCard(
          title: 'Odhadovaný prílet',
          formattedDateTime: formatDateTime(outboundArrival!),
          arrivalLocalCity: airportOutboundArr?.city ?? tripDestinationCityLabel,
          subtitle:
              'Približný čas letu: ${formatBlockDurationSk(fe.duration.estimatedDurationMinutes)}',
          warnings: warns,
        ),
        _LuxuryActionLink(label: 'Upraviť prílet manuálne', onTap: onRequestManualOutboundArrival),
      ];
    }
    return [
      const SizedBox(height: 8),
      _mutedLine('Odhad príletu sa dopočíta po výbere letísk a odletu.'),
    ];
  }

  List<Widget> _planeReturnArrivalArea() {
    if (_showPlaneManualReturnArrival()) {
      return [
        const SizedBox(height: 8),
        _TravelDateTimeRow(
          label: 'Prílet',
          value: returnArrival != null ? formatDateTime(returnArrival!) : null,
          onTap: onPickReturnArrival,
          onClear: returnArrival != null ? onClearReturnArrival : null,
        ),
      ];
    }
    if (returnDeparture == null) {
      return [
        const SizedBox(height: 8),
        _mutedLine('Najprv vyber spiatočný odlet.'),
      ];
    }
    final o = planeReturnOriginController.text.trim();
    final d = planeReturnDestController.text.trim();
    if (o.isEmpty || d.isEmpty) {
      return [
        const SizedBox(height: 8),
        _mutedLine('Pre odhad spiatočného príletu doplň letiská spiatočnej trasy.'),
      ];
    }
    if (returnPlaneCannotEstimate) {
      return [
        const SizedBox(height: 8),
        _mutedLine(
          'Prílet zatiaľ nevieme odhadnúť. Vyber presnejšie letisko alebo zadaj prílet manuálne.',
        ),
        _LuxuryActionLink(label: 'Upraviť prílet manuálne', onTap: onRequestManualReturnArrival),
      ];
    }
    if (returnFlightEstimate != null &&
        returnArrival != null &&
        returnArrivalSource == TripArrivalTimeSource.autoEstimated) {
      final fe = returnFlightEstimate!;
      final warns = <String>[];
      if (fe.duration.warningText != null) warns.add(fe.duration.warningText!);
      if (fe.extraWarningSk != null) warns.add(fe.extraWarningSk!);
      return [
        const SizedBox(height: 10),
        _AutoArrivalEstimateCard(
          title: 'Odhadovaný prílet',
          formattedDateTime: formatDateTime(returnArrival!),
          arrivalLocalCity: airportReturnArr?.city ?? tripDestinationCityLabel,
          subtitle:
              'Približný čas letu: ${formatBlockDurationSk(fe.duration.estimatedDurationMinutes)}',
          warnings: warns,
        ),
        _LuxuryActionLink(label: 'Upraviť prílet manuálne', onTap: onRequestManualReturnArrival),
      ];
    }
    return [
      const SizedBox(height: 8),
      _mutedLine('Odhad spiatočného príletu sa dopočíta po údajoch vyššie.'),
    ];
  }

  List<Widget> _roadOutboundArrivalArea() {
    final rows = <Widget>[];
    if (transport == TripTransport.car) {
      rows.add(const SizedBox(height: 8));
      rows.add(
        Text(
          'Príchod dopočítame automaticky',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.88),
            fontSize: 12.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (!_showRoadOutboundArrivalRow()) {
        rows.add(
          _LuxuryActionLink(
            label: 'Upraviť príchod manuálne',
            onTap: onRequestManualOutboundArrival,
          ),
        );
      }
    } else {
      rows.add(const SizedBox(height: 6));
      rows.add(
        _LuxuryActionLink(
          label: optionalOutboundArrivalOpen
              ? 'Skryť voliteľný príchod tam'
              : 'Doplniť príchod tam (voliteľné)',
          onTap: onToggleOptionalOutboundArrival,
        ),
      );
    }
    if (_showRoadOutboundArrivalRow()) {
      rows.add(const SizedBox(height: 8));
      rows.add(
        _TravelDateTimeRow(
          label: 'Príchod',
          value: outboundArrival != null ? formatDateTime(outboundArrival!) : null,
          onTap: onPickOutboundArrival,
          onClear: outboundArrival != null ? onClearOutboundArrival : null,
        ),
      );
    }
    return rows;
  }

  List<Widget> _roadReturnArrivalArea() {
    final rows = <Widget>[];
    if (transport == TripTransport.car) {
      rows.add(const SizedBox(height: 8));
      rows.add(
        Text(
          'Príchod dopočítame automaticky',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.88),
            fontSize: 12.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (!_showRoadReturnArrivalRow()) {
        rows.add(
          _LuxuryActionLink(
            label: 'Upraviť príchod manuálne',
            onTap: onRequestManualReturnArrival,
          ),
        );
      }
    } else {
      rows.add(const SizedBox(height: 6));
      rows.add(
        _LuxuryActionLink(
          label: optionalReturnArrivalOpen
              ? 'Skryť voliteľný príchod späť'
              : 'Doplniť príchod späť (voliteľné)',
          onTap: onToggleOptionalReturnArrival,
        ),
      );
    }
    if (_showRoadReturnArrivalRow()) {
      rows.add(const SizedBox(height: 8));
      rows.add(
        _TravelDateTimeRow(
          label: 'Príchod',
          value: returnArrival != null ? formatDateTime(returnArrival!) : null,
          onTap: onPickReturnArrival,
          onClear: returnArrival != null ? onClearReturnArrival : null,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final sectionTitle = transport == TripTransport.plane ? 'Detaily letu' : 'Detaily cesty';
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionTitle,
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _sectionBlurb,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
              fontSize: 11.8,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Cesta tam',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (transport == TripTransport.plane) ...[
            _OurAirportsAirportField(
              label: 'Odkiaľ letíš',
              hint: 'IATA, mesto alebo názov letiska',
              controller: planeOutboundOriginController,
              boundAirport: airportOutboundDep,
              onAirportChanged: onOutboundDepAirportChanged,
            ),
            const SizedBox(height: 12),
            _OurAirportsAirportField(
              label: 'Kam prilietaš',
              hint: 'Letisko príchodu (nie mesto pobytu)',
              controller: planeOutboundDestController,
              boundAirport: airportOutboundArr,
              onAirportChanged: onOutboundArrAirportChanged,
            ),
            const SizedBox(height: 12),
            _TravelDateTimeRow(
              label: 'Odlet',
              value: outboundDeparture != null ? formatDateTime(outboundDeparture!) : null,
              onTap: onPickOutboundDeparture,
              onClear: outboundDeparture != null ? onClearOutboundDeparture : null,
            ),
            ..._planeOutboundArrivalArea(),
          ] else if (_roadLike) ...[
            _SmartCityField(
              label: 'Odkiaľ vyrážaš',
              hint: 'Štart cesty',
              controller: roadOutboundOriginController,
            ),
            const SizedBox(height: 12),
            _TravelDateTimeRow(
              label: 'Odchod',
              value: outboundDeparture != null ? formatDateTime(outboundDeparture!) : null,
              onTap: onPickOutboundDeparture,
              onClear: outboundDeparture != null ? onClearOutboundDeparture : null,
            ),
            ..._roadOutboundArrivalArea(),
          ],
          const SizedBox(height: 16),
          Text(
            'Cesta späť',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (transport == TripTransport.plane) ...[
            _OurAirportsAirportField(
              label: 'Spiatočný odlet — odkiaľ',
              hint: 'Letisko odletu späť (podľa spiatočnej trasy)',
              controller: planeReturnOriginController,
              boundAirport: airportReturnDep,
              onAirportChanged: onReturnDepAirportChanged,
            ),
            const SizedBox(height: 12),
            _OurAirportsAirportField(
              label: 'Kam prilietaš (domov)',
              hint: 'Letisko príchodu domov',
              controller: planeReturnDestController,
              boundAirport: airportReturnArr,
              onAirportChanged: onReturnArrAirportChanged,
            ),
            const SizedBox(height: 12),
            _TravelDateTimeRow(
              label: 'Odlet',
              value: returnDeparture != null ? formatDateTime(returnDeparture!) : null,
              onTap: onPickReturnDeparture,
              onClear: returnDeparture != null ? onClearReturnDeparture : null,
            ),
            ..._planeReturnArrivalArea(),
          ] else if (_roadLike) ...[
            _SmartCityField(
              label: 'Odkiaľ vyrážaš',
              hint: 'Štart spiatočnej cesty',
              controller: roadReturnOriginController,
            ),
            const SizedBox(height: 12),
            _TravelDateTimeRow(
              label: 'Odchod',
              value: returnDeparture != null ? formatDateTime(returnDeparture!) : null,
              onTap: onPickReturnDeparture,
              onClear: returnDeparture != null ? onClearReturnDeparture : null,
            ),
            ..._roadReturnArrivalArea(),
          ],
        ],
      ),
    );
  }
}

class _TravelStyleSection extends StatelessWidget {
  const _TravelStyleSection({
    required this.selected,
    required this.onToggle,
  });

  final Set<TripTravelStyle> selected;
  final ValueChanged<TripTravelStyle> onToggle;

  static const _options = <(TripTravelStyle, String)>[
    (TripTravelStyle.comfy, 'Pohodlne'),
    (TripTravelStyle.elegant, 'Elegantnejšie'),
    (TripTravelStyle.subtle, 'Nenápadne'),
    (TripTravelStyle.stylish, 'Štýlovo'),
  ];

  @override
  Widget build(BuildContext context) {
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ako sa chceš cítiť?',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Môžeš kombinovať (napr. pohodlne + nenápadne). Ovplyvní smer outfitov a výber obuvi.',
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                _ChoiceChip(
                  label: o.$2,
                  selected: selected.contains(o.$1),
                  onTap: () => onToggle(o.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return HomeGlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Čo plánuješ robiť?',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.96), fontSize: 14),
            cursorColor: HomeLuxuryPalette.accent,
            decoration: InputDecoration(
              hintText:
                  'Napr. jeden večer reštaurácia, jeden deň pracovné stretnutie, veľa chodenia…',
              hintStyle: TextStyle(color: HomeLuxuryPalette.textSecondary.withOpacity(0.65)),
              filled: true,
              fillColor: HomeLuxuryPalette.bgTop.withOpacity(0.42),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: HomeLuxuryPalette.accent.withOpacity(0.55), width: 1.2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: HomeLuxuryPalette.accent.withOpacity(0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? HomeLuxuryPalette.accent.withOpacity(0.55)
                  : HomeLuxuryPalette.border,
              width: selected ? 1.1 : 0.9,
            ),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      HomeLuxuryPalette.accent.withOpacity(0.18),
                      HomeLuxuryPalette.accent.withOpacity(0.06),
                    ],
                  )
                : null,
            color: selected ? null : HomeLuxuryPalette.bgTop.withOpacity(0.28),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(selected ? 0.98 : 0.82),
              fontSize: 12.8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldCta extends StatelessWidget {
  const _GoldCta({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HomeLuxuryPalette.accent.withOpacity(0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: HomeLuxuryPalette.accent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.black.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Navrhnúť balenie',
                  style: TextStyle(
                    color: const Color(0xFF191512),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Počasie pri „Na cestu tam/späť“ (bez samostatnej sekcie počasia).
class _InlineTravelRouteWeather extends StatelessWidget {
  const _InlineTravelRouteWeather({required this.route});

  final TripWeatherRoutePreview route;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          route.travelDateLabelSk,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          route.routeTitleSk,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: HomeLuxuryPalette.accent.withOpacity(0.92),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              LuxuryWeatherEmoji.forConditionSk(route.conditionFromSk),
              style: const TextStyle(fontSize: 17, height: 1),
            ),
            const SizedBox(width: 4),
            Text(
              '${route.tempFromC}°',
              style: TextStyle(
                color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '→',
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.75),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              LuxuryWeatherEmoji.forConditionSk(route.conditionToSk),
              style: const TextStyle(fontSize: 17, height: 1),
            ),
            const SizedBox(width: 4),
            Text(
              '${route.tempToC}°',
              style: TextStyle(
                color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaceholderResultView extends StatelessWidget {
  const _PlaceholderResultView({
    required this.result,
    required this.onEdit,
  });

  final TripPackingPlaceholderResult result;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Poradie sekcií (nemenit): 1 Do batožiny → 2 Na cestu tam → 3 Outfity v destinácii → 4 Na cestu späť → 5 Čo ti možno chýba.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Do batožiny',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        HomeGlassSurface(
          borderRadius: 18,
          blurSigma: 14,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: result.luggageItems.isEmpty
              ? Text(
                  'Žiadne kúsky do batožiny zo šatníka. Pridaj fotky kúskov alebo doplníme odporúčania podľa výletu.',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                    fontSize: 12.8,
                    height: 1.38,
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.luggageItems.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.65,
                  ),
                  itemBuilder: (_, i) => _PieceTile(piece: result.luggageItems[i]),
                ),
        ),
        const SizedBox(height: 22),
        Text(
          'Na cestu tam',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        HomeGlassSurface(
          borderRadius: 18,
          blurSigma: 14,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.weather.outboundRoute != null) ...[
                _InlineTravelRouteWeather(route: result.weather.outboundRoute!),
                const SizedBox(height: 12),
              ],
              result.travelOutboundPieces.isEmpty
                  ? Text(
                      'Žiadne vybrané kúsky na cestu zo šatníka. Skontroluj sekciu Do batožiny vyššie alebo šatník.',
                      style: TextStyle(
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                        fontSize: 12.8,
                        height: 1.38,
                      ),
                    )
                  : SizedBox(
                      height: 124,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: result.travelOutboundPieces.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _PieceTile(piece: result.travelOutboundPieces[i]),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Outfity v destinácii',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (final o in result.destinationDailyPlans) ...[
          HomeGlassSurface(
            borderRadius: 16,
            blurSigma: 12,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.titleSk,
                  style: TextStyle(
                    color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (o.weatherPlaceSk != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    o.weatherPlaceSk!,
                    style: TextStyle(
                      color: HomeLuxuryPalette.accent.withOpacity(0.92),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
                if (o.weatherHighC != null &&
                    o.weatherLowC != null &&
                    o.weatherConditionSk != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        LuxuryWeatherEmoji.forConditionSk(o.weatherConditionSk!),
                        style: const TextStyle(fontSize: 17, height: 1),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${o.weatherHighC}°',
                        style: TextStyle(
                          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '/',
                          style: TextStyle(
                            color: HomeLuxuryPalette.textSecondary.withOpacity(0.75),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${o.weatherLowC}°',
                        style: TextStyle(
                          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  o.summarySk,
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
                if (o.pieces.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 118,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: o.pieces.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _PieceTile(piece: o.pieces[i], compact: true),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 22),
        Text(
          'Na cestu späť',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        HomeGlassSurface(
          borderRadius: 18,
          blurSigma: 14,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.weather.returnRoute != null) ...[
                _InlineTravelRouteWeather(route: result.weather.returnRoute!),
                const SizedBox(height: 12),
              ],
              result.travelReturnPieces.isEmpty
                  ? (!result.hadWardrobeCandidates
                      ? Text(
                          'Žiadne vybrané kúsky na návrat zo šatníka.',
                          style: TextStyle(
                            color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                            fontSize: 12.8,
                            height: 1.38,
                          ),
                        )
                      : const SizedBox.shrink())
                  : SizedBox(
                      height: 124,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: result.travelReturnPieces.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _PieceTile(piece: result.travelReturnPieces[i]),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Čo ti možno chýba',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (result.missingItems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Podľa zadaného výletu nemám ďalšiu zjavnú medzeru v základnom vybavení.',
              style: TextStyle(
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.78),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        for (final m in result.missingItems) ...[
          HomeGlassSurface(
            borderRadius: 14,
            blurSigma: 10,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.nameSk,
                        style: TextStyle(
                          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                          fontSize: 13.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.reasonSk,
                        style: TextStyle(
                          color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                          fontSize: 12.2,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: HomeLuxuryPalette.accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: HomeLuxuryPalette.accent.withOpacity(0.35)),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: HomeLuxuryPalette.accent.withOpacity(0.92),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.92),
          ),
          child: const Text(
            'Upraviť vstup',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _PieceTile extends StatefulWidget {
  const _PieceTile({
    required this.piece,
    this.compact = false,
  });

  final TripWardrobePiece piece;
  final bool compact;

  @override
  State<_PieceTile> createState() => _PieceTileState();
}

class _PieceTileState extends State<_PieceTile> {
  int _urlIndex = 0;

  List<String> get _urls {
    final fromPiece = widget.piece.effectiveImageUrls;
    if (fromPiece.isNotEmpty) return fromPiece;
    final p = widget.piece.imageUrl?.trim();
    if (p != null && p.isNotEmpty) return [p];
    return const <String>[];
  }

  @override
  void didUpdateWidget(covariant _PieceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) _urlIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final size = compact ? 64.0 : 74.0;
    final labelHeight = compact ? 30.0 : 32.0;
    final urls = _urls;
    final safeIdx = urls.isEmpty ? 0 : _urlIndex.clamp(0, urls.length - 1);

    Widget imageChild;
    if (urls.isEmpty) {
      imageChild = Icon(
        Icons.image_not_supported_outlined,
        color: HomeLuxuryPalette.textSecondary.withOpacity(0.45),
        size: compact ? 28 : 32,
      );
    } else {
      imageChild = Image.network(
        urls[safeIdx],
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          if (_urlIndex < urls.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _urlIndex++);
            });
          }
          return Icon(
            Icons.broken_image_outlined,
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.5),
            size: compact ? 28 : 32,
          );
        },
      );
    }

    return SizedBox(
      width: compact ? 72 : 86,
      height: size + 6 + labelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: HomeLuxuryPalette.bgTop.withOpacity(0.35),
              border: Border.all(color: HomeLuxuryPalette.accent.withOpacity(0.28)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageChild,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: labelHeight,
            child: Text(
              widget.piece.nameSk,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HomeLuxuryPalette.textPrimary.withOpacity(0.9),
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
