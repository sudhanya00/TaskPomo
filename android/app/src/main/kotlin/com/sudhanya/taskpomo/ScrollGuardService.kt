package com.sudhanya.taskpomo

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import android.widget.TextView

/**
 * Counts time spent in the apps you chose to limit and, when your points
 * run out, covers them with a full-screen page. It only looks at which app
 * is in front: no screen content is read.
 */
class ScrollGuardService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: GuardStore
    private var current: String? = null
    private var lastTick = 0L
    private var screenOn = true
    private var overlay: View? = null
    private val ignored = mutableSetOf("com.android.systemui")

    /** Home screens: sitting on one during a session isn't using an app. */
    private val home = mutableSetOf<String>()

    private val ticker = object : Runnable {
        override fun run() {
            step()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            step()
            screenOn = intent.action != Intent.ACTION_SCREEN_OFF
            lastTick = SystemClock.elapsedRealtime()
            evaluate()
        }
    }

    override fun onServiceConnected() {
        store = GuardStore(this)
        // Keyboards pop up over apps; they shouldn't count as switching away.
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .enabledInputMethodList.forEach { ignored += it.packageName }
        @Suppress("DEPRECATION")
        packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_ALL,
        ).forEach { home += it.activityInfo.packageName }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        lastTick = SystemClock.elapsedRealtime()
        handler.post(ticker)
        Log.d(TAG, "connected; ${store.packages.size} limited apps, balance ${store.balanceMs / 1000}s")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg in ignored) return
        // Our own block page reports as us; that isn't the user leaving.
        if (pkg == packageName && overlay != null) return
        if (pkg == current) return
        // Only a real app screen (an activity) means the user switched apps.
        // Pop-ups that float over an app (caller ID cards, chat heads, edge
        // panels, dialogs) also send window changes, but the app underneath
        // is still in front; treating them as a switch stopped the count.
        if (!isActivity(pkg, event.className?.toString())) return
        step()
        current = pkg
        evaluate()
    }

    private val activityCache = HashMap<String, Boolean>()

    private fun isActivity(pkg: String, cls: String?): Boolean {
        if (cls == null) return false
        return activityCache.getOrPut("$pkg/$cls") {
            runCatching { packageManager.getActivityInfo(ComponentName(pkg, cls), 0) }.isSuccess
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        hideLive()
        runCatching { unregisterReceiver(screenReceiver) }
        hideBlock()
        super.onDestroy()
    }

    /**
     * Charges the time since the last tick to the app in front, if limited,
     * and notes it for a running focus session if it's another app.
     */
    private fun step() {
        val now = SystemClock.elapsedRealtime()
        val pkg = current
        // Cap a single step so a missed tick can't overcharge.
        val ms = (now - lastTick).coerceIn(0, 4 * TICK_MS)
        if (screenOn && overlay == null && store.isLimited(pkg)) {
            store.addUsage(pkg!!, ms)
        }
        if (screenOn && overlay == null && pkg != null && pkg != packageName &&
            pkg !in home && store.sessionRunning
        ) {
            store.addSessionUsage(pkg, ms)
        }
        lastTick = now
        evaluate()
    }

    private fun evaluate() {
        val limited = screenOn && store.isLimited(current)
        if (!limited) {
            hideBlock()
            hideLive()
            return
        }
        val balance = store.balanceMs
        if (balance <= 0) {
            hideLive()
            showBlock()
        } else {
            hideBlock()
            showLive(current!!, balance)
            if (balance <= WARN_MS && store.warnedDate != GuardStore.today()) {
                store.warnedDate = GuardStore.today()
                warn(balance)
            }
        }
    }

    private fun showBlock() {
        if (overlay != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = object : android.widget.FrameLayout(this) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    goHome()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        LayoutInflater.from(this).inflate(R.layout.guard_block, view, true)
        val grace = view.findViewById<TextView>(R.id.guard_grace)
        grace.visibility = if (store.graceAvailable) View.VISIBLE else View.GONE
        view.findViewById<TextView>(R.id.guard_body).text = if (store.allowanceMs < 0) {
            "You’re ${minutes(-store.allowanceMs)} min behind after grace minutes. Finish a task to earn them back."
        } else {
            "Your points for these apps are used up. Finish a task to earn more: about a minute for every three of practice."
        }
        view.findViewById<TextView>(R.id.guard_open).setOnClickListener {
            hideBlock()
            startActivity(
                packageManager.getLaunchIntentForPackage(packageName)!!
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        }
        grace.setOnClickListener {
            store.useGrace()
            lastTick = SystemClock.elapsedRealtime()
            hideBlock()
            liveFor = null
            evaluate()
        }
        view.findViewById<TextView>(R.id.guard_home).setOnClickListener { goHome() }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        )
        runCatching { wm.addView(view, params) }.onSuccess { overlay = view }
    }

    private fun hideBlock() {
        val v = overlay ?: return
        overlay = null
        runCatching { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(v) }
    }

    private fun goHome() {
        hideBlock()
        current = null
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /** A quiet heads-up a couple of minutes before the block. Names no app. */
    private fun warn(balanceMs: Long) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("guard", "Scroll minutes", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "guard") else Notification.Builder(this)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_mark)
            .setContentTitle("${minutes(balanceMs).coerceAtLeast(1)} scroll minutes left")
            .setContentText("Then these apps pause until you earn more.")
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(WARN_ID, n) }
    }

    private var liveFor: String? = null
    private var liveAt = 0L

    /**
     * Silent, ongoing countdown while a limited app is in front: the header
     * ticks down the time left on its own. Re-posted when the app changes,
     * after grace, and once a minute for the "used today" line.
     */
    private fun showLive(pkg: String, balanceMs: Long) {
        val now = SystemClock.elapsedRealtime()
        if (pkg == liveFor && now - liveAt < 60_000) return
        liveFor = pkg
        liveAt = now
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("guard_live", "Scroll timer", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = store.labels[pkg]?.takeIf { it.isNotBlank() } ?: "Limited app"
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "guard_live") else Notification.Builder(this)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_mark)
            .setContentTitle("$label · scroll minutes left")
            .setContentText("${used(store.usedTodayMs)} used today on limited apps")
            .setWhen(System.currentTimeMillis() + balanceMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open)
            .build()
        runCatching { nm.notify(LIVE_ID, n) }
    }

    private fun hideLive() {
        if (liveFor == null) return
        liveFor = null
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(LIVE_ID)
    }

    private fun minutes(ms: Long) = ((ms + 59_999) / 60_000).toInt()

    /** Same format as "Used today" in the app: seconds until a full minute. */
    private fun used(ms: Long): String {
        val s = ms / 1000
        return if (s < 60) "$s s" else "${s / 60} min"
    }

    private companion object {
        const val TAG = "TaskPomoGuard"
        const val TICK_MS = 5_000L
        const val WARN_MS = 2 * 60_000L
        const val WARN_ID = 410
        const val LIVE_ID = 411
    }
}
