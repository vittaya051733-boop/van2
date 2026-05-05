package van.merchant

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Routes Android incoming-call intents to Flutter once a MethodChannel is ready.
 */
object CallIntentRouter {
    private const val CHANNEL_NAME = "van.merchant/call_intents"
    private const val METHOD_DRAIN_PENDING = "drain_pending_intents"

    private var channel: MethodChannel? = null
    private val pendingPayloads = mutableListOf<Map<String, Any?>>()
    private var flutterReady = false
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        if (channel != null) {
            return
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_DRAIN_PENDING -> {
                        flutterReady = true
                        val snapshot = ArrayList(pendingPayloads)
                        pendingPayloads.clear()
                        result.success(snapshot)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun deliverIntent(intent: Intent?) {
        val payload = extractPayload(intent) ?: return
        val methodChannel = channel
        if (methodChannel == null || !flutterReady) {
            pendingPayloads.add(payload)
        } else {
            mainHandler.post {
                methodChannel.invokeMethod("incoming_call_intent", payload)
            }
        }
    }

    private fun extractPayload(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        return when (intent.action) {
            MainActivity.ACTION_SHOW_INCOMING_CALL -> buildIncomingPayload(intent)
            MainActivity.ACTION_CANCEL_INCOMING_CALL -> buildCancelPayload(intent)
            MainActivity.ACTION_SHOW_CHAT_NOTIFICATION -> buildChatPayload(intent)
            else -> null
        }
    }

    private fun buildIncomingPayload(intent: Intent): Map<String, Any?>? {
        val channelId = intent.getStringExtra(MainActivity.EXTRA_CHANNEL_ID) ?: return null
        val token = intent.getStringExtra(MainActivity.EXTRA_CALL_TOKEN) ?: return null
        return mapOf(
            "channelId" to channelId,
            "appId" to intent.getStringExtra(MainActivity.EXTRA_APP_ID),
            "token" to token,
            "callerId" to intent.getStringExtra(MainActivity.EXTRA_CALLER_ID),
            "callerName" to intent.getStringExtra(MainActivity.EXTRA_CALLER_NAME),
            "callerPhotoUrl" to intent.getStringExtra(MainActivity.EXTRA_CALLER_PHOTO),
            "isVideo" to intent.getBooleanExtra(MainActivity.EXTRA_IS_VIDEO, false),
            "appWasForeground" to intent.getBooleanExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, true)
        )
    }

    private fun buildCancelPayload(intent: Intent): Map<String, Any?>? {
        val channelId = intent.getStringExtra(MainActivity.EXTRA_CHANNEL_ID) ?: return null
        return mapOf(
            "channelId" to channelId,
            "cancelOnly" to true
        )
    }

    private fun buildChatPayload(intent: Intent): Map<String, Any?>? {
        val chatId = intent.getStringExtra(MainActivity.EXTRA_CHAT_ID) ?: return null
        return mapOf(
            "type" to "chat",
            "chatId" to chatId,
            "senderId" to intent.getStringExtra(MainActivity.EXTRA_SENDER_ID),
            "senderName" to intent.getStringExtra(MainActivity.EXTRA_SENDER_NAME),
            "message" to intent.getStringExtra(MainActivity.EXTRA_MESSAGE),
            "orderId" to intent.getStringExtra(MainActivity.EXTRA_ORDER_ID)
        )
    }

}
