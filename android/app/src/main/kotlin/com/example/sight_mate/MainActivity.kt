package com.example.sight_mate

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.sight_mate/hardware_buttons"
    private var methodChannel: MethodChannel? = null

    private var lastVolumeUpTime: Long = 0
    private var lastVolumeDownTime: Long = 0
    private val DOUBLE_CLICK_TIME_DELTA: Long = 450 // milliseconds

    // Audio Gate for Movie Mode
    private var audioRecord: AudioRecord? = null
    private var isAudioGating = false
    private var audioGateThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAudioGate" -> {
                    startAudioGate()
                    result.success(true)
                }
                "stopAudioGate" -> {
                    stopAudioGate()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAudioGate() {
        if (isAudioGating) return
        isAudioGating = true

        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = if (minBufferSize > 2048) minBufferSize else 2048

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )
            audioRecord?.startRecording()

            audioGateThread = Thread {
                val buffer = ShortArray(bufferSize)
                while (isAudioGating) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        var sum = 0.0
                        for (i in 0 until read) {
                            val v = buffer[i].toDouble()
                            sum += v * v
                        }
                        val rms = Math.sqrt(sum / read)
                        runOnUiThread {
                            if (isAudioGating) {
                                methodChannel?.invokeMethod("onAudioLevel", rms)
                            }
                        }
                    }
                    try {
                        Thread.sleep(150)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }.apply { start() }
        } catch (_: Exception) {
            isAudioGating = false
        }
    }

    private fun stopAudioGate() {
        isAudioGating = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        audioGateThread = null
    }

    override fun onDestroy() {
        stopAudioGate()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val currentTime = SystemClock.uptimeMillis()

            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    if (currentTime - lastVolumeUpTime < DOUBLE_CLICK_TIME_DELTA) {
                        // Double-click detected!
                        lastVolumeUpTime = 0
                        // Revert the 1 step volume increase from the first click
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                            audioManager?.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, 0)
                        } catch (_: Exception) {}

                        methodChannel?.invokeMethod("onVolumeUpDoubleTap", null)
                        return true // Consume second click so volume doesn't increase twice
                    }
                    lastVolumeUpTime = currentTime
                    // Single click passes through to adjust volume normally
                    return super.dispatchKeyEvent(event)
                }

                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (currentTime - lastVolumeDownTime < DOUBLE_CLICK_TIME_DELTA) {
                        // Double-click detected!
                        lastVolumeDownTime = 0
                        // Revert the 1 step volume decrease from the first click
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                            audioManager?.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, 0)
                        } catch (_: Exception) {}

                        methodChannel?.invokeMethod("onVolumeDownDoubleTap", null)
                        return true // Consume second click so volume doesn't decrease twice
                    }
                    lastVolumeDownTime = currentTime
                    // Single click passes through to adjust volume normally
                    return super.dispatchKeyEvent(event)
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }
}
