package com.sudhanya.taskpomo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Ledger homescreen widget. It is visible to anyone who sees the phone, so it
 * never shows task names or icons: minutes today, the week, how much is left,
 * and numbered progress lines with each task's own streak. The app saves a
 * JSON payload (lib/services/widget_sync.dart); the wording and the paper's
 * age are worked out here from that payload and the clock, so they stay right
 * with the app closed.
 *
 * Widgets can't use custom fonts, so the serif numbers and headline are drawn
 * into bitmaps with the bundled Instrument Serif.
 */
class PomoWidgetProvider : HomeWidgetProvider() {

    private data class Item(
        val id: String,
        val target: Int,
        val days: Set<Int>,
        val created: String,
        val doneSec: Int,
        val completed: Boolean,
        val frozen: Boolean,
        val streak: Int,
    ) {
        val settled get() = completed || frozen
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = render(context, widgetData.getString("payload", null))
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    private fun render(context: Context, raw: String?): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.pomo_widget)
        val ink = context.getColor(R.color.ink)
        val muted = context.getColor(R.color.muted)
        val faint = context.getColor(R.color.ink_faint)
        val rust = context.getColor(R.color.rust)
        v.setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
        v.setViewVisibility(R.id.chrono, View.GONE)
        v.setViewVisibility(R.id.headline, View.VISIBLE)
        rows.forEach { v.setViewVisibility(it[0], View.GONE) }

        val cal = Calendar.getInstance()
        val today = key(cal)
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)
        // Calendar: Sunday = 1 … Saturday = 7. Ours: Monday = 1 … Sunday = 7.
        val weekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
        val monday = (cal.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1 - weekday) }

        val json = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
        if (json == null) {
            v.setImageViewBitmap(R.id.minutes, serif(context, listOf("0" to ink), 84f))
            headline(context, v, "Open to begin.", null, ink, muted)
            week(v, List(7) { if (it + 1 < weekday) "rest" to 0 else if (it + 1 == weekday) "today" to 0 else "future" to 0 })
            return v
        }

        // Data saved on an earlier day says nothing about today's progress.
        val fresh = json.optString("date") == today
        val tasks = json.optJSONArray("tasks")
        val items = (0 until (tasks?.length() ?: 0)).map { i ->
            val t = tasks!!.getJSONObject(i)
            val d = t.optJSONArray("days")
            Item(
                id = t.optString("id"),
                target = t.optInt("target", 15).coerceAtLeast(1),
                days = (0 until (d?.length() ?: 0)).map { d!!.getInt(it) }.toSet(),
                created = t.optString("created"),
                doneSec = if (fresh) t.optInt("doneSec") else 0,
                completed = fresh && t.optBoolean("completed"),
                frozen = fresh && t.optBoolean("frozen"),
                streak = t.optInt("streak"),
            )
        }
        val due = items.filter { weekday in it.days && it.created <= today }
        val left = due.filterNot { it.settled }
        val session = json.optJSONObject("session")
        val runningSince = session?.optLong("runningSince", 0L) ?: 0L

        // Minutes put in today, including a running session.
        var focusedMs = items.sumOf { it.doneSec.toLong() } * 1000
        if (session != null) {
            focusedMs += session.optLong("accumulatedMs") + if (runningSince > 0) System.currentTimeMillis() - runningSince else 0
        }
        v.setImageViewBitmap(R.id.minutes, serif(context, listOf("${focusedMs / 60000}" to ink), 84f))

        // Paper yellows as the day goes on with work left; see lib/logic/paper.dart.
        val targetTotal = due.sumOf { it.target }
        val minsLeft = left.sumOf { (it.target - it.doneSec / 60.0).coerceIn(0.0, it.target.toDouble()) }
        val dayGone = ((hour + minute / 60.0 - 9) / 15).coerceIn(0.0, 1.0)
        val age = if (targetTotal == 0) 0.0 else dayGone * minsLeft / targetTotal
        v.setInt(R.id.root, "setBackgroundResource", paperIds[Math.round(age * (paperIds.size - 1)).toInt()])

        week(v, weekCells(json, items, monday, today, weekday, due))

        // Eyebrow and headline.
        var eyebrow = "TODAY"
        var eyebrowColor = muted
        when {
            session != null && runningSince > 0 -> {
                eyebrow = "FOCUSING"
                eyebrowColor = rust
                val focused = session.optLong("accumulatedMs") + System.currentTimeMillis() - runningSince
                v.setViewVisibility(R.id.headline, View.GONE)
                v.setViewVisibility(R.id.chrono, View.VISIBLE)
                v.setChronometer(R.id.chrono, SystemClock.elapsedRealtime() - focused, null, true)
            }
            items.isEmpty() -> headline(context, v, "Add a task.", null, ink, muted)
            due.isEmpty() -> headline(context, v, "Rest day.", "Nothing due.", ink, muted)
            left.isEmpty() -> headline(context, v, "All done.", "See you tomorrow.", ink, muted)
            else -> {
                val count = if (left.size < words.size) words[left.size] else "${left.size}"
                headline(context, v, "$count left.", "${mins(Math.ceil(minsLeft).toInt())}.", ink, muted)
                if (hour >= 21) {
                    eyebrow = "BEFORE MIDNIGHT"
                    eyebrowColor = rust
                } else if (hour >= 18) {
                    eyebrow = "THIS EVENING"
                }
            }
        }
        v.setTextViewText(R.id.eyebrow, eyebrow)
        v.setTextColor(R.id.eyebrow, eyebrowColor)

        // Numbered rows, in the order the tasks were made so 01 always means
        // the same task to you. Each carries its own streak. If there are more
        // tasks than rows, unfinished ones get the rows.
        val numbered = due.withIndex().toList()
        val shown = if (numbered.size <= rows.size) numbered
        else numbered.sortedBy { if (it.value.settled) 1 else 0 }.take(rows.size).sortedBy { it.index }
        shown.forEachIndexed { r, (i, item) ->
            val ids = rows[r]
            val doneMin = item.doneSec / 60
            v.setViewVisibility(ids[0], View.VISIBLE)
            v.setTextViewText(ids[1], String.format(Locale.US, "%02d", i + 1))
            v.setTextViewText(
                ids[3],
                when {
                    item.completed -> "done"
                    item.frozen -> "frozen"
                    else -> "$doneMin/${item.target}"
                },
            )
            v.setTextViewText(ids[4], "${item.streak}d")
            val pct = if (item.completed) 100 else (doneMin * 100 / item.target).coerceIn(0, 100)
            v.setProgressBar(ids[2], 100, pct, false)
            v.setTextColor(ids[1], if (item.settled) faint else muted)
            v.setTextColor(ids[3], if (item.settled) faint else muted)
            v.setTextColor(ids[4], if (item.settled) faint else ink)
            v.setOnClickPendingIntent(
                ids[0],
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("taskpomo://timer?task=${Uri.encode(item.id)}"),
                ),
            )
        }
        return v
    }

    /**
     * The app's week (kind, fill %) rolled forward if days have passed since
     * it was saved. Days it never saw count as nothing done.
     */
    private fun weekCells(
        json: JSONObject,
        items: List<Item>,
        monday: Calendar,
        today: String,
        weekday: Int,
        due: List<Item>,
    ): List<Pair<String, Int>> {
        val saved = json.optJSONArray("week")
        val sameWeek = json.optString("weekStart") == key(monday)
        val savedDate = json.optString("date")
        val todayFill = due.sumOf { it.target }.let { total ->
            if (total == 0) 0
            else (100 * due.sumOf { if (it.settled) it.target.toDouble() else (it.doneSec / 60.0).coerceAtMost(it.target.toDouble()) } / total).toInt()
        }
        return (0 until 7).map { i ->
            val k = key((monday.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, i) })
            val cell = saved?.optJSONObject(i)
            when {
                i + 1 > weekday -> "future" to 0
                i + 1 == weekday -> "today" to todayFill
                sameWeek && k <= savedDate && cell != null ->
                    (if (cell.optString("k") == "today") "past" else cell.optString("k")) to cell.optInt("f")
                else -> (if (items.any { (i + 1) in it.days && it.created <= k }) "past" else "rest") to 0
            }
        }
    }

    private fun week(v: RemoteViews, cells: List<Pair<String, Int>>) {
        cells.forEachIndexed { i, (kind, fill) ->
            v.setImageViewResource(
                weekIds[i],
                when (kind) {
                    "past" -> R.drawable.week_past
                    "today" -> R.drawable.week_today
                    "rest" -> R.drawable.week_rest
                    else -> R.drawable.week_future
                },
            )
            v.setInt(weekIds[i], "setImageLevel", fill.coerceIn(0, 100) * 100)
        }
    }

    private fun headline(context: Context, v: RemoteViews, line: String, aside: String?, ink: Int, muted: Int) {
        val parts = mutableListOf(line to ink)
        if (aside != null) parts += " $aside" to muted
        v.setImageViewBitmap(R.id.headline, serif(context, parts, 32f, italicFrom = 1))
    }

    /** Draws [parts] in Instrument Serif at [sizeSp]; parts from [italicFrom] on are italic. */
    private fun serif(context: Context, parts: List<Pair<String, Int>>, sizeSp: Float, italicFrom: Int = Int.MAX_VALUE): Bitmap {
        val px = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sizeSp, context.resources.displayMetrics)
        val regular = font(context, R.font.instrument_serif, Typeface.SERIF)
        val italic = font(context, R.font.instrument_serif_italic, Typeface.create(Typeface.SERIF, Typeface.ITALIC))
        val paints = parts.mapIndexed { i, (_, color) ->
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
                typeface = if (i >= italicFrom) italic else regular
                textSize = px
                this.color = color
                letterSpacing = -0.02f
            }
        }
        val fm = paints[0].fontMetrics
        val width = parts.indices.sumOf { paints[it].measureText(parts[it].first).toDouble() }.toInt() + 4
        val height = (fm.descent - fm.ascent).toInt() + 2
        val bmp = Bitmap.createBitmap(width.coerceAtLeast(1), height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        var x = 0f
        parts.forEachIndexed { i, (text, _) ->
            c.drawText(text, x, -fm.ascent, paints[i])
            x += paints[i].measureText(text)
        }
        return bmp
    }

    private fun font(context: Context, id: Int, fallback: Typeface): Typeface =
        if (Build.VERSION.SDK_INT >= 26) runCatching { context.resources.getFont(id) }.getOrDefault(fallback) else fallback

    private fun key(c: Calendar) = String.format(
        Locale.US, "%04d-%02d-%02d",
        c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
    )

    private fun mins(m: Int) = when {
        m < 60 -> "$m min"
        m % 60 == 0 -> "${m / 60} h"
        else -> "${m / 60} h ${m % 60} min"
    }

    private companion object {
        val words = listOf("None", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten")
        val weekIds = intArrayOf(R.id.week0, R.id.week1, R.id.week2, R.id.week3, R.id.week4, R.id.week5, R.id.week6)
        val paperIds = intArrayOf(
            R.drawable.widget_bg_0, R.drawable.widget_bg_1, R.drawable.widget_bg_2,
            R.drawable.widget_bg_3, R.drawable.widget_bg_4, R.drawable.widget_bg_5,
        )

        /** root, index, bar, value, streak */
        val rows = listOf(
            intArrayOf(R.id.row1, R.id.row1_index, R.id.row1_bar, R.id.row1_value, R.id.row1_streak),
            intArrayOf(R.id.row2, R.id.row2_index, R.id.row2_bar, R.id.row2_value, R.id.row2_streak),
            intArrayOf(R.id.row3, R.id.row3_index, R.id.row3_bar, R.id.row3_value, R.id.row3_streak),
            intArrayOf(R.id.row4, R.id.row4_index, R.id.row4_bar, R.id.row4_value, R.id.row4_streak),
            intArrayOf(R.id.row5, R.id.row5_index, R.id.row5_bar, R.id.row5_value, R.id.row5_streak),
        )
    }
}
