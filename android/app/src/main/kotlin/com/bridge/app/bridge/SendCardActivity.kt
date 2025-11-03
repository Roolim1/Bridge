package com.bridge.app.bridge

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import okio.source
import java.io.IOException

class SendCardActivity : Activity() {

    private val TAG = "SendCardActivity"
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.Main)

    // SharedPreferences se IP address lene ke liye keys
    private val PREFS_NAME = "FlutterSharedPreferences"
    private val IP_KEY = "flutter.last_receiver_ip"

    // UI Elements
    private lateinit var statusText: TextView
    private lateinit var fileNameText: TextView
    private lateinit var cardView: LinearLayout
    private lateinit var portalView: ImageView // Portal view

    // File Data
    private lateinit var fileUri: Uri
    private lateinit var fileName: String
    private var isSending = false

    // Drag variables
    private var originalCardY: Float = 0f // Card ki original Y position
    private var dY: Float = 0f // Touch offset

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Naya full-screen transparent layout set karein
        setContentView(R.layout.activity_send_card)

        // UI elements ko link karein
        statusText = findViewById(R.id.status_text)
        fileNameText = findViewById(R.id.file_name_text)
        cardView = findViewById(R.id.card_view)
        portalView = findViewById(R.id.portal_view) // Portal ko link karein

        // Window Flags ko (Theme ke saath) transparent banayein
        window.apply {
            // Yeh line background ko fully transparent rakhti hai
            setBackgroundDrawableResource(android.R.color.transparent)
            // Yeh line card ko status bar ke upar bhi drag hone degi
            addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        }

        // Share Intent se file data nikaalein
        if (intent?.action == Intent.ACTION_SEND) {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uri ->
                fileUri = uri
                fileName = getFileName(uri) ?: "shared_file"
                fileNameText.text = fileName
            } ?: run {
                showToast("No file to send.")
                finish()
            }
        } else {
            showToast("Invalid action.")
            finish()
        }

        // Card ki original position save karein (layout ke baad)
        cardView.post {
            originalCardY = cardView.y
        }

        // --- Drag (Touch) Listener Setup ---
        cardView.setOnTouchListener { view, event ->
            if (isSending) return@setOnTouchListener true // Agar bhej rahe hain toh drag lock karein

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    // Touch offset calculate karein (rawY screen par position deta hai)
                    dY = event.rawY - view.y
                    true // Event consume karein
                }
                MotionEvent.ACTION_MOVE -> {
                    // Card ko sirf vertically move karein
                    val newY = event.rawY - dY

                    // Card ko original position se neeche na jaane dein
                    if (newY >= originalCardY) {
                        view.y = originalCardY
                    } else {
                        // Sirf upar drag karne dein
                        view.y = newY
                    }

                    // Check karein agar portal se takra raha hai
                    if (isViewOverlapping(cardView, portalView)) {
                        portalView.alpha = 1.0f // Portal ko glow karayein
                        portalView.scaleX = 1.2f
                        portalView.scaleY = 1.2f
                    } else {
                        portalView.alpha = 0.8f // Normal alpha
                        portalView.scaleX = 1.0f
                        portalView.scaleY = 1.0f
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // Check karein agar user ne portal par chhodha
                    if (isViewOverlapping(cardView, portalView)) {
                        isSending = true
                        animateAndSend() // Send karein
                    } else {
                        // Wapis original position par animate karein
                        view.animate().y(originalCardY).setDuration(200).start()
                        portalView.alpha = 0.8f
                        portalView.scaleX = 1.0f
                        portalView.scaleY = 1.0f
                    }
                    true
                }
                else -> false
            }
        }
    }

    /**
     * Check karta hai ki do views overlap ho rahe hain ya nahi.
     */
    private fun isViewOverlapping(view1: View, view2: View): Boolean {
        val rect1 = Rect()
        view1.getHitRect(rect1)
        val rect2 = Rect()
        view2.getHitRect(rect2)
        return Rect.intersects(rect1, rect2)
    }

    /**
     * Card ko portal mein "suck" hone ka animation dikhata hai aur file send karta hai.
     */
    private fun animateAndSend() {
        statusText.text = "Sending..."
        portalView.animate().scaleX(1.5f).scaleY(1.5f).alpha(1f).setDuration(200).start() // Portal bada karein

        // Card ko portal ke center mein animate karein
        val targetX = portalView.x + (portalView.width - cardView.width) / 2
        val targetY = portalView.y + (portalView.height - cardView.height) / 2

        cardView.animate()
            .x(targetX)
            .y(targetY)
            .scaleX(0.0f) // Bilkul chhota karein
            .scaleY(0.0f) // Bilkul chhota karein
            .alpha(0f)
            .setDuration(300) // Thoda tez
            .withEndAction {
                sendFile(fileUri, fileName) // Animation ke baad file send karein
            }
            .start()
    }

    /**
     * File ko background mein send karta hai.
     */
    private fun sendFile(uri: Uri, fileName: String) {
        scope.launch {
            try {
                val ip = getSavedIp()
                if (ip == null) {
                    throw IOException("Receiver IP not set in app.")
                }
                val url = "http://$ip:8080"
                val requestBody = createRequestBody(uri)
                val request = Request.Builder()
                    .url(url)
                    .addHeader("file-name", Uri.encode(fileName))
                    .post(requestBody)
                    .build()

                withContext(Dispatchers.IO) {
                    client.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            throw IOException("Server error: ${response.code} ${response.body?.string()}")
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    finish() // Success
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    // Error: Card ko wapis reset karein
                    cardView.animate()
                        .x(cardView.x) // X position change nahi karni
                        .y(originalCardY) // Original Y position par set karein
                        .scaleX(1f)
                        .scaleY(1f)
                        .alpha(1f)
                        .setDuration(300)
                        .start()

                    portalView.animate().scaleX(1f).scaleY(1f).alpha(0.8f).setDuration(200).start()
                    statusText.text = "Error: ${e.message}"
                    isSending = false
                    delayAndFinish(isError = true)
                }
            }
        }
    }


    /**
     * Flutter ki SharedPreferences se saved IP address nikaalta hai.
     */
    private fun getSavedIp(): String? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(IP_KEY, null)
    }

    /**
     * File URI se OkHttp RequestBody banata hai.
     */
    private fun createRequestBody(uri: Uri): RequestBody {
        val contentType = contentResolver.getType(uri)?.toMediaTypeOrNull()
        val contentLength = getFileSize(uri)

        return object : RequestBody() {
            override fun contentType() = contentType
            override fun contentLength() = contentLength

            override fun writeTo(sink: BufferedSink) {
                val inputStream = contentResolver.openInputStream(uri)
                    ?: throw IOException("Failed to open input stream")

                inputStream.source().use { source ->
                    sink.writeAll(source)
                }
            }
        }
    }

    /**
     * File URI se file ka size (bytes mein) pata karta hai.
     */
    private fun getFileSize(uri: Uri): Long {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                    return cursor.getLong(sizeIndex)
                }
            }
        }
        // Agar size na mile toh -1 return karein (chunked transfer)
        return -1
    }

    /**
     * File URI se file ka naam pata karta hai.
     */
    private fun getFileName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1) {
                    return cursor.getString(nameIndex)
                }
            }
        }
        return uri.lastPathSegment
    }

    /**
     * Activity ko kuch der baad band karta hai (error ke case mein).
     */
    private fun delayAndFinish(isError: Boolean = false) {
        scope.launch {
            if(isError) {
                delay(3000L) // Error par 3s rukein
                finish()
            }
            // Success par yeh call nahi hoga, 'sendFile' se hi finish() ho jayega.
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel() // Memory leak se bachne ke liye Coroutine scope ko cancel karein
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }
}

