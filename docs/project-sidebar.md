# Project sidebar

Added 2026-10-15. A left-hand column on every document window for folders you want to keep around. The column runs the full height of the window, and the tab bar starts at its right edge.

- The header has a sidebar button on the left that hides the column. The same button then sits at the left of the tab bar and shows it again. That choice is remembered (`projectSidebarCollapsed`) and shared by every window. The Projects label sits on its own line above the buttons. The folder-plus button adds an existing folder. The filled folder-plus button creates an empty folder. The document-plus button creates an empty file. If a folder or file is selected, the new item is created in that folder and its name is ready to type. Click the empty area of the list to clear the selection; the save panel then asks for a name and location. A new folder outside the sidebar is added to the sidebar. A new file outside the sidebar is added as its own row, lined up with the projects, and opened. Drag that file onto a folder to move it there. Project folders themselves still only reorder.
- A sidebar folder stays until you right-click it and choose Remove from Sidebar, or select it and press Delete. Right-click a project, folder, or file and choose Reveal in Finder to show it in Finder.
- Drag a file or folder from Finder into the empty part of the sidebar to add it. A file opens in a tab. Drag onto a folder to put the item inside that folder; a file opens after it lands. Holding Option copies instead of moving. On another disk, the drop copies. Drag a top-level project up or down to change its place in the list. A gap shows the new spot. That reorder never moves a project inside another project, and folders inside a project cannot be reordered. The order is saved in user defaults (`projectSidebarFolders`) and shared by every window.
- The tree shows folders plus files TextMate can open as text (Markdown, HTML, source, and other text types). Hidden files, images, and other binaries stay out. `node_modules` and `Pods` are skipped so the list stays usable.
- Click a file to open it in the current window. Option-click replaces the other tabs, same as the existing file browser.
- Switching to a tab expands the sidebar to that file and selects it. If the row is off screen, it scrolls to the middle of the list. A file that is not in the sidebar is left alone.
- Drag the sidebar’s right edge to resize it.

The older File Browser (the Finder-style one) is unchanged.

Closing the last tab closes the window. The next one opens at the last size you left it. A window saved as only the title bar and status bar opens at a wide default instead, including when it has no tabs yet. That default can be resized from any corner.
