// One site in a window without any frame (frameless-app <url>, browsers.nix):
// no title bar, no window controls, no menu. The page drags the window from
// its `app-region: drag` parts; Super+drag moves it anyway. Each site keeps its
// own profile (cookies, IndexedDB, its service worker) and one window: opened
// again, the window comes forward. Links off the site open in the default
// browser. Reload, devtools and zoom keep their usual keys; every other key is
// the page's.
const { app, BrowserWindow, Menu, session, shell } = require("electron")
const path = require("node:path")

const site = new URL(process.argv.find((a) => /^https?:\/\//.test(a)))

// The window's class (X11) and app_id (Wayland) is the name in the
// package.json frameless-app writes for the site: its host, dots as dashes.
app.setPath("userData", path.join(app.getPath("appData"), "frameless-apps", site.host))
Menu.setApplicationMenu(null)

if (!app.requestSingleInstanceLock()) app.quit()
else {
  let win
  app.on("second-instance", () => {
    if (!win) return
    if (win.isMinimized()) win.restore()
    win.focus()
  })
  app.whenReady().then(() => {
    const own = (u) => {
      try { return new URL(u).origin === site.origin } catch { return false }
    }
    // The microphone (dictation), notifications, the clipboard: the site's own pages may.
    session.defaultSession.setPermissionRequestHandler((_wc, _perm, done, details) => done(own(details.requestingUrl)))
    session.defaultSession.setPermissionCheckHandler((_wc, _perm, origin) => own(origin))
    win = new BrowserWindow({
      width: 1600,
      height: 1000,
      frame: false,
      backgroundColor: "#24201d",
      webPreferences: { preload: path.join(__dirname, "preload.js") },
    })
    win.webContents.setWindowOpenHandler(({ url }) => {
      if (own(url)) return { action: "allow" }
      shell.openExternal(url)
      return { action: "deny" }
    })
    win.webContents.on("before-input-event", (event, input) => {
      if (input.type !== "keyDown") return
      const mod = input.control || input.meta
      const key = input.key.toLowerCase()
      const wc = win.webContents
      if (key === "f12" || (mod && input.shift && key === "i")) wc.toggleDevTools()
      else if (key === "f5" || (mod && key === "r")) input.shift ? wc.reloadIgnoringCache() : wc.reload()
      else if (mod && (key === "=" || key === "+")) wc.setZoomLevel(wc.getZoomLevel() + 0.5)
      else if (mod && key === "-") wc.setZoomLevel(wc.getZoomLevel() - 0.5)
      else if (mod && key === "0") wc.setZoomLevel(0)
      else return
      event.preventDefault()
    })
    win.loadURL(site.href)
  })
  app.on("window-all-closed", () => app.quit())
}
