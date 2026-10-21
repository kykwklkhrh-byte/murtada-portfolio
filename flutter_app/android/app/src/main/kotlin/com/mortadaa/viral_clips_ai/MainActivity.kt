package com.mortadaa.viral_clips_ai

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "viral_clips_ai/native_video")
            .setMethodCallHandler { call, reply ->
                if (call.method == "suggest") {
                    val source = call.argument<String>("path")
                    val durationMs = call.argument<Number>("durationMs")?.toLong()
                    val count = call.argument<Number>("count")?.toInt()
                    if (source.isNullOrBlank() || durationMs == null || count == null ||
                            durationMs !in 1000L..120000L || count !in 1..8) {
                        reply.error("INVALID", "Invalid analysis settings", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val candidates = SceneScorer.suggest(source, durationMs, count)
                            runOnUiThread { reply.success(candidates) }
                        } catch (e: Exception) {
                            runOnUiThread { reply.error("ANALYSIS_FAILED",
                                e.message ?: "Cannot inspect video frames", null) }
                        }
                    }.start()
                    return@setMethodCallHandler
                }
                if (call.method != "trim") {
                    reply.notImplemented()
                    return@setMethodCallHandler
                }
                val filename = call.argument<String>("path")
                val start = call.argument<Number>("startMs")?.toLong()
                val length = call.argument<Number>("durationMs")?.toLong()
                if (filename.isNullOrBlank() || start == null || length == null ||
                        start < 0 || length < 1000 || length > 120000) {
                    reply.error("INVALID", "Invalid video selection or range", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val file = cut(File(filename), start, length)
                        runOnUiThread { reply.success(file.absolutePath) }
                    } catch (e: Exception) {
                        runOnUiThread { reply.error("CUT_ERROR", e.message ?: "Cannot cut this video", null) }
                    }
                }.start()
            }
    }

    private data class Stream(val reader: MediaExtractor, val muxId: Int, val video: Boolean)

    private fun cut(source: File, startMs: Long, durationMs: Long): File {
        require(source.isFile && source.length() > 0) { "Input video not available" }
        val probe = MediaMetadataRetriever()
        var duration = 0L
        var rotation = 0
        try {
            probe.setDataSource(source.absolutePath)
            duration = probe.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            rotation = probe.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } finally {
            probe.release()
        }
        require(duration > startMs + 500) { "Choose an earlier start position" }
        val end = minOf(duration, startMs + durationMs) * 1000
        val folder = getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
        folder.mkdirs()
        val out = File(folder, "ViralClip_" + UUID.randomUUID().toString().take(10) + ".mp4")
        val streams = mutableListOf<Stream>()
        val mux = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        var ok = false
        try {
            if (rotation in listOf(90, 180, 270)) mux.setOrientationHint(rotation)
            val scan = MediaExtractor()
            try {
                scan.setDataSource(source.absolutePath)
                var gotVideo = false
                var gotAudio = false
                for (i in 0 until scan.trackCount) {
                    val format = scan.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                    val isVideo = mime.startsWith("video/")
                    val isAudio = mime.startsWith("audio/")
                    if (!isVideo && !isAudio) continue
                    if (isVideo && gotVideo || isAudio && gotAudio) continue
                    // MPEG4 container needs compatible codecs, not arbitrary MKV/WebM samples.
                    if (isVideo && mime !in listOf("video/avc", "video/hevc", "video/mp4v-es", "video/3gpp")) {
                        throw IllegalArgumentException("Unsupported video codec: " + mime + ". Try MP4 H.264.")
                    }
                    if (isAudio && mime !in listOf("audio/mp4a-latm", "audio/3gpp", "audio/amr-wb")) continue
                    val reader = MediaExtractor()
                    try {
                        reader.setDataSource(source.absolutePath)
                        reader.selectTrack(i)
                        streams.add(Stream(reader, mux.addTrack(format), isVideo))
                    } catch (e: Exception) {
                        reader.release()
                        throw e
                    }
                    if (isVideo) gotVideo = true else gotAudio = true
                }
            } finally {
                scan.release()
            }
            require(streams.any { it.video }) { "No supported video track found" }
            val video = streams.first { it.video }.reader
            video.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val fromUs = maxOf(0L, video.sampleTime)
            mux.start()
            started = true
            var videoSamples = 0
            for (stream in streams) {
                val reader = stream.reader
                reader.seekTo(fromUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val buffer = ByteBuffer.allocateDirect(8 * 1024 * 1024)
                val info = MediaCodec.BufferInfo()
                var lastPts = -1L
                while (reader.sampleTime >= 0 && reader.sampleTime < end) {
                    val pts = reader.sampleTime
                    if (pts < fromUs) {
                        if (!reader.advance()) break
                        continue
                    }
                    buffer.clear()
                    val size = reader.readSampleData(buffer, 0)
                    if (size <= 0) break
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = maxOf(0L, pts - fromUs)
                    info.flags = reader.sampleFlags
                    if (info.presentationTimeUs > lastPts) {
                        mux.writeSampleData(stream.muxId, buffer, info)
                        lastPts = info.presentationTimeUs
                        if (stream.video) videoSamples++
                    }
                    if (!reader.advance()) break
                }
            }
            require(videoSamples > 0) { "No samples found in selected range" }
            ok = true
        } finally {
            for (s in streams) try { s.reader.release() } catch (_: Exception) {}
            if (started) try { mux.stop() } catch (_: Exception) { ok = false }
            try { mux.release() } catch (_: Exception) {}
            if (!ok) out.delete()
        }
        require(out.exists() && out.length() > 0) { "Video export failed" }
        return out
    }
}
