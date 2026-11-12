package com.example.cameraremote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    private lateinit var statusAccessibility: TextView
    private lateinit var statusConnectIQ: TextView
    private lateinit var btnEnableAccessibility: Button
    private lateinit var statusPhotos: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusAccessibility = findViewById(R.id.statusAccessibility)
        statusConnectIQ = findViewById(R.id.statusConnectIQ)
        btnEnableAccessibility = findViewById(R.id.btnEnableAccessibility)
        statusPhotos = findViewById(R.id.statusPhotos)

        btnEnableAccessibility.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        requestRuntimePermissions()

        // Start the ConnectIQ foreground service
        val serviceIntent = Intent(this, ConnectIQReceiver::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    /** Photo access lets the watch show the shot; notifications show connection status. */
    private fun requestRuntimePermissions() {
        val wanted = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted += Manifest.permission.READ_MEDIA_IMAGES
            wanted += Manifest.permission.POST_NOTIFICATIONS
        } else {
            wanted += Manifest.permission.READ_EXTERNAL_STORAGE
        }
        val missing = wanted.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 1)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        updateStatus()
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

        val photoPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, photoPerm) == PackageManager.PERMISSION_GRANTED) {
            statusPhotos.text = "Photo on watch: ON"
            statusPhotos.setTextColor(0xFF4CAF50.toInt())
        } else {
            statusPhotos.text = "Photo on watch: OFF (allow Photos in app settings)"
            statusPhotos.setTextColor(0xFFF44336.toInt())
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
