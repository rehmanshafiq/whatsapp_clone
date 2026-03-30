package com.example.whatsapp_clone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Force plugin registration on this engine so audio plugins
        // are available even when launching with a cached/custom engine.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}
