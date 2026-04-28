import Flutter
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let readiumChannelName = "com.example.epub_reader_poc/readium"
  private var readiumChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReadiumBridge") else {
      return
    }
    let channel = FlutterMethodChannel(name: readiumChannelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleReadium(call: call, result: result)
    }
    readiumChannel = channel
  }

  private func handleReadium(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "openReadium" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let args = call.arguments as? [String: Any],
      let filePath = args["filePath"] as? String,
      !filePath.isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "Missing filePath",
          details: nil
        )
      )
      return
    }

    guard
      let bookId = args["bookId"] as? String,
      !bookId.isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "Missing bookId",
          details: nil
        )
      )
      return
    }

    let title = (args["title"] as? String) ?? "Book"
    let initialChapterIndex = (args["initialChapterIndex"] as? NSNumber)?.intValue ?? 0
    let initialPageInChapter = (args["initialPageInChapter"] as? NSNumber)?.intValue ?? 0
    let initialProgressPercent = (args["initialProgressPercent"] as? NSNumber)?.doubleValue ?? 0
    let fontSize = (args["fontSize"] as? NSNumber)?.doubleValue ?? 17.0
    let fontFamily = (args["fontFamily"] as? String) ?? "Iowan Old Style"
    let colorMode = (args["colorMode"] as? String) ?? "sepia"

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "presentation_error",
          message: "No active view controller to present native reader",
          details: nil
        )
      )
      return
    }

    let prefs = ReadiumPresentationPreferences(
      fontSize: fontSize,
      fontFamily: fontFamily,
      colorMode: colorMode
    )

    let controller = ReadiumNativeViewController(
      bookId: bookId,
      bookTitle: title,
      filePath: filePath,
      initialChapterIndex: initialChapterIndex,
      initialPageInChapter: initialPageInChapter,
      initialProgressPercent: initialProgressPercent,
      initialPreferences: prefs,
      onPositionChanged: { [weak self] payload in
        self?.readiumChannel?.invokeMethod("onReadiumPositionChanged", arguments: payload)
      },
      onToolbarAction: { [weak self] payload in
        self?.readiumChannel?.invokeMethod("onReadiumToolbarAction", arguments: payload)
      },
      onHighlightCreated: { [weak self] payload in
        self?.readiumChannel?.invokeMethod("onReadiumHighlightCreated", arguments: payload)
      }
    )

    let host = UINavigationController(rootViewController: controller)
    host.modalPresentationStyle = .fullScreen
    presenter.present(host, animated: true)
    result(nil)
  }

  private func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let initialBase: UIViewController?
    if let base {
      initialBase = base
    } else {
      initialBase = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?
        .rootViewController
    }

    if let nav = initialBase as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = initialBase as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = initialBase?.presentedViewController {
      return topViewController(base: presented)
    }
    return initialBase
  }
}

struct ReadiumPresentationPreferences {
  var fontSize: Double
  var fontFamily: String
  var colorMode: String

  var theme: Theme {
    switch colorMode.lowercased() {
    case "dark":
      return .dark
    case "white":
      return .light
    default:
      return .sepia
    }
  }

  var epubPreferences: EPUBPreferences {
    // Readium uses a scale factor where 1.0 is the baseline size.
    let normalizedFontSize = max(0.8, min(1.6, fontSize / 17.0))
    return EPUBPreferences(
      fontFamily: FontFamily(rawValue: fontFamily),
      fontSize: normalizedFontSize,
      theme: theme
    )
  }

  var chromeBackgroundColor: UIColor {
    theme.backgroundColor.uiColor
  }

  var chromeForegroundColor: UIColor {
    theme.contentColor.uiColor
  }
}

final class ReadiumNativeViewController: UIViewController {
  private let bookId: String
  private let bookTitle: String
  private let filePath: String
  private let initialChapterIndex: Int
  private let initialPageInChapter: Int
  private let initialProgressPercent: Double
  private let onPositionChanged: ([String: Any]) -> Void
  private let onToolbarAction: ([String: Any]) -> Void
  private let onHighlightCreated: ([String: Any]) -> Void

  private let httpClient: HTTPClient = DefaultHTTPClient()
  private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
  private lazy var publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
      httpClient: httpClient,
      assetRetriever: assetRetriever,
      pdfFactory: DefaultPDFDocumentFactory()
    )
  )

  private var publication: Publication?
  private var positionsByChapter: [[Locator]] = []
  private weak var navigator: EPUBNavigatorViewController?
  private var currentChapterIndex: Int = 0
  private var currentPageInChapter: Int = 0
  private var currentProgressPercent: Double = 0

  private let highlightGroup = "user-highlights"
  private var highlightDecorations: [Decoration] = []
  private var pendingSelection: Selection?
  private var presentationPreferences: ReadiumPresentationPreferences
  private var bookmarkButton: UIBarButtonItem?
  private var bookmarkedPageKeys = Set<String>()

  init(
    bookId: String,
    bookTitle: String,
    filePath: String,
    initialChapterIndex: Int,
    initialPageInChapter: Int,
    initialProgressPercent: Double,
    initialPreferences: ReadiumPresentationPreferences,
    onPositionChanged: @escaping ([String: Any]) -> Void,
    onToolbarAction: @escaping ([String: Any]) -> Void,
    onHighlightCreated: @escaping ([String: Any]) -> Void
  ) {
    self.bookId = bookId
    self.bookTitle = bookTitle
    self.filePath = filePath
    self.initialChapterIndex = initialChapterIndex
    self.initialPageInChapter = initialPageInChapter
    self.initialProgressPercent = initialProgressPercent
    self.presentationPreferences = initialPreferences
    self.onPositionChanged = onPositionChanged
    self.onToolbarAction = onToolbarAction
    self.onHighlightCreated = onHighlightCreated
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = presentationPreferences.chromeBackgroundColor
    title = bookTitle

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "chevron.backward"),
      style: .plain,
      target: self,
      action: #selector(closeTapped)
    )

    let menuButton = UIBarButtonItem(
      image: UIImage(systemName: "ellipsis.circle"),
      menu: buildFeatureMenu()
    )
    let bookmarkButton = UIBarButtonItem(
      image: UIImage(systemName: "bookmark"),
      style: .plain,
      target: self,
      action: #selector(bookmarkTapped)
    )
    self.bookmarkButton = bookmarkButton
    navigationItem.rightBarButtonItems = [menuButton, bookmarkButton]
    updateBookmarkButtonState()

    applyChromeAppearance()

    let loading = UIActivityIndicatorView(style: .large)
    loading.translatesAutoresizingMaskIntoConstraints = false
    loading.startAnimating()
    view.addSubview(loading)

    NSLayoutConstraint.activate([
      loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])

    Task {
      do {
        try await openAndRenderNavigator()
      } catch {
        showError(message: "Failed to open publication: \(error.localizedDescription)")
      }
      loading.removeFromSuperview()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    emitCurrentPosition()
  }

  private func applyChromeAppearance() {
    let bg = presentationPreferences.chromeBackgroundColor
    let fg = presentationPreferences.chromeForegroundColor
    navigationController?.navigationBar.tintColor = fg
    navigationController?.navigationBar.barTintColor = bg
    navigationController?.navigationBar.backgroundColor = bg
    navigationController?.navigationBar.titleTextAttributes = [
      .foregroundColor: fg,
    ]
    navigationController?.navigationBar.isTranslucent = false
    view.backgroundColor = bg
  }

  private func openAndRenderNavigator() async throws {
    guard let absoluteURL = URL(fileURLWithPath: filePath).anyURL.absoluteURL else {
      throw NSError(domain: "Readium", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
    }

    let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
    let publication = try await publicationOpener.open(
      asset: asset,
      allowUserInteraction: true,
      sender: self
    ).get()

    self.publication = publication
    positionsByChapter = (try? await publication.positionsByReadingOrder().get()) ?? []
    let initialLocation = await initialLocator(for: publication)

    let navigator = try EPUBNavigatorViewController(
      publication: publication,
      initialLocation: initialLocation,
      config: EPUBNavigatorViewController.Configuration(
        preferences: presentationPreferences.epubPreferences,
        defaults: EPUBDefaults()
      )
    )
    navigator.delegate = self
    self.navigator = navigator

    addChild(navigator)
    navigator.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(navigator.view)

    NSLayoutConstraint.activate([
      navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      navigator.view.topAnchor.constraint(equalTo: view.topAnchor),
      navigator.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    navigator.didMove(toParent: self)
  }

  private func initialLocator(for publication: Publication) async -> Locator? {
    let chapter = max(0, initialChapterIndex)
    let page = max(0, initialPageInChapter)

    if chapter < positionsByChapter.count, !positionsByChapter[chapter].isEmpty {
      let chapterPositions = positionsByChapter[chapter]
      return chapterPositions[min(page, chapterPositions.count - 1)]
    }

    if
      let allPositions = try? await publication.positions().get(),
      !allPositions.isEmpty
    {
      let progression = max(0, min(1, initialProgressPercent / 100.0))
      let index = min(Int(progression * Double(allPositions.count - 1)), allPositions.count - 1)
      return allPositions[index]
    }

    return nil
  }

  private func showError(message: String) {
    let label = UILabel()
    label.text = message
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func emitCurrentPosition() {
    onPositionChanged([
      "bookId": bookId,
      "chapterIndex": currentChapterIndex,
      "pageInChapter": currentPageInChapter,
      "progressPercent": currentProgressPercent,
    ])
  }

  private func emitToolbarAction(_ action: String) {
    onToolbarAction([
      "bookId": bookId,
      "action": action,
      "chapterIndex": currentChapterIndex,
      "pageInChapter": currentPageInChapter,
      "progressPercent": currentProgressPercent,
    ])
  }

  private func emitHighlightCreated(text: String, color: String, locator: Locator) {
    onHighlightCreated([
      "bookId": bookId,
      "text": text,
      "color": color,
      "chapterIndex": chapterIndex(for: locator),
      "pageInChapter": currentPageInChapter,
      "progressPercent": currentProgressPercent,
    ])
  }

  private func buildFeatureMenu() -> UIMenu {
    let bookmarks = UIAction(title: "Bookmarks", image: UIImage(systemName: "book")) { [weak self] _ in
      self?.emitToolbarAction("bookmarks")
      self?.dismiss(animated: true)
    }
    let highlights = UIAction(title: "Highlights", image: UIImage(systemName: "highlighter")) { [weak self] _ in
      self?.emitToolbarAction("highlights")
      self?.dismiss(animated: true)
    }
    let display = UIAction(title: "Display", image: UIImage(systemName: "textformat.size")) { [weak self] _ in
      self?.presentDisplaySheet()
    }

    return UIMenu(title: "Reader", children: [bookmarks, highlights, display])
  }

  private func presentDisplaySheet() {
    let sheet = UIAlertController(title: "Display", message: nil, preferredStyle: .actionSheet)

    let fontSizes: [Double] = [14, 17, 20, 23]
    for size in fontSizes {
      sheet.addAction(UIAlertAction(title: "Font Size \(Int(size))", style: .default) { [weak self] _ in
        self?.presentationPreferences.fontSize = size
        self?.applyReaderPreferences()
      })
    }

    sheet.addAction(UIAlertAction(title: "Sepia", style: .default) { [weak self] _ in
      self?.presentationPreferences.colorMode = "sepia"
      self?.applyReaderPreferences()
    })
    sheet.addAction(UIAlertAction(title: "White", style: .default) { [weak self] _ in
      self?.presentationPreferences.colorMode = "white"
      self?.applyReaderPreferences()
    })
    sheet.addAction(UIAlertAction(title: "Dark", style: .default) { [weak self] _ in
      self?.presentationPreferences.colorMode = "dark"
      self?.applyReaderPreferences()
    })

    let fonts = ["Iowan Old Style", "Athelas", "Seravek", "OpenDyslexic", "IA Writer Duospace"]
    for font in fonts {
      sheet.addAction(UIAlertAction(title: "Font: \(font)", style: .default) { [weak self] _ in
        self?.presentationPreferences.fontFamily = font
        self?.applyReaderPreferences()
      })
    }

    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

    if let popover = sheet.popoverPresentationController {
      popover.barButtonItem = navigationItem.rightBarButtonItems?.first
    }
    present(sheet, animated: true)
  }

  private func applyReaderPreferences() {
    navigator?.submitPreferences(presentationPreferences.epubPreferences)
    applyChromeAppearance()
  }

  private func chapterIndex(for locator: Locator) -> Int {
    guard let publication else { return currentChapterIndex }
    let locatorHref = normalizedHref(locator.href)
    return publication.readingOrder.firstIndex(where: {
      let href = normalizedHref($0.href)
      return href == locatorHref || locatorHref.hasSuffix(href)
    }) ?? currentChapterIndex
  }

  private func normalizedHref(_ href: Any) -> String {
    let value = String(describing: href)
    return value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
  }

  private func bookmarkKey(chapter: Int, page: Int) -> String {
    "\(chapter):\(page)"
  }

  private func currentBookmarkKey() -> String {
    bookmarkKey(chapter: currentChapterIndex, page: currentPageInChapter)
  }

  private func updateBookmarkButtonState() {
    let isBookmarked = bookmarkedPageKeys.contains(currentBookmarkKey())
    bookmarkButton?.image = UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
  }

  private func presentHighlightSwatchMenu(for selection: Selection) {
    pendingSelection = selection

    let sheet = UIAlertController(title: "Highlight", message: "Choose a color", preferredStyle: .actionSheet)
    sheet.addAction(UIAlertAction(title: "🟡", style: .default) { [weak self] _ in
      self?.applyHighlight(colorName: "yellow", tint: UIColor(red: 1.0, green: 0.92, blue: 0.35, alpha: 1.0))
    })
    sheet.addAction(UIAlertAction(title: "🔵", style: .default) { [weak self] _ in
      self?.applyHighlight(colorName: "blue", tint: UIColor(red: 0.62, green: 0.78, blue: 1.0, alpha: 1.0))
    })
    sheet.addAction(UIAlertAction(title: "🩷", style: .default) { [weak self] _ in
      self?.applyHighlight(colorName: "pink", tint: UIColor(red: 0.98, green: 0.66, blue: 0.82, alpha: 1.0))
    })
    sheet.addAction(UIAlertAction(title: "🟠", style: .default) { [weak self] _ in
      self?.applyHighlight(colorName: "orange", tint: UIColor(red: 0.96, green: 0.76, blue: 0.45, alpha: 1.0))
    })
    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
      self?.pendingSelection = nil
      self?.navigator?.clearSelection()
    })

    if let popover = sheet.popoverPresentationController,
       let frame = selection.frame {
      popover.sourceView = view
      popover.sourceRect = frame
    } else if let popover = sheet.popoverPresentationController {
      popover.barButtonItem = navigationItem.rightBarButtonItems?.first
    }

    if presentedViewController == nil {
      present(sheet, animated: true)
    }
  }

  private func applyHighlight(colorName: String, tint: UIColor) {
    guard let selection = pendingSelection else { return }
    pendingSelection = nil

    let decoration = Decoration(
      id: UUID().uuidString,
      locator: selection.locator,
      style: .highlight(tint: tint)
    )
    highlightDecorations.append(decoration)
    navigator?.apply(decorations: highlightDecorations, in: highlightGroup)
    navigator?.clearSelection()

    let text = selection.locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !text.isEmpty {
      emitHighlightCreated(text: text, color: colorName, locator: selection.locator)
    }
  }

  @objc
  private func closeTapped() {
    dismiss(animated: true)
  }

  @objc
  private func bookmarkTapped() {
    let key = currentBookmarkKey()
    if bookmarkedPageKeys.contains(key) {
      bookmarkedPageKeys.remove(key)
      emitToolbarAction("bookmark_remove")
    } else {
      bookmarkedPageKeys.insert(key)
      emitToolbarAction("bookmark_add")
    }
    updateBookmarkButtonState()
  }
}

extension ReadiumNativeViewController: EPUBNavigatorDelegate {
  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    guard let publication else { return }

    let locatorHref = normalizedHref(locator.href)
    let chapterIndex = publication.readingOrder.firstIndex(where: {
      let href = normalizedHref($0.href)
      return href == locatorHref || locatorHref.hasSuffix(href)
    }) ?? 0

    currentChapterIndex = chapterIndex

    if chapterIndex < positionsByChapter.count {
      let chapterPositions = positionsByChapter[chapterIndex]
      let page = chapterPositions.firstIndex(where: {
        let sameHref = normalizedHref($0.href) == locatorHref
        let lhs = $0.locations.position ?? -1
        let rhs = locator.locations.position ?? -2
        return sameHref && lhs == rhs
      }) ?? 0
      currentPageInChapter = page
    } else {
      currentPageInChapter = 0
    }

    let progression = locator.locations.totalProgression ?? (initialProgressPercent / 100.0)
    currentProgressPercent = max(0, min(100, progression * 100.0))
    updateBookmarkButtonState()
    emitCurrentPosition()
  }

  func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
    presentHighlightSwatchMenu(for: selection)
    return false
  }
}
