package van.merchant

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

data class IncomingCallOverlayData(
    val channelId: String,
    val callerName: String,
    val isVideo: Boolean,
)

object IncomingCallOverlayController {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var currentChannelId: String? = null

    fun show(
        context: Context,
        data: IncomingCallOverlayData,
        onOpenCallScreen: () -> Unit,
        onDismiss: () -> Unit,
    ) {
        if (!canDrawOverlays(context)) {
            return
        }
        if (currentChannelId == data.channelId && overlayView != null) {
            return
        }
        dismiss()

        val appContext = context.applicationContext
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return

        val scrim = FrameLayout(appContext).apply {
            setBackgroundColor(0x99000000.toInt())
            isClickable = true
            isFocusable = true
        }

        val card = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(appContext, 24), dp(appContext, 28), dp(appContext, 24), dp(appContext, 24))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(appContext, 28).toFloat()
            }
        }

        val badge = TextView(appContext).apply {
            text = if (data.isVideo) "สายวิดีโอเข้า" else "สายเข้า"
            setTextColor(Color.parseColor("#4A5D9F"))
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
        }

        val callerName = TextView(appContext).apply {
            text = data.callerName
            setTextColor(Color.parseColor("#111827"))
            textSize = 28f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(appContext, 18), 0, dp(appContext, 10))
        }

        val subtitle = TextView(appContext).apply {
            text = "มีสายเรียกเข้า แตะเปิดหน้ารับสายทันที"
            setTextColor(Color.parseColor("#6B7280"))
            textSize = 16f
            gravity = Gravity.CENTER
        }

        val buttonRow = LinearLayout(appContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(appContext, 28), 0, 0)
        }

        val declineButton = buildActionButton(
            context = appContext,
            label = "ปิด",
            backgroundColor = Color.parseColor("#E5E7EB"),
            textColor = Color.parseColor("#111827"),
        ) {
            dismiss()
            onDismiss()
        }

        val answerButton = buildActionButton(
            context = appContext,
            label = "เปิดหน้ารับสาย",
            backgroundColor = Color.parseColor("#4A5D9F"),
            textColor = Color.WHITE,
        ) {
            dismiss()
            onOpenCallScreen()
        }

        buttonRow.addView(declineButton)
        buttonRow.addView(answerButton)

        card.addView(
            badge,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        card.addView(
            callerName,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        card.addView(
            subtitle,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        card.addView(
            buttonRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        ).apply {
            leftMargin = dp(appContext, 24)
            rightMargin = dp(appContext, 24)
        }
        scrim.addView(card, cardParams)

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            windowType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        wm.addView(scrim, layoutParams)
        overlayView = scrim
        windowManager = wm
        currentChannelId = data.channelId
    }

    fun dismiss(channelId: String? = null) {
        if (channelId != null && currentChannelId != null && channelId != currentChannelId) {
            return
        }
        val view = overlayView ?: return
        val wm = windowManager
        try {
            wm?.removeViewImmediate(view)
        } catch (_: Exception) {
        }
        overlayView = null
        windowManager = null
        currentChannelId = null
    }

    private fun canDrawOverlays(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || android.provider.Settings.canDrawOverlays(context)
    }

    private fun buildActionButton(
        context: Context,
        label: String,
        backgroundColor: Int,
        textColor: Int,
        onClick: () -> Unit,
    ): Button {
        return Button(context).apply {
            text = label
            isAllCaps = false
            setTextColor(textColor)
            textSize = 16f
            minHeight = dp(context, 52)
            minimumHeight = dp(context, 52)
            background = GradientDrawable().apply {
                setColor(backgroundColor)
                cornerRadius = dp(context, 18).toFloat()
            }
            setPadding(dp(context, 18), dp(context, 12), dp(context, 18), dp(context, 12))
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(context, 6)
                marginEnd = dp(context, 6)
            }
        }
    }

    private fun dp(context: Context, value: Int): Int {
        return (value * context.resources.displayMetrics.density).toInt()
    }
}