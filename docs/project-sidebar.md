# Project sidebar

Added 2026-10-15. A left-hand column on every document window for folders you want to keep around.

- The folder-plus button adds a project or folder. It stays until you right-click it and choose Remove from Sidebar, or select it and press Delete. Right-click a project, folder, or file and choose Reveal in Finder to show it in Finder.
- Drag a top-level project up or down to change its place in the list. A gap shows the new spot. The drag never moves a project inside another project, and folders inside a project cannot be reordered. The order is saved in user defaults (`projectSidebarFolders`) and shared by every window.
- The tree shows folders plus files TextMate can open as text (Markdown, HTML, source, and other text types). Hidden files, images, and other binaries stay out. `node_modules` and `Pods` are skipped so the list stays usable.
- Click a file to open it in the current window. Option-click replaces the other tabs, same as the existing file browser.
- Drag the sidebar’s right edge to resize it.

The older File Browser (the Finder-style one) is unchanged.
