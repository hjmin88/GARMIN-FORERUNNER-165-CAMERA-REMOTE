package com.example.cameraremote

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.provider.MediaStore
import android.graphics.Rect
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/** What happened when the watch asked for a shutter press. */
enum class ShutterResult { CLICKED, NOT_CAMERA, NOT_FOUND }

class ShutterAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "ShutterA11yService"

        @Volatile
        var instance: ShutterAccessibilityService? = null
            private set

        // Checked in addition to the apps that declare they take photos, in case a
        // camera app does not answer the intent query.
        private val KNOWN_CAMERA_PACKAGES = setOf(
            "com.sec.android.app.camera",          // Samsung
            "com.google.android.GoogleCamera",     // Pixel
            "com.android.camera",
            "com.android.camera2",
        )

        private val SHUTTER_KEYWORDS = listOf(
            "shutter", "capture", "take photo", "take picture",
            "photo", "record", "snap",
            "촬영", "사진 촬영", "셔터", "캡처", "녹화"
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Intentionally empty — this service acts on-demand only
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted")
    }

    /**
     * Finds and clicks the camera shutter button in the current foreground app.
     * Uses two strategies:
     *   1. Semantic: match content descriptions against known shutter keywords
     *   2. Heuristic: find the largest clickable element in the bottom half of the screen
     *
     * @return true if a button was found and clicked
     */
    fun clickShutterButton(): ShutterResult {
        val rootNode = rootInActiveWindow
        if (rootNode == null) {
            Log.w(TAG, "No active window root node")
            return ShutterResult.NOT_FOUND
        }

        try {
            // Only ever press buttons in a camera app. Both strategies below would
            // otherwise happily press "Send" or "Pay" in whatever app is in front.
            val pkg = rootNode.packageName?.toString()
            if (pkg == null || pkg !in cameraPackages()) {
                Log.w(TAG, "Foreground app $pkg is not a camera app; not pressing anything")
                return ShutterResult.NOT_CAMERA
            }

            // Strategy 1: Find by content description
            val byDescription = findByContentDescription(rootNode)
            if (byDescription != null) {
                Log.d(TAG, "Found shutter by description: '${byDescription.contentDescription}'")
                val clicked = byDescription.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                byDescription.recycle()
                return if (clicked) ShutterResult.CLICKED else ShutterResult.NOT_FOUND
            }

            // Strategy 2: Find largest clickable in bottom half
            val byHeuristic = findLargestClickableInBottomHalf(rootNode)
            if (byHeuristic != null) {
                Log.d(TAG, "Found shutter by heuristic (largest clickable in bottom half)")
                val clicked = byHeuristic.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                byHeuristic.recycle()
                return if (clicked) ShutterResult.CLICKED else ShutterResult.NOT_FOUND
            }

            Log.w(TAG, "Could not find shutter button")
            return ShutterResult.NOT_FOUND
        } finally {
            rootNode.recycle()
        }
    }

    /** Apps that say they take photos (needs the <queries> entries in the manifest). */
    private fun cameraPackages(): Set<String> {
        val pm = packageManager
        val found = listOf(MediaStore.ACTION_IMAGE_CAPTURE, MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            .flatMap { action -> pm.queryIntentActivities(Intent(action), 0) }
            .map { it.activityInfo.packageName }
        return KNOWN_CAMERA_PACKAGES + found
    }

    /**
     * DFS traversal looking for a clickable node whose content description
     * contains a known shutter-related keyword.
     */
    private fun findByContentDescription(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val desc = node.contentDescription?.toString()?.lowercase() ?: ""

        if (desc.isNotEmpty()) {
            for (keyword in SHUTTER_KEYWORDS) {
                if (desc.contains(keyword)) {
                    if (node.isClickable) {
                        return AccessibilityNodeInfo.obtain(node)
                    }
                    // Walk up to find nearest clickable ancestor
                    val clickableAncestor = findClickableAncestor(node)
                    if (clickableAncestor != null) {
                        return clickableAncestor
                    }
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findByContentDescription(child)
            child.recycle()
            if (result != null) {
                return result
            }
        }

        return null
    }

    private fun findClickableAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current = node.parent ?: return null
        while (true) {
            if (current.isClickable) {
                return current
            }
            val parent = current.parent
            current.recycle()
            current = parent ?: return null
        }
    }

    /**
     * Finds the largest clickable element whose center is in the bottom half of the screen.
     * Camera apps almost universally place a large shutter button at the bottom center.
     */
    private fun findLargestClickableInBottomHalf(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val screenBounds = Rect()
        root.getBoundsInScreen(screenBounds)
        val midY = screenBounds.centerY()

        var bestNode: AccessibilityNodeInfo? = null
        var bestArea = 0

        collectLargestClickable(root, midY, bestArea) { node, area ->
            bestNode?.recycle()
            bestNode = AccessibilityNodeInfo.obtain(node)
            bestArea = area
        }

        return bestNode
    }

    private fun collectLargestClickable(
        node: AccessibilityNodeInfo,
        midY: Int,
        currentBestArea: Int,
        onNewBest: (AccessibilityNodeInfo, Int) -> Unit
    ): Int {
        var best = currentBestArea

        if (node.isClickable && node.isVisibleToUser) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val centerY = bounds.centerY()

            if (centerY > midY) {
                val area = bounds.width() * bounds.height()
                if (area > best) {
                    onNewBest(node, area)
                    best = area
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            best = collectLargestClickable(child, midY, best, onNewBest)
            child.recycle()
        }

        return best
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "Accessibility service destroyed")
        super.onDestroy()
    }
}
