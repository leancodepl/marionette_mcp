package com.example.counter

import android.app.AlertDialog
import android.content.Intent
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) because local_auth needs a
// FragmentActivity for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private var pendingNativeScreen: MethodChannel.Result? = null

    private val nativeScreen =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
            val text = activityResult.data?.getStringExtra(NativeFormActivity.EXTRA_TEXT)
            pendingNativeScreen?.success(text ?: "cancelled")
            pendingNativeScreen = null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "marionette-demo-native-controls",
                NativeControlsViewFactory(messenger),
            )

        // Native UI that the native lane must handle on its own (§9, §10, §11).
        MethodChannel(messenger, "marionette-demo/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "showAlert" -> showAlert(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("message") ?: "",
                    result,
                )
                "showToast" -> {
                    Toast.makeText(this, call.argument<String>("text") ?: "", Toast.LENGTH_LONG).show()
                    result.success(null)
                }
                "openNativeScreen" -> {
                    pendingNativeScreen = result
                    nativeScreen.launch(Intent(this, NativeFormActivity::class.java))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showAlert(title: String, message: String, result: MethodChannel.Result) {
        var answered = false
        fun answer(value: String) {
            if (answered) return
            answered = true
            result.success(value)
        }
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("OK") { _, _ -> answer("ok") }
            .setNegativeButton("Cancel") { _, _ -> answer("cancel") }
            .setOnDismissListener { answer("dismissed") }
            .show()
    }
}
