package com.bridge.app.bridge

import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.app.PendingIntent // <-- FIX: Import PendingIntent

class QuickSendTileService : TileService() {

    private val TAG = "QuickSendTileService"

    override fun onStartListening() {
        super.onStartListening()
        Log.d(TAG, "Tile is listening")
        // You can update the tile state here
        qsTile?.state = Tile.STATE_INACTIVE
        qsTile?.updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        Log.d(TAG, "Tile is not listening")
    }

    override fun onClick() {
        super.onClick()
        Log.d(TAG, "Tile clicked, starting activity...")

        // 1. Create the same Intent
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("route", "/sender")
        }

        // 2. FIX: Wrap the Intent in a PendingIntent
        val pendingIntent = PendingIntent.getActivity(
            this,
            0, // Request code
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 3. FIX: Use the PendingIntent to start the activity
        try {
            startActivityAndCollapse(pendingIntent)
            qsTile?.state = Tile.STATE_ACTIVE
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start activity from tile", e)
        }

        qsTile?.updateTile()
    }
}
