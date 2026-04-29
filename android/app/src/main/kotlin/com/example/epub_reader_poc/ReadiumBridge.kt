package com.example.epub_reader_poc

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object ReadiumBridge {
    var channel: MethodChannel? = null

    fun emitPosition(
        bookId: String,
        chapterIndex: Int,
        pageInChapter: Int,
        progressPercent: Double,
        locatorJson: String?,
    ) {
        val payload = mapOf(
            "bookId" to bookId,
            "chapterIndex" to chapterIndex,
            "pageInChapter" to pageInChapter,
            "progressPercent" to progressPercent,
            "locatorJson" to locatorJson,
        )

        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("onReadiumPositionChanged", payload)
        }
    }

    fun emitToolbarAction(
        bookId: String,
        action: String,
        chapterIndex: Int,
        pageInChapter: Int,
        progressPercent: Double,
        locatorJson: String?,
        snippetText: String? = null,
    ) {
        val payload = mapOf(
            "bookId" to bookId,
            "action" to action,
            "chapterIndex" to chapterIndex,
            "pageInChapter" to pageInChapter,
            "progressPercent" to progressPercent,
            "locatorJson" to locatorJson,
            "snippetText" to snippetText,
        )

        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("onReadiumToolbarAction", payload)
        }
    }

    fun emitHighlightCreated(
        bookId: String,
        chapterIndex: Int,
        pageInChapter: Int,
        progressPercent: Double,
        color: String,
        text: String,
        locatorJson: String?,
    ) {
        val payload = mapOf(
            "bookId" to bookId,
            "chapterIndex" to chapterIndex,
            "pageInChapter" to pageInChapter,
            "progressPercent" to progressPercent,
            "color" to color,
            "text" to text,
            "locatorJson" to locatorJson,
        )

        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("onReadiumHighlightCreated", payload)
        }
    }
}
