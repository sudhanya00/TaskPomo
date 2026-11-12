package com.sudhanya.taskpomo

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * On-device state for limited apps, shared by [ScrollGuardService] and the
 * app (through MainActivity's channel). Time is in milliseconds.
 *
 * balance = allowance (what the points above the reserve buy, pushed by the
 * app) + today's grace - usage not yet paid for.
 * The app pays for usage in points when it next runs and calls [consume].
 */
class GuardStore(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("scroll_guard", Context.MODE_PRIVATE)

    var packages: Set<String>
        get() = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        set(v) = prefs.edit().putStringSet(KEY_PACKAGES, v).apply()

    var labels: Map<String, String>
        get() = readMap(KEY_LABELS).mapValues { it.value.toString() }
        set(v) = prefs.edit().putString(KEY_LABELS, JSONObject(v).toString()).apply()

    var allowanceMs: Long
        get() = prefs.getLong(KEY_ALLOWANCE, 0)
        set(v) = prefs.edit().putLong(KEY_ALLOWANCE, v).apply()

    val unsyncedMs: Long get() = prefs.getLong(KEY_UNSYNCED, 0)

    /** Unpaid usage per package. */
    val perApp: Map<String, Long> get() = readMap(KEY_PER_APP).mapValues { (it.value as Number).toLong() }

    val graceAvailable: Boolean get() = prefs.getString(KEY_GRACE_DATE, null) != today()

    private val graceTodayMs: Long
        get() = if (prefs.getString(KEY_GRACE_DATE, null) == today()) GRACE_MS else 0

    val balanceMs: Long get() = allowanceMs + graceTodayMs - unsyncedMs

    fun isLimited(pkg: String?) = pkg != null && pkg in packages

    fun addUsage(pkg: String, ms: Long) {
        if (ms <= 0) return
        val per = perApp.toMutableMap()
        per[pkg] = (per[pkg] ?: 0) + ms
        prefs.edit()
            .putLong(KEY_UNSYNCED, unsyncedMs + ms)
            .putString(KEY_PER_APP, JSONObject(per as Map<*, *>).toString())
            .apply()
    }

    /**
     * Time on limited apps today, the same sum the app shows: what the app
     * has already paid for today (it tells us on every sync) plus usage not
     * yet paid for.
     */
    val usedTodayMs: Long
        get() {
            val paid = if (prefs.getString(KEY_PAID_DATE, null) == today()) prefs.getLong(KEY_PAID_MS, 0) else 0
            return paid + unsyncedMs
        }

    fun setPaid(date: String, ms: Long) {
        prefs.edit().putString(KEY_PAID_DATE, date).putLong(KEY_PAID_MS, ms).apply()
    }

    /** The app paid for [ms] of usage. Per-app detail shrinks in proportion. */
    fun consume(ms: Long) {
        val before = unsyncedMs
        val after = (before - ms).coerceAtLeast(0)
        val ratio = if (before == 0L) 0.0 else after.toDouble() / before
        val per = perApp.mapValues { (it.value * ratio).toLong() }.filterValues { it > 0 }
        prefs.edit()
            .putLong(KEY_UNSYNCED, after)
            .putString(KEY_PER_APP, JSONObject(per as Map<*, *>).toString())
            .apply()
    }

    /** A focus session's timer is running; time in other apps is noted. */
    var sessionRunning: Boolean
        get() = prefs.getBoolean(KEY_SESSION_RUNNING, false)
        set(v) = prefs.edit().putBoolean(KEY_SESSION_RUNNING, v).apply()

    /** Time per app during focus sessions, not yet collected by the app. */
    val sessionLog: Map<String, Long>
        get() = readMap(KEY_SESSION_LOG).mapValues { (it.value as Number).toLong() }

    fun addSessionUsage(pkg: String, ms: Long) {
        if (ms <= 0) return
        val log = sessionLog.toMutableMap()
        log[pkg] = (log[pkg] ?: 0) + ms
        prefs.edit().putString(KEY_SESSION_LOG, JSONObject(log as Map<*, *>).toString()).apply()
    }

    /** Hands over the session log and starts a fresh one. */
    fun takeSessionLog(): Map<String, Long> {
        val log = sessionLog
        prefs.edit().remove(KEY_SESSION_LOG).apply()
        return log
    }

    /** Forgets everything, e.g. when the account is deleted. */
    fun clear() {
        prefs.edit().clear().apply()
    }

    fun useGrace() {
        prefs.edit().putString(KEY_GRACE_DATE, today()).apply()
    }

    /** Whether the low-balance warning already went out today. */
    var warnedDate: String?
        get() = prefs.getString(KEY_WARNED, null)
        set(v) = prefs.edit().putString(KEY_WARNED, v).apply()

    private fun readMap(key: String): Map<String, Any> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return runCatching {
            val o = JSONObject(raw)
            o.keys().asSequence().associateWith { o.get(it) }
        }.getOrDefault(emptyMap())
    }

    companion object {
        const val GRACE_MS = 5 * 60 * 1000L
        private const val KEY_PACKAGES = "packages"
        private const val KEY_LABELS = "labels"
        private const val KEY_ALLOWANCE = "allowance_ms"
        private const val KEY_UNSYNCED = "unsynced_ms"
        private const val KEY_PER_APP = "per_app"
        private const val KEY_GRACE_DATE = "grace_date"
        private const val KEY_WARNED = "warned_date"
        private const val KEY_PAID_DATE = "paid_date"
        private const val KEY_SESSION_RUNNING = "session_running"
        private const val KEY_SESSION_LOG = "session_log"
        private const val KEY_PAID_MS = "paid_ms"

        fun today(): String {
            val c = Calendar.getInstance()
            return String.format(
                Locale.US, "%04d-%02d-%02d",
                c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
            )
        }
    }
}
