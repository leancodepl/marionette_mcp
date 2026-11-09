package com.example.counter

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val channelName = "marionette_example/native_controls"

class NativeControlsViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeControlsPlatformView(context, messenger)
    }
}

private class NativeControlsPlatformView(
    context: Context,
    messenger: BinaryMessenger,
) : PlatformView {
    private val channel = MethodChannel(messenger, channelName)

    private val root: LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
            setBackgroundColor(Color.parseColor("#E8F5E9"))

            addView(
                TextView(context).apply {
                    text = "Native label"
                    contentDescription = "native_label"
                    textSize = 18f
                },
            )

            addView(
                EditText(context).apply {
                    hint = "Type here (native)"
                    contentDescription = "native_input"
                    setTextColor(Color.BLACK)
                },
            )

            addView(
                Button(context).apply {
                    text = "Tap me (native)"
                    contentDescription = "native_button"
                    setOnClickListener {
                        channel.invokeMethod("nativeButtonTapped", null)
                    }
                },
            )
        }

    override fun getView(): View = root

    override fun dispose() {}
}
