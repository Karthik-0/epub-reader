package com.example.epub_reader_poc

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "com.example.epub_reader_poc/readium"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				if (call.method != "openReadium") {
					result.notImplemented()
					return@setMethodCallHandler
				}

				ReadiumBridge.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)

				val bookId = call.argument<String>("bookId")
				val title = call.argument<String>("title") ?: "Book"
				val filePath = call.argument<String>("filePath")
				val initialChapterIndex = call.argument<Int>("initialChapterIndex") ?: 0
				val initialPageInChapter = call.argument<Int>("initialPageInChapter") ?: 0
				val initialProgressPercent = call.argument<Double>("initialProgressPercent") ?: 0.0
				val fontSize = call.argument<Double>("fontSize") ?: 17.0
				val fontFamily = call.argument<String>("fontFamily") ?: "Iowan Old Style"
				val colorMode = call.argument<String>("colorMode") ?: "sepia"

				if (bookId.isNullOrBlank() || filePath.isNullOrBlank()) {
					result.error("invalid_args", "Missing bookId or filePath", null)
					return@setMethodCallHandler
				}

				val intent = Intent(this, ReadiumReaderActivity::class.java).apply {
					putExtra(ReadiumReaderActivity.EXTRA_BOOK_ID, bookId)
					putExtra(ReadiumReaderActivity.EXTRA_TITLE, title)
					putExtra(ReadiumReaderActivity.EXTRA_FILE_PATH, filePath)
					putExtra(ReadiumReaderActivity.EXTRA_INITIAL_CHAPTER_INDEX, initialChapterIndex)
					putExtra(ReadiumReaderActivity.EXTRA_INITIAL_PAGE_IN_CHAPTER, initialPageInChapter)
					putExtra(ReadiumReaderActivity.EXTRA_INITIAL_PROGRESS_PERCENT, initialProgressPercent)
					putExtra(ReadiumReaderActivity.EXTRA_FONT_SIZE, fontSize)
					putExtra(ReadiumReaderActivity.EXTRA_FONT_FAMILY, fontFamily)
					putExtra(ReadiumReaderActivity.EXTRA_COLOR_MODE, colorMode)
				}
				startActivity(intent)
				result.success(null)
			}

		ReadiumBridge.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
	}
}
