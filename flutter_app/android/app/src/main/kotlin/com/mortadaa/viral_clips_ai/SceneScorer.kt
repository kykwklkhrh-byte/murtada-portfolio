package com.mortadaa.viral_clips_ai

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Visual-change heuristic (NOT speech understanding or an AI model).
 * Samples a small number of video frames and chooses high-change windows.
 */
object SceneScorer {
    fun suggest(path: String, lengthMs: Long, count: Int): List<Long> {
        require(lengthMs in 1000..120000 && count in 1..8)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            require(duration >= 1000L) { "Video duration unavailable" }
            val clipLength = min(lengthMs, duration)
            val maxStart = max(0L, duration - clipLength)
            if (maxStart <= 0) return listOf(0L)

            val step = max(1700L, duration / 100)
            val scores = mutableListOf<Pair<Long, Double>>()
            var previous: IntArray? = null
            var at = 0L
            while (at < duration && scores.size < 105) {
                val current = sample(retriever, at)
                if (current != null) {
                    val before = previous
                    val score = if (before == null) 0.0 else difference(before, current)
                    scores.add(Pair(at, score))
                    previous = current
                }
                at += step
            }
            // Score candidates by average activity in a clip-length window.
            val ranked = scores.map { sample ->
                val start = (sample.first - clipLength / 3).coerceIn(0, maxStart)
                val windowEnd = min(duration, start + clipLength)
                val changes = scores.filter { it.first >= start && it.first < windowEnd }
                Pair(start, changes.map { it.second }.average().takeUnless { it.isNaN() } ?: 0.0)
            }.distinctBy { it.first / max(1000L, step) }
                .sortedByDescending { it.second }

            val starts = mutableListOf<Long>()
            fun addIfFree(t: Long) {
                if (starts.size >= count) return
                if (starts.none { abs(it - t) < clipLength * 9 / 10 }) starts.add(t)
            }
            for ((t, _) in ranked) addIfFree(t)
            // When the frames barely change (podcast talking heads), distribute
            // remaining samples evenly instead of pretending the score is smart.
            for (i in 0 until count * 5) {
                if (starts.size >= count) break
                val t = if (count <= 1) maxStart / 2
                        else (maxStart * i) / max(1, count * 5 - 1)
                addIfFree(t)
            }
            return starts.sorted().take(count)
        } finally {
            retriever.release()
        }
    }

    private fun sample(r: MediaMetadataRetriever, timeMs: Long): IntArray? {
        var frame: Bitmap? = null
        var small: Bitmap? = null
        try {
            frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                r.getScaledFrameAtTime(
                    timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 12, 12)
            } else {
                r.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }
            if (frame == null) return null
            small = if (frame.width == 12 && frame.height == 12) frame
                    else Bitmap.createScaledBitmap(frame, 12, 12, false)
            val values = IntArray(12 * 12)
            small.getPixels(values, 0, 12, 0, 0, 12, 12)
            return values
        } catch (_: Exception) {
            return null
        } finally {
            if (small != null && small !== frame) small.recycle()
            frame?.recycle()
        }
    }

    private fun difference(a: IntArray, b: IntArray): Double {
        var total = 0L
        for (i in a.indices) {
            val x = a[i]
            val y = b[i]
            total += abs((x shr 16 and 255) - (y shr 16 and 255))
            total += abs((x shr 8 and 255) - (y shr 8 and 255))
            total += abs((x and 255) - (y and 255))
        }
        return total.toDouble() / (a.size * 3.0)
    }
}
