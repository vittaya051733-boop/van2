package van.merchant

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import java.lang.ref.WeakReference

class IncomingCallActivity : AppCompatActivity() {
    private var channelId: String = ""
    private var didForwardToFlutter: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        applyCallWindowFlags()
        super.onCreate(savedInstanceState)
        activeActivity = WeakReference(this)
        handleIntent(intent)
        if (channelId.isEmpty()) {
            finish()
            return
        }
        forwardToFlutterCallScreen()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        if (intent.action == MainActivity.ACTION_CANCEL_INCOMING_CALL) {
            finish()
            return
        }
        didForwardToFlutter = false
        forwardToFlutterCallScreen()
    }

    override fun onDestroy() {
        if (activeActivity?.get() === this) {
            activeActivity = null
        }
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?) {
        channelId = intent?.getStringExtra(MainActivity.EXTRA_CHANNEL_ID).orEmpty()
        if (intent?.action == MainActivity.ACTION_CANCEL_INCOMING_CALL) {
            finish()
        }
    }

    private fun forwardToFlutterCallScreen() {
        if (didForwardToFlutter || channelId.isEmpty()) {
            return
        }
        didForwardToFlutter = true
        dismissNotification()
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHOW_INCOMING_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtras(intent)
        }
        startActivity(launchIntent)
        finish()
    }

    private fun dismissNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.cancel(VanFirebaseMessagingService.NOTIFICATION_ID_INCOMING_CALL)
    }

    private fun applyCallWindowFlags() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }

    companion object {
        @Volatile
        private var activeActivity: WeakReference<IncomingCallActivity>? = null

        fun dismissIfShowing(channelId: String?) {
            val activity = activeActivity?.get() ?: return
            if (channelId != null && activity.channelId.isNotEmpty() && activity.channelId != channelId) {
                return
            }
            activity.finish()
        }
    }
}