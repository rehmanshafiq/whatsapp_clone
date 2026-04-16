import 'package:flutter/material.dart';

/// [MaterialApp.scaffoldMessengerKey] so call flows can surface SnackBars
/// from non-widget code (e.g. call rejected while overlay closes).
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
