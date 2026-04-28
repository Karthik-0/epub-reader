# Product Requirements Document: Flutter EPUB Reader POC

## 1. Overview

### 1.1 Purpose
Build a proof-of-concept Flutter application that demonstrates a Kindle-like EPUB reading experience, validating core technical feasibility and user experience patterns before committing to full product development.

### 1.2 Scope
This POC focuses exclusively on the four foundational reading features: opening books, page navigation, line highlighting, and bookmarking. It is not intended for production release.

### 1.3 Success Criteria
The POC is successful if a user can open an EPUB file from device storage, navigate through it page by page, highlight a passage, bookmark a location, and return to that bookmark in a subsequent session — all with reasonable performance on mid-tier Android and iOS devices.

## 2. Goals and Non-Goals

### 2.1 Goals
- Validate that Flutter can deliver a smooth, Kindle-comparable reading experience
- Establish technical patterns for EPUB parsing, rendering, and persistence
- Identify performance bottlenecks early (large books, image-heavy chapters)
- Produce a working demo that can be shown to stakeholders within a short timeframe

### 2.2 Non-Goals
The POC will not include cloud sync, a built-in bookstore, social features, dictionary lookup, text-to-speech, advanced typography settings, DRM-protected content, PDF support, or multi-device library management. These are out of scope to keep the POC focused.

## 3. Target User

A reader who has EPUB files on their device (sideloaded from sources like Project Gutenberg, Standard Ebooks, or personal purchases) and wants a clean, distraction-free reading interface with the ability to mark passages and return to specific pages.

## 4. Functional Requirements

### 4.1 Open a Book

The user can pick an EPUB file from local device storage via the system file picker. The app parses the file, extracts metadata (title, author, cover image), and renders the first chapter. A simple library view lists all previously opened books with their cover, title, and last-read timestamp, allowing one-tap reopening. When a book is reopened, the reader resumes at the last-read position.

### 4.2 View Pages

Content is rendered as paginated views rather than continuous scroll, mimicking the Kindle experience. Users navigate via horizontal swipe gestures (left/right) or tap zones (tap right side for next, left for previous). The app displays a progress indicator showing current page and total pages within the current chapter, plus overall book progress as a percentage. A table of contents is accessible via a menu, allowing direct jumps to any chapter. Font size has at least three preset levels (small, medium, large) accessible from a reading toolbar.

### 4.3 Highlight Lines

Long-press on text initiates selection mode with draggable handles to adjust the selection range. Once a selection is confirmed, the user can apply a highlight in one of three colors (yellow, green, pink). Highlights persist across sessions and are visually rendered when the user returns to that page. A "Highlights" view lists all highlights for the current book with the highlighted text and a tap-to-jump action. Users can delete a highlight by tapping it and selecting remove.

### 4.4 Bookmark Pages

The user can bookmark the current page via a bookmark icon in the reading toolbar. Bookmarked pages display a visual indicator (a small ribbon or icon) when revisited. A "Bookmarks" view lists all bookmarks for the current book with a snippet of text from that location and a tap-to-jump action. Users can remove a bookmark by tapping the bookmark icon again on the same page or from the bookmarks list.

## 5. Non-Functional Requirements

**Performance:** A 500-page EPUB should open in under three seconds on a mid-tier device. Page transitions should feel instant (under 100ms). Highlight and bookmark actions should persist within 200ms.

**Persistence:** All user data (library, reading positions, highlights, bookmarks) is stored locally. No network calls are required for core functionality.

**Platforms:** Android (API 24+) and iOS (13+). Tablet layouts are nice-to-have but not required for the POC.

**Offline-first:** The entire app must function without an internet connection.

## 6. Technical Approach

**Framework:** Flutter (latest stable channel). For EPUB parsing, evaluate `epubx` and `epub_view` packages — `epub_view` provides paginated rendering out of the box and is the recommended starting point. For local persistence, use `sqflite` or `isar` to store the library, reading positions, highlights, and bookmarks. Use `file_picker` for the open-book flow and `path_provider` to manage the app's document directory where imported EPUBs are copied for stable access.

**Data model sketch:** A `Book` table (id, title, author, cover path, file path, last opened, last position), a `Highlight` table (id, book id, CFI or chapter+offset range, color, text, created at), and a `Bookmark` table (id, book id, position, snippet, created at).

**Position tracking:** Use EPUB CFI (Canonical Fragment Identifier) where supported, or fall back to chapter index plus character offset. This is the trickiest part technically and worth prototyping first.

## 7. User Flows

The primary flow: open app → see library → tap "Add Book" → pick EPUB from storage → book appears in library → tap book → reader opens at last position → swipe to navigate → long-press to highlight → tap bookmark icon to save position → exit app → return later → tap book → resume at saved position with highlights and bookmarks intact.

## 8. Risks and Open Questions

The biggest risk is EPUB rendering fidelity — EPUBs vary widely in CSS complexity, embedded fonts, and image handling, so the POC should be tested against at least five varied real-world EPUBs (a novel, a technical book with code blocks, a book with many images, a non-English book, and a poetry book) to surface rendering issues early. Position stability across font size changes is another known hard problem worth prototyping. An open question is whether to build pagination from scratch or rely on `epub_view`'s built-in pagination — the latter is faster but may limit customization later.

## 9. Timeline Estimate

A reasonable POC timeline is two to three weeks for a single developer: roughly three days for project setup and library/file picker, four days for EPUB parsing and paginated rendering, three days for highlights, two days for bookmarks, and the remainder for persistence, polish, and testing across devices.

## 10. Deliverables

A working Flutter app (Android APK and iOS build), source code in a Git repository, a brief technical writeup of decisions made and limitations discovered, and a short demo video walking through the four core features.
