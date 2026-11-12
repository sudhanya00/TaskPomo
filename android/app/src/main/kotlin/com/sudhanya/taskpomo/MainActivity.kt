package com.sudhanya.taskpomo

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Hosts the Flutter app and the 'taskpomo/guard' channel, through which the
 * app configures limited apps and pays for their usage in points.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val icons = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Where the app was installed from; App Check only works for Play installs.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskpomo/app").setMethodCallHandler { call, result ->
            if (call.method == "installer") result.success(installer()) else result.notImplemented()
        }
        val store = GuardStore(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskpomo/guard").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(serviceEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "openAppInfo" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "installedApps" -> io.execute {
                    val apps = installedApps()
                    main.post { result.success(apps) }
                }
                "appIcon" -> {
                    val pkg = call.argument<String>("package")
                    icons.execute {
                        val png = runCatching { iconPng(packageManager.getApplicationIcon(pkg!!)) }.getOrNull()
                        main.post { result.success(png) }
                    }
                }
                "configure" -> {
                    @Suppress("UNCHECKED_CAST")
                    val apps = call.argument<List<Map<String, String>>>("apps") ?: emptyList()
                    store.packages = apps.mapNotNull { it["package"] }.toSet()
                    store.labels = apps.associate { (it["package"] ?: "") to (it["label"] ?: "") }
                    store.allowanceMs = (call.argument<Number>("allowanceSeconds")?.toLong() ?: 0) * 1000
                    val paidDate = call.argument<String>("paidDate")
                    val paidSeconds = call.argument<Number>("paidSeconds")?.toLong()
                    if (paidDate != null && paidSeconds != null) store.setPaid(paidDate, paidSeconds * 1000)
                    Log.d("TaskPomoGuard", "configure: ${store.packages.size} limited apps, allowance ${store.allowanceMs / 1000}s")
                    result.success(null)
                }
                "state" -> result.success(
                    mapOf(
                        "unsyncedSeconds" to store.unsyncedMs / 1000,
                        "balanceSeconds" to store.balanceMs / 1000,
                        "graceAvailable" to store.graceAvailable,
                        "perApp" to store.perApp.mapValues { it.value / 1000 },
                        "enabled" to serviceEnabled(),
                    ),
                )
                "sessionRunning" -> {
                    store.sessionRunning = call.argument<Boolean>("running") ?: false
                    result.success(null)
                }
                "takeSessionLog" -> io.execute {
                    val log = store.takeSessionLog().map { (pkg, ms) -> describe(pkg) + ("ms" to ms) }
                    main.post { result.success(log) }
                }
                "reset" -> {
                    store.clear()
                    result.success(null)
                }
                "consume" -> {
                    store.consume((call.argument<Number>("seconds")?.toLong() ?: 0) * 1000)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private val browsers: Set<String> by lazy {
        @Suppress("DEPRECATION")
        packageManager.queryIntentActivities(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")),
            PackageManager.MATCH_ALL,
        ).map { it.activityInfo.packageName }.toSet()
    }

    /**
     * Name and kind of an app, for judging time spent in it during a session.
     * The kind comes from the category the app's developer declares.
     */
    private fun describe(pkg: String): Map<String, Any> {
        val info = runCatching { packageManager.getApplicationInfo(pkg, 0) }.getOrNull()
        val label = info?.let { packageManager.getApplicationLabel(it).toString() } ?: pkg
        val kind = when {
            pkg in browsers -> "browser"
            info == null || Build.VERSION.SDK_INT < 26 -> "other"
            info.category == ApplicationInfo.CATEGORY_SOCIAL -> "social"
            info.category == ApplicationInfo.CATEGORY_GAME -> "game"
            info.category == ApplicationInfo.CATEGORY_VIDEO -> "video"
            else -> "other"
        }
        return mapOf("package" to pkg, "label" to label, "kind" to kind)
    }

    private fun installer(): String? = runCatching {
        if (Build.VERSION.SDK_INT >= 30) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    }.getOrNull()

    private fun serviceEnabled(): Boolean {
        val am = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
            it.resolveInfo.serviceInfo.packageName == packageName &&
                it.resolveInfo.serviceInfo.name == ScrollGuardService::class.java.name
        }
    }

    /**
     * Launchable apps for the picker, names only: drawing every icon up front
     * took seconds, so the picker asks for each icon as its row appears.
     */
    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val infos = pm.queryIntentActivities(launcher, PackageManager.MATCH_ALL)
        return infos
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { app ->
                mapOf(
                    "package" to app.packageName,
                    "label" to pm.getApplicationLabel(app).toString(),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    private fun iconPng(d: android.graphics.drawable.Drawable): ByteArray {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        return ByteArrayOutputStream().use {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }
}
