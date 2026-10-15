# Markdown preview in the editor

Added 2026-10-15. Markdown files get a Preview button on the status bar, next to the language presets.

Preview runs TextMate’s existing Markdown preview command and shows the result in the editor area. Edit switches back to the text. The preview follows the current Markdown file. Leaving Markdown, or opening a file that is not Markdown, returns to the editor.

The Markdown language button only sets the file type. It does not open a separate preview window.

The preview uses the colors of the current editor theme, including a dark theme when the editor theme is dark. If the theme has no background, it follows the system appearance. Code blocks, including fenced blocks, are colored with the theme's comment, string, keyword, number, and function colors.
