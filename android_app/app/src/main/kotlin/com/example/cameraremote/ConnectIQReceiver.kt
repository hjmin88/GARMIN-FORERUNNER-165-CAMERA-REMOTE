package com.example.cameraremote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice

class ConnectIQReceiver : Service() {

    companion object {
        private const val TAG = "ConnectIQReceiver"
        const val WATCH_APP_ID = "a3421fee-d289-106a-538c-b9547ab12095"
        private const val CHANNEL_ID = "camera_remote_channel"
        private const val NOTIFICATION_ID = 1

        @Volatile
        var instance: ConnectIQReceiver? = null
            private set
    }

    private var connectIQ: ConnectIQ? = null
    private var currentDevice: IQDevice? = null
    private val iqApp = IQApp(WATCH_APP_ID)
    private val bench = BenchSender({ connectIQ }, { currentDevice }) { updateNotification(it) }
    private val still by lazy {
        StillSender(this, { connectIQ }, { currentDevice }, bench.app) { updateNotification(it) }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Waiting for watch..."))
        initializeConnectIQ()
    }

    private fun initializeConnectIQ() {
        try {
            connectIQ = ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS)
            connectIQ?.initialize(this, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    Log.d(TAG, "Connect IQ SDK ready")
                    registerForDevices()
                }

                override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                    Log.e(TAG, "Connect IQ init error: $status")
                    updateNotification("Error: Connect IQ init failed")
                }

                override fun onSdkShutDown() {
                    Log.d(TAG, "Connect IQ SDK shut down")
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Connect IQ", e)
            updateNotification("Error: Garmin Connect not installed?")
        }
    }

    private fun registerForDevices() {
        val ciq = connectIQ ?: return

        try {
            val devices = ciq.knownDevices
            if (devices.isNullOrEmpty()) {
                Log.w(TAG, "No known Garmin devices")
                updateNotification("No paired Garmin devices found")
                return
            }

            for (device in devices) {
                // Register for connection state changes
                ciq.registerForDeviceEvents(device) { dev, status ->
                    Log.d(TAG, "Device '${dev.friendlyName}' status: $status")
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        currentDevice = dev
                        registerAppMessages(dev)
                        updateNotification("Connected: ${dev.friendlyName}")
                    } else {
                        if (currentDevice == dev) {
                            bench.stop("Bench stopped: watch disconnected")
                            currentDevice = null
                            updateNotification("Watch disconnected")
                        }
                    }
                }

                // Check if already connected
                val status = ciq.getDeviceStatus(device)
                if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                    currentDevice = device
                    registerAppMessages(device)
                    updateNotification("Connected: ${device.friendlyName}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering device events", e)
        }
    }

    private fun registerAppMessages(device: IQDevice) {
        try {
            connectIQ?.registerForAppEvents(device, iqApp) { _, _, messageData, _ ->
                handleMessage(messageData)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering app events", e)
        }
        try {
            connectIQ?.registerForAppEvents(device, bench.app) { _, _, messageData, _ ->
                val msg = messageData?.firstOrNull() as? Map<*, *>
                if (msg?.get("cmd") == "still") {
                    val id = (msg["id"] as? Number)?.toInt() ?: 0
                    still.onRequest(id)
                } else {
                    bench.onMessage(messageData)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering bench app events", e)
        }
    }

    private fun handleMessage(messageData: List<Any>?) {
        if (messageData.isNullOrEmpty()) return

        val first = messageData[0]
        if (first is Map<*, *>) {
            val cmd = first["cmd"] as? String
            Log.d(TAG, "Received command: $cmd")

            if (cmd == "shutter") {
                performShutter()
            }
        }
    }

    private fun performShutter() {
        val a11yService = ShutterAccessibilityService.instance
        if (a11yService == null) {
            Log.w(TAG, "Accessibility service not running")
            sendResponse("error")
            return
        }

        val success = a11yService.clickShutterButton()
        sendResponse(if (success) "ok" else "error")
    }

    private fun sendResponse(status: String) {
        val device = currentDevice ?: return
        val ciq = connectIQ ?: return

        try {
            val response = mapOf("status" to status)
            ciq.sendMessage(device, iqApp, listOf(response)) { _, _, msgStatus ->
                Log.d(TAG, "Response send status: $msgStatus")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending response to watch", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Camera Remote",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Garmin Camera Remote service status"
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Camera Remote")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(text))
        } catch (e: Exception) {
            Log.e(TAG, "Error updating notification", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        bench.stop("Bench stopped: service destroyed")
        try {
            connectIQ?.shutdown(this)
        } catch (e: Exception) {
            Log.e(TAG, "Error shutting down ConnectIQ", e)
        }
        connectIQ = null
        super.onDestroy()
    }
}
