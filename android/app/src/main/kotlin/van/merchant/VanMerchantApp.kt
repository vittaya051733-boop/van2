package van.merchant

import android.app.Activity
import android.app.Application
import android.os.Bundle
import kotlin.math.max

class VanMerchantApp : Application(), Application.ActivityLifecycleCallbacks {

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(this)
    }

    override fun onTerminate() {
        unregisterActivityLifecycleCallbacks(this)
        super.onTerminate()
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivityStarted(activity: Activity) {
        synchronized(this) {
            foregroundActivities++
            isAppVisible = foregroundActivities > 0
        }
    }

    override fun onActivityResumed(activity: Activity) = Unit

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivityStopped(activity: Activity) {
        synchronized(this) {
            foregroundActivities = max(0, foregroundActivities - 1)
            isAppVisible = foregroundActivities > 0
        }
    }

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) = Unit

    companion object {
        @Volatile private var isAppVisible: Boolean = false
        @Volatile private var foregroundActivities: Int = 0

        @JvmStatic
        fun isAppInForeground(): Boolean = isAppVisible
    }
}