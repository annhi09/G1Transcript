package com.example.demo_ai_even

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.Build
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder

class CaptionMicService : Service() {
    private val channelId = "caption_mic_channel"
    private val notifId = 1001

    // AudioRecord (scaffold for future background capture)
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    @Volatile private var recording = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(notifId, buildNotification("Listening in background"))
        // TODO: Initialize and start AudioRecord if you implement background ASR
        // startAudioCapture()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // You could handle start/stop intents here if needed
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAudioCapture()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(content: String): Notification {
        val notifBuilder = Notification.Builder(this)
            .setContentTitle("Live Captions")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifBuilder.setChannelId(channelId)
        }
        return notifBuilder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(
                channelId,
                "Caption Background",
                NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(chan)
        }
    }

    // ---- Optional background audio capture scaffold ----
    private fun startAudioCapture() {
        if (recording) return
        val sampleRate = 16000
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        audioRecord?.startRecording()
        recording = true

        audioThread = Thread {
            val buffer = ShortArray(bufferSize / 2)
            while (recording) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    // TODO: stream PCM to your ASR (socket/http) or JNI
                }
            }
        }
        audioThread?.start()
    }

    private fun stopAudioCapture() {
        recording = false
        audioThread?.join(300)
        audioThread = null
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }
    // ----------------------------------------------------
}
