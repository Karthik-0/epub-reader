package com.example.epub_reader_poc

import android.app.AlertDialog
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.ActionMode
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.lifecycle.lifecycleScope
import java.io.File
import kotlinx.coroutines.launch
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.positions
import org.readium.r2.shared.publication.services.positionsByReadingOrder
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

@OptIn(ExperimentalReadiumApi::class)
class ReadiumReaderActivity : AppCompatActivity() {
    private val containerId = 0x424242
    private val actionBookmark = View.generateViewId()
    private val actionBookmarks = View.generateViewId()
    private val actionHighlights = View.generateViewId()
    private val actionDisplay = View.generateViewId()
    private val actionHighlightSelection = View.generateViewId()

    private val highlightGroup = "user-highlights"
    private val highlightDecorations = mutableListOf<Decoration>()

    private var publication: Publication? = null
    private var navigatorFragment: EpubNavigatorFragment? = null
    private var currentLocator: Locator? = null
    private var currentChapterIndex: Int = 0
    private var currentPageInChapter: Int = 0
    private var currentProgressPercent: Double = 0.0

    private lateinit var bookId: String
    private lateinit var filePath: String
    private lateinit var requestedTitle: String
    private lateinit var toolbar: Toolbar
    private var initialChapterIndex: Int = 0
    private var initialPageInChapter: Int = 0
    private var initialProgressPercent: Double = 0.0

    private var currentFontScale: Double = 1.0
    private var currentTheme: Theme = Theme.SEPIA
    private var currentFontFamily: String = "Iowan Old Style"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        bookId = intent.getStringExtra(EXTRA_BOOK_ID).orEmpty()
        requestedTitle = intent.getStringExtra(EXTRA_TITLE) ?: "Book"
        filePath = intent.getStringExtra(EXTRA_FILE_PATH).orEmpty()
        initialChapterIndex = intent.getIntExtra(EXTRA_INITIAL_CHAPTER_INDEX, 0)
        initialPageInChapter = intent.getIntExtra(EXTRA_INITIAL_PAGE_IN_CHAPTER, 0)
        initialProgressPercent = intent.getDoubleExtra(EXTRA_INITIAL_PROGRESS_PERCENT, 0.0)

        val initialFontSize = intent.getDoubleExtra(EXTRA_FONT_SIZE, 17.0)
        currentFontScale = (initialFontSize / 17.0).coerceIn(0.8, 1.6)
        currentFontFamily = intent.getStringExtra(EXTRA_FONT_FAMILY) ?: "Iowan Old Style"
        currentTheme = when (intent.getStringExtra(EXTRA_COLOR_MODE)?.lowercase()) {
            "dark" -> Theme.DARK
            "white" -> Theme.LIGHT
            else -> Theme.SEPIA
        }

        if (bookId.isBlank() || filePath.isBlank()) {
            finish()
            return
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(themeBackgroundColor(currentTheme))
        }

        toolbar = Toolbar(this).apply {
            title = requestedTitle
            setNavigationIcon(android.R.drawable.ic_media_previous)
            setNavigationOnClickListener { finish() }
            popupTheme = androidx.appcompat.R.style.ThemeOverlay_AppCompat
            setBackgroundColor(themeBackgroundColor(currentTheme))
            setTitleTextColor(themeForegroundColor(currentTheme))
            navigationIcon?.setTint(themeForegroundColor(currentTheme))

            menu.add(0, actionBookmark, 0, "Bookmark")
            menu.add(0, actionBookmarks, 1, "Bookmarks")
            menu.add(0, actionHighlights, 2, "Highlights")
            menu.add(0, actionDisplay, 3, "Display")

            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    actionBookmark -> {
                        emitToolbarAction("bookmark", dismissAfter = false)
                        Toast.makeText(this@ReadiumReaderActivity, "Bookmark saved", Toast.LENGTH_SHORT).show()
                        true
                    }

                    actionBookmarks -> {
                        emitToolbarAction("bookmarks", dismissAfter = true)
                        true
                    }

                    actionHighlights -> {
                        emitToolbarAction("highlights", dismissAfter = true)
                        true
                    }

                    actionDisplay -> {
                        showDisplayDialog()
                        true
                    }

                    else -> false
                }
            }
        }

        val container = FrameLayout(this).apply {
            id = containerId
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }

        root.addView(
            toolbar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.TOP },
        )
        root.addView(container)
        setContentView(root)

        lifecycleScope.launch {
            openPublicationAndRender(savedInstanceState)
        }
    }

    override fun onPause() {
        super.onPause()
        emitCurrentPosition()
    }

    private suspend fun openPublicationAndRender(savedInstanceState: Bundle?) {
        val file = File(filePath)
        if (!file.exists()) {
            showErrorAndClose("File not found: $filePath")
            return
        }

        val httpClient = DefaultHttpClient()
        val assetRetriever = AssetRetriever(contentResolver, httpClient)
        val publicationOpener = PublicationOpener(
            DefaultPublicationParser(this, httpClient, assetRetriever, null),
        )

        val absoluteUrl = Uri.fromFile(file).toAbsoluteUrl()
        if (absoluteUrl == null) {
            showErrorAndClose("Invalid publication URL")
            return
        }

        val asset = assetRetriever.retrieve(absoluteUrl).getOrElse {
            showErrorAndClose("Failed to load publication asset: ${it.message}")
            return
        }

        val openedPublication = publicationOpener.open(asset, allowUserInteraction = true).getOrElse {
            showErrorAndClose("Failed to open publication: ${it.message}")
            return
        }

        publication = openedPublication

        val initialLocator = buildInitialLocator(openedPublication)
        val navigatorConfig = EpubNavigatorFragment.Configuration().apply {
            selectionActionModeCallback = buildSelectionActionModeCallback()
        }

        val navigatorFactory = EpubNavigatorFactory(openedPublication)
        supportFragmentManager.fragmentFactory = navigatorFactory.createFragmentFactory(
            initialLocator = initialLocator,
            initialPreferences = EpubPreferences(
                fontFamily = currentFontFamily,
                fontSize = currentFontScale,
                theme = currentTheme,
            ),
            listener = null,
            paginationListener = object : EpubNavigatorFragment.PaginationListener {
                override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
                    currentLocator = locator
                    currentPageInChapter = pageIndex.coerceAtLeast(0)
                    currentChapterIndex = findChapterIndex(openedPublication, locator)
                    val progression = locator.locations.totalProgression ?: (initialProgressPercent / 100.0)
                    currentProgressPercent = (progression * 100.0).coerceIn(0.0, 100.0)
                    emitCurrentPosition()
                }

                override fun onPageLoaded() = Unit
            },
            config = navigatorConfig,
        )

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .add(containerId, EpubNavigatorFragment::class.java, Bundle(), NAVIGATOR_TAG)
                .commitNow()
        }

        navigatorFragment = supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment
    }

    private fun buildSelectionActionModeCallback(): ActionMode.Callback {
        return object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                menu.add(0, actionHighlightSelection, 0, "Highlight")
                    .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                return true
            }

            override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean = false

            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                if (item.itemId != actionHighlightSelection) return false
                showHighlightColorDialog(mode)
                return true
            }

            override fun onDestroyActionMode(mode: ActionMode) = Unit
        }
    }

    private fun showHighlightColorDialog(mode: ActionMode) {
        val colorOptions = listOf(
            "Yellow" to Color.parseColor("#FFE760"),
            "Blue" to Color.parseColor("#9FC8FF"),
            "Pink" to Color.parseColor("#F7A8D0"),
            "Orange" to Color.parseColor("#F5C373"),
        )
        val swatches = colorOptions.map { (_, color) ->
            SpannableString("⬤").apply {
                setSpan(ForegroundColorSpan(color), 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Highlight color")
            .setItems(swatches) { _, which ->
                val (name, tint) = colorOptions[which]
                addHighlightFromSelection(name.lowercase(), tint)
                mode.finish()
            }
            .setOnCancelListener { mode.finish() }
            .show()
    }

    private fun addHighlightFromSelection(colorName: String, tint: Int) {
        lifecycleScope.launch {
            val fragment = navigatorFragment ?: return@launch
            val selection: Selection = fragment.currentSelection() ?: return@launch
            val locator = selection.locator
            val selectedText = locator.text?.highlight?.trim().orEmpty()

            if (selectedText.isEmpty()) {
                fragment.clearSelection()
                return@launch
            }

            val decoration = Decoration(
                id = System.currentTimeMillis().toString(),
                locator = locator,
                style = Decoration.Style.Highlight(tint = tint),
            )
            highlightDecorations.add(decoration)
            fragment.applyDecorations(highlightDecorations, highlightGroup)
            fragment.clearSelection()

            ReadiumBridge.emitHighlightCreated(
                bookId = bookId,
                chapterIndex = findChapterIndex(publication ?: return@launch, locator),
                pageInChapter = currentPageInChapter,
                progressPercent = currentProgressPercent,
                color = colorName,
                text = selectedText,
            )
        }
    }

    private fun showDisplayDialog() {
        val options = arrayOf("Text size", "Theme", "Font")
        AlertDialog.Builder(this)
            .setTitle("Display")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showTextSizeDialog()
                    1 -> showThemeDialog()
                    2 -> showFontFamilyDialog()
                }
            }
            .show()
    }

    private fun showTextSizeDialog() {
        val labels = arrayOf("Small", "Medium", "Large", "XL")
        val scales = arrayOf(0.9, 1.0, 1.18, 1.35)
        AlertDialog.Builder(this)
            .setTitle("Text size")
            .setItems(labels) { _, which ->
                currentFontScale = scales[which]
                applyDisplayPreferences()
            }
            .show()
    }

    private fun showThemeDialog() {
        val labels = arrayOf("Sepia", "White", "Dark")
        val themes = arrayOf(Theme.SEPIA, Theme.LIGHT, Theme.DARK)
        AlertDialog.Builder(this)
            .setTitle("Theme")
            .setItems(labels) { _, which ->
                currentTheme = themes[which]
                applyDisplayPreferences()
            }
            .show()
    }

    private fun showFontFamilyDialog() {
        val fonts = arrayOf(
            "Iowan Old Style",
            "Athelas",
            "Seravek",
            "OpenDyslexic",
            "IA Writer Duospace",
        )
        AlertDialog.Builder(this)
            .setTitle("Font")
            .setItems(fonts) { _, which ->
                currentFontFamily = fonts[which]
                applyDisplayPreferences()
            }
            .show()
    }

    private fun applyDisplayPreferences() {
        navigatorFragment?.submitPreferences(
            EpubPreferences(
                fontFamily = currentFontFamily,
                fontSize = currentFontScale,
                theme = currentTheme,
            ),
        )

        val bg = themeBackgroundColor(currentTheme)
        val fg = themeForegroundColor(currentTheme)
        toolbar.apply {
            setBackgroundColor(bg)
            setTitleTextColor(fg)
            navigationIcon?.setTint(fg)
        }
        window.decorView.setBackgroundColor(bg)
    }

    private fun themeBackgroundColor(theme: Theme): Int {
        return when (theme) {
            Theme.DARK -> Color.parseColor("#121212")
            Theme.LIGHT -> Color.parseColor("#FFFFFF")
            Theme.SEPIA -> Color.parseColor("#F6F0E4")
        }
    }

    private fun themeForegroundColor(theme: Theme): Int {
        return when (theme) {
            Theme.DARK -> Color.parseColor("#F4F4F4")
            Theme.LIGHT, Theme.SEPIA -> Color.parseColor("#1E1E1E")
        }
    }

    private suspend fun buildInitialLocator(publication: Publication): Locator? {
        val chapter = initialChapterIndex.coerceAtLeast(0)
        val page = initialPageInChapter.coerceAtLeast(0)

        val positionsByReadingOrder = publication.positionsByReadingOrder()
        if (positionsByReadingOrder.isNotEmpty() && chapter in positionsByReadingOrder.indices) {
            val positions = positionsByReadingOrder[chapter]
            if (positions.isNotEmpty()) {
                return positions[page.coerceAtMost(positions.lastIndex)]
            }
        }

        val flatPositions = publication.positions()
        if (flatPositions.isNotEmpty()) {
            val progression = (initialProgressPercent / 100.0).coerceIn(0.0, 1.0)
            val index = (progression * (flatPositions.size - 1)).toInt().coerceIn(0, flatPositions.size - 1)
            return flatPositions[index]
        }

        return null
    }

    private fun findChapterIndex(publication: Publication, locator: Locator): Int {
        val locatorHref = locator.href.toString().substringBefore('#')
        val idx = publication.readingOrder.indexOfFirst { link ->
            val href = link.href.toString().substringBefore('#')
            href == locatorHref || locatorHref.endsWith(href)
        }
        return if (idx >= 0) idx else 0
    }

    private fun emitCurrentPosition() {
        ReadiumBridge.emitPosition(
            bookId = bookId,
            chapterIndex = currentChapterIndex,
            pageInChapter = currentPageInChapter,
            progressPercent = currentProgressPercent,
        )
    }

    private fun emitToolbarAction(action: String, dismissAfter: Boolean) {
        ReadiumBridge.emitToolbarAction(
            bookId = bookId,
            action = action,
            chapterIndex = currentChapterIndex,
            pageInChapter = currentPageInChapter,
            progressPercent = currentProgressPercent,
        )

        if (dismissAfter) {
            finish()
        }
    }

    private fun showErrorAndClose(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }

    companion object {
        const val EXTRA_BOOK_ID = "extra_book_id"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_FILE_PATH = "extra_file_path"
        const val EXTRA_INITIAL_CHAPTER_INDEX = "extra_initial_chapter_index"
        const val EXTRA_INITIAL_PAGE_IN_CHAPTER = "extra_initial_page_in_chapter"
        const val EXTRA_INITIAL_PROGRESS_PERCENT = "extra_initial_progress_percent"
        const val EXTRA_FONT_SIZE = "extra_font_size"
        const val EXTRA_FONT_FAMILY = "extra_font_family"
        const val EXTRA_COLOR_MODE = "extra_color_mode"
        private const val NAVIGATOR_TAG = "readium_epub_navigator"
    }
}
