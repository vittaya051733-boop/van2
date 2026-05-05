package van.merchant

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

	override fun onCreate(savedInstanceState: Bundle?) {
		applyCallWindowFlags(intent)
		super.onCreate(savedInstanceState)
		CallIntentRouter.deliverIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		applyCallWindowFlags(intent)
		CallIntentRouter.deliverIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CONTROL_CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					METHOD_MOVE_TASK_TO_BACK -> {
							val moved = moveTaskToBack(true)
							if (!moved) {
								moveTaskToBack(false)
							}
						result.success(null)
					}
					METHOD_CAN_USE_FULL_SCREEN_INTENT -> {
						result.success(canUseFullScreenIntent())
					}
					METHOD_OPEN_FULL_SCREEN_INTENT_SETTINGS -> {
						openFullScreenIntentSettings()
						result.success(null)
					}
					METHOD_CAN_DRAW_OVERLAYS -> {
						result.success(canDrawOverlays())
					}
					METHOD_OPEN_OVERLAY_SETTINGS -> {
						openOverlaySettings()
						result.success(null)
					}
					else -> result.notImplemented()
				}
			}
		CallIntentRouter.register(flutterEngine)
	}

	private fun applyCallWindowFlags(intent: Intent?) {
		val isIncomingCall = intent?.action == ACTION_SHOW_INCOMING_CALL
		if (isIncomingCall) {
			window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
				setShowWhenLocked(true)
				setTurnScreenOn(true)
			} else {
				window.addFlags(
					WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
						WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
						WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
						WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
				)
			}
		} else {
			window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
				setShowWhenLocked(false)
				setTurnScreenOn(false)
			} else {
				window.clearFlags(
					WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
						WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
						WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
						WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
				)
			}
		}
	}

	private fun canUseFullScreenIntent(): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
			return true
		}
		val notificationManager = getSystemService(NotificationManager::class.java)
		return notificationManager?.canUseFullScreenIntent() ?: true
	}

	private fun openFullScreenIntentSettings() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
			val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
				data = Uri.parse("package:$packageName")
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			startActivity(intent)
			return
		}
		val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
			data = Uri.parse("package:$packageName")
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		startActivity(intent)
	}

	private fun canDrawOverlays(): Boolean {
		return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
	}

	private fun openOverlaySettings() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			return
		}
		val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
			data = Uri.parse("package:$packageName")
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		startActivity(intent)
	}

	companion object {
		const val ACTION_SHOW_INCOMING_CALL = "van.merchant.ACTION_SHOW_INCOMING_CALL"
		const val ACTION_CANCEL_INCOMING_CALL = "van.merchant.ACTION_CANCEL_INCOMING_CALL"
		const val ACTION_SHOW_CHAT_NOTIFICATION = "van.merchant.ACTION_SHOW_CHAT_NOTIFICATION"
		const val EXTRA_CHANNEL_ID = "extra_channel_id"
		const val EXTRA_APP_ID = "extra_app_id"
		const val EXTRA_CALL_TOKEN = "extra_call_token"
		const val EXTRA_CALLER_ID = "extra_caller_id"
		const val EXTRA_CALLER_NAME = "extra_caller_name"
		const val EXTRA_CALLER_PHOTO = "extra_caller_photo"
		const val EXTRA_IS_VIDEO = "extra_is_video"
		const val EXTRA_APP_WAS_FOREGROUND = "extra_app_was_foreground"
		const val EXTRA_ORDER_ID = "extra_order_id"
		const val EXTRA_CHAT_ID = "extra_chat_id"
		const val EXTRA_SENDER_ID = "extra_sender_id"
		const val EXTRA_SENDER_NAME = "extra_sender_name"
		const val EXTRA_MESSAGE = "extra_message"
		private const val APP_CONTROL_CHANNEL = "van.merchant/app_state"
		private const val METHOD_MOVE_TASK_TO_BACK = "move_task_to_back"
		private const val METHOD_CAN_USE_FULL_SCREEN_INTENT = "can_use_full_screen_intent"
		private const val METHOD_OPEN_FULL_SCREEN_INTENT_SETTINGS = "open_full_screen_intent_settings"
		private const val METHOD_CAN_DRAW_OVERLAYS = "can_draw_overlays"
		private const val METHOD_OPEN_OVERLAY_SETTINGS = "open_overlay_settings"
	}
}
