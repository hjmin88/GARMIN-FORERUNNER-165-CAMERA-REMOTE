package com.example.cameraremote

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var statusAccessibility: TextView
    private lateinit var statusConnectIQ: TextView
    private lateinit var btnEnableAccessibility: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusAccessibility = findViewById(R.id.statusAccessibility)
        statusConnectIQ = findViewById(R.id.statusConnectIQ)
        btnEnableAccessibility = findViewById(R.id.btnEnableAccessibility)

        btnEnableAccessibility.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        // Start the ConnectIQ foreground service
        val serviceIntent = Intent(this, ConnectIQReceiver::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    override fun onResume() {
        super.onResume()
        updateStatus()
    }

    private fun updateStatus() {
        val a11yRunning = ShutterAccessibilityService.instance != null
        val ciqRunning = ConnectIQReceiver.instance != null

        if (a11yRunning) {
            statusAccessibility.text = "Accessibility Service: ENABLED"
            statusAccessibility.setTextColor(0xFF4CAF50.toInt())
            btnEnableAccessibility.visibility = View.GONE
        } else {
            statusAccessibility.text = "Accessibility Service: DISABLED"
            statusAccessibility.setTextColor(0xFFF44336.toInt())
            btnEnableAccessibility.visibility = View.VISIBLE
        }

        if (ciqRunning) {
            statusConnectIQ.text = "Connect IQ Listener: RUNNING"
            statusConnectIQ.setTextColor(0xFF4CAF50.toInt())
        } else {
            statusConnectIQ.text = "Connect IQ Listener: STOPPED"
            statusConnectIQ.setTextColor(0xFFF44336.toInt())
        }
    }
}
