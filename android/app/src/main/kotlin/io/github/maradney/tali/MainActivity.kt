package io.github.maradney.tali

import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app, plus one channel Flutter cannot express on its own.
 *
 * SystemChrome.setPreferredOrientations says which orientations are *allowed*,
 * and Android still honours the user's rotation lock on top of that. With the
 * lock on, fullscreen therefore picks one landscape orientation and stays
 * there - turn the phone end over end and the picture is upside down.
 *
 * SCREEN_ORIENTATION_SENSOR_LANDSCAPE follows the accelerometer regardless of
 * the lock, between the two landscape orientations only, which is what every
 * video player does. There is no upside-down state to land in: both are the
 * right way up from where the viewer is sitting.
 *
 * This is the only writer of the activity's requested orientation. Flutter's
 * own setPreferredOrientations calls the same Android setter underneath, so
 * the Dart side deliberately stops using it on Android for fullscreen - two
 * callers on one property resolve by whichever ran last, which is a timing
 * bug waiting to happen.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "io.github.maradney.tali/orientation"
        const val METHOD_APPLY = "apply"
        const val ARG_MODE = "mode"

        /** Follow the sensor between the two landscape orientations. */
        const val MODE_SENSOR_LANDSCAPE = "sensorLandscape"

        /** Hand orientation back to the system. */
        const val MODE_UNSPECIFIED = "unspecified"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != METHOD_APPLY) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val mode = call.argument<String>(ARG_MODE)
                requestedOrientation = when (mode) {
                    MODE_SENSOR_LANDSCAPE ->
                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    MODE_UNSPECIFIED ->
                        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    // An unknown mode releases rather than holds: being stuck
                    // in an orientation is worse than not rotating.
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
                result.success(null)
            }
    }
}
