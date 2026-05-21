package com.egitim_ai_tutor.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val channelName = "ai_tutor/tts"
    private var tts: TextToSpeech? = null
    private var isTtsReady = false
    private var pendingSpeakResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Creates FCM notification channels with human-readable Turkish names so
     * status-bar notifications group properly and the channel settings screen
     * shows meaningful labels (instead of the raw channel id).
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            Triple("koala_general", "Genel", NotificationManager.IMPORTANCE_DEFAULT),
            Triple("koala_messages", "Mesajlar", NotificationManager.IMPORTANCE_HIGH),
            Triple("koala_design", "Tasarım Hazır", NotificationManager.IMPORTANCE_HIGH),
        )
        for ((id, name, importance) in channels) {
            val channel = NotificationChannel(id, name, importance).apply {
                enableVibration(true)
                enableLights(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text").orEmpty()
                        val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                        val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
                        val gender = call.argument<String>("gender")?.lowercase(Locale.US) ?: "neutral"

                        if (text.isBlank()) {
                            result.error("invalid_text", "Text is empty.", null)
                            return@setMethodCallHandler
                        }
                        if (!isTtsReady) {
                            result.error("tts_not_ready", "TextToSpeech is not ready yet.", null)
                            return@setMethodCallHandler
                        }

                        applyVoiceForGender(gender = gender, baseRate = rate, basePitch = pitch)
                        pendingSpeakResult?.success(null)
                        pendingSpeakResult = result

                        val utteranceId = UUID.randomUUID().toString()
                        val speakResult = tts?.speak(
                            text,
                            TextToSpeech.QUEUE_FLUSH,
                            null,
                            utteranceId
                        )
                        if (speakResult == TextToSpeech.ERROR) {
                            pendingSpeakResult?.error("speak_failed", "Unable to speak text.", null)
                            pendingSpeakResult = null
                        }
                    }

                    "stop" -> {
                        tts?.stop()
                        pendingSpeakResult?.success(null)
                        pendingSpeakResult = null
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            isTtsReady = false
            return
        }

        tts?.language = Locale("tr", "TR")
        tts?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    runOnUiThread {
                        pendingSpeakResult?.success(null)
                        pendingSpeakResult = null
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    runOnUiThread {
                        pendingSpeakResult?.error("tts_error", "TTS failed.", null)
                        pendingSpeakResult = null
                    }
                }
            }
        )
        isTtsReady = true
    }

    private fun applyVoiceForGender(gender: String, baseRate: Float, basePitch: Float) {
        val engine = tts ?: return

        val allVoices: Set<Voice> = engine.voices ?: emptySet()
        val trVoices = allVoices.filter { it.locale?.language == "tr" }
        val voicePool = if (trVoices.isNotEmpty()) trVoices else allVoices.toList()

        val femaleKeys = listOf("female", "woman", "kadin", "zira", "fema")
        val maleKeys = listOf("male", "man", "erkek", "masc")

        val targetVoice = when (gender) {
            "female" -> voicePool.firstOrNull { voiceMatches(it, femaleKeys) }
            "male" -> voicePool.firstOrNull { voiceMatches(it, maleKeys) }
            else -> null
        } ?: voicePool.firstOrNull()

        if (targetVoice != null) {
            engine.voice = targetVoice
        }

        val pitchMultiplier = when (gender) {
            "female" -> 1.1f
            "male" -> 0.9f
            else -> 1.0f
        }
        val rateMultiplier = when (gender) {
            "female" -> 1.03f
            "male" -> 0.96f
            else -> 1.0f
        }

        engine.setPitch(basePitch * pitchMultiplier)
        engine.setSpeechRate(baseRate * rateMultiplier)
    }

    private fun voiceMatches(voice: Voice, keywords: List<String>): Boolean {
        val name = voice.name.lowercase(Locale.US)
        return keywords.any { key -> name.contains(key) }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
