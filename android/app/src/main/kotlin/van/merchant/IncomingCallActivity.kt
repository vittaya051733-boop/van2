package van.merchant

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.lang.ref.WeakReference

class IncomingCallActivity : AppCompatActivity() {
    private var channelId: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        applyCallWindowFlags()
        super.onCreate(savedInstanceState)
        activeActivity = WeakReference(this)
        handleIntent(intent)
        if (channelId.isEmpty()) {
            finish()
            return
        }
        setContentView(buildContentView())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        if (intent.action == MainActivity.ACTION_CANCEL_INCOMING_CALL) {
            finish()
        }
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

    private fun buildContentView(): LinearLayout {
        val callerName = intent.getStringExtra(MainActivity.EXTRA_CALLER_NAME).orEmpty().ifBlank { "ผู้โทร" }
        val isVideo = intent.getBooleanExtra(MainActivity.EXTRA_IS_VIDEO, false)

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F5F7FF"))
            setPadding(dp(24), dp(32), dp(24), dp(32))

            addView(TextView(context).apply {
                text = if (isVideo) "สายวิดีโอเข้า" else "สายเข้า"
                setTextColor(Color.parseColor("#5A6FB2"))
                textSize = 20f
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
            })

            addView(TextView(context).apply {
                text = callerName
                setTextColor(Color.parseColor("#111827"))
                textSize = 34f
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(0, dp(20), 0, dp(12))
            })

            addView(TextView(context).apply {
                text = "แตะเพื่อเปิดหน้ารับสายทันที"
                setTextColor(Color.parseColor("#6B7280"))
                textSize = 18f
                gravity = Gravity.CENTER
            })

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                setPadding(0, dp(32), 0, 0)

                addView(buildButton(
                    label = "ปิด",
                    backgroundColor = Color.parseColor("#E5E7EB"),
                    textColor = Color.parseColor("#111827"),
                ) {
                    dismissNotification()
                    finish()
                })

                addView(buildButton(
                    label = "เปิดหน้ารับสาย",
                    backgroundColor = Color.parseColor("#5A6FB2"),
                    textColor = Color.WHITE,
                ) {
                    openFlutterCallScreen()
                })
            })
        }
    }

    private fun buildButton(
        label: String,
        backgroundColor: Int,
        textColor: Int,
        onClick: () -> Unit,
    ): Button {
        return Button(this).apply {
            text = label
            isAllCaps = false
            setTextColor(textColor)
            textSize = 18f
            background = GradientDrawable().apply {
                setColor(backgroundColor)
                cornerRadius = dp(18).toFloat()
            }
            setPadding(dp(18), dp(14), dp(18), dp(14))
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(8)
                marginEnd = dp(8)
            }
        }
    }

    private fun openFlutterCallScreen() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHOW_INCOMING_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
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

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
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