# LinguaReader (Mobile)

LinguaReader is a cross-platform language learning application designed to help you learn new vocabulary while reading PDF books. This is the **Mobile Companion App** (Android) that synchronizes with the [Desktop Application](https://github.com/yusufdinc974/LinguaReader).

> [!WARNING]
> **Development Preview**: This build is currently in the **development phase** and has not been fully verified for production release. Features and data stability are subject to change.

## Features

### 📖 Immersive PDF Reader
- Read standard PDF files with a clean, distraction-free interface.
- Tap any word to instantly see its translation.
- Zoom and pan support.

### 🔍 Instant Translation & Privacy
- **Integrated Translation**: Seamlessly translate words without leaving your book.
- **DeepL Integration**: Use your own DeepL API Key for high-quality translations.
- **Offline/Free Fallback**: Automatically falls back to the MyMemory API if no key is provided or quota is exceeded.
- **Privacy First**: API Keys are stored **locally** on your device and are never transmitted to our servers.

### 🧠 Vocabulary Building (SRS)
- **Smart Flashcards**: Words you translate can be saved to custom Word Lists.
- **Spaced Repetition System (SRS)**: The app tracks how familiar you are with each word (Unknown → Seen → Learning → Mastered) and schedules reviews accordingly.
- **Review Quizzes**: Test your knowledge with automatically generated quizzes.

### 🔄 Cross-Platform Sync
- **Local Network Sync**: Synchronize your reading progress, word lists, and vocabulary stats between your Desktop and Mobile devices.
- **No Cloud Required**: Data is transferred directly over your local Wi-Fi network using a secure QR code handshake.

## How it Works

1.  **Open a PDF**: Import any PDF book from your device.
2.  **Translate**: Tap a word you don't know. A popup shows the translation.
3.  **Save**: Add the word to a list (e.g., "Spanish Basics") and rate your familiarity.
4.  **Review**: Go to the "Words" tab to review your saved vocabulary or take a quiz.
5.  **Sync**: Go to Settings -> "Sync with Desktop" to push/pull your data to/from the PC app.

## Related Projects

- **[LinguaReader Desktop](https://github.com/yusufdinc974/LinguaReader)**: The main desktop application (Windows/Linux/macOS) that acts as the sync server and offers a full-screen reading experience.

---
*Created by Yusuf Dinc*
