import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

BuildContext? get rootContext => rootNavigatorKey.currentContext;
NavigatorState? get rootNavigator => rootNavigatorKey.currentState;
