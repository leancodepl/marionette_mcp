package com.example.counter

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

// A full native screen outside Flutter. Returns the typed text to the
// Flutter screen that opened it.
class NativeFormActivity : Activity() {
    companion object {
        const val EXTRA_TEXT = "text"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (24 * resources.displayMetrics.density).toInt()
        val field = EditText(this).apply {
            id = R.id.native_form_name
            hint = "Native name"
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding * 3, padding, padding)
            addView(TextView(this@NativeFormActivity).apply {
                id = R.id.native_form_title
                text = "Native screen"
                textSize = 24f
            })
            addView(field, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(Button(this@NativeFormActivity).apply {
                id = R.id.native_form_back
                text = "Back to Flutter"
                setOnClickListener {
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_TEXT, field.text.toString()))
                    finish()
                }
            })
        }
        setContentView(layout)
    }
}
