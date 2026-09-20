import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons

// Concave rounded-corner fills, in two independent families:
//
//   screen — four fills flush with the physical display corners, over the bar,
//     so the picture appears to bend into the bezel.
//   bar — the two fills at the bar's inner edge, so the desktop bends into the
//     bar instead of starting square below it. Follows the bar's position and
//     size, and drops out while the bar is hidden or transparent.
//
// Settings are inline on this plugin's entry in ~/.config/omarchy/shell.json:
//
//   { "id": "turbinebmw.corners", "screenRadius": "", "barRadius": "",
//     "screenColor": "#000000", "barColor": "", "screen": true, "bar": true }
//
// An empty or missing radius follows Hyprland's decoration:rounding, so the
// fills match the windows; a number pins it. An empty barColor follows the
// theme's bar background.
Item {
  id: root

  // Injected by the host: scoped shell facade (bar state) and our manifest.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "turbinebmw.corners"

  property var settings: ({})

  function setting(key, fallback) {
    var value = settings ? settings[key] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  // Style.cornerRadius mirrors Hyprland's decoration:rounding.
  readonly property int screenRadius: Math.max(0, Number(setting("screenRadius", Style.cornerRadius)) || 0)
  readonly property int barRadius: Math.max(0, Number(setting("barRadius", Style.cornerRadius)) || 0)
  readonly property color screenColor: setting("screenColor", "#000000")
  readonly property color barColor: setting("barColor", Color.bar.background)
  readonly property bool screenOn: setting("screen", true) === true && screenRadius > 0
  readonly property bool barOn: setting("bar", true) === true && barRadius > 0

  readonly property var barState: shell ? shell.bar : null
  readonly property string barEdge: barState ? barState.position : "top"
  readonly property int barSize: barState ? barState.barSize : 0
  // Read from shell.json below rather than shell.barConfig: that snapshot is
  // not refreshed when the bar's double-click transparency toggle flips back.
  property bool barTransparent: false
  readonly property bool barVisible: barSize > 0 && !(barState && barState.barHidden) && !barTransparent

  readonly property var barCornerNames: barEdge === "left" ? ["topLeft", "bottomLeft"]
    : barEdge === "right" ? ["topRight", "bottomRight"]
    : barEdge === "bottom" ? ["bottomLeft", "bottomRight"]
    : ["topLeft", "topRight"]

  // One entry per fill, "<family>:<corner>". The bar family comes first so the
  // screen fills are the younger surfaces and win where the two overlap.
  readonly property var pieces: (barOn && barVisible ? barCornerNames.map(name => "bar:" + name) : [])
    .concat(screenOn ? ["topLeft", "topRight", "bottomLeft", "bottomRight"].map(name => "screen:" + name) : [])

  // The shell only re-reads Hyprland's rounding on startup and theme changes;
  // nudge it when the Hyprland config reloads so an edited rounding applies.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") Style.scheduleRefresh()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var config = JSON.parse(text())
        var plugins = config.plugins || []
        root.barTransparent = !!(config.bar && config.bar.transparent === true)
        var entry = plugins.find(p => p && p.id === root.pluginId)
        root.settings = entry || ({})
      } catch (e) {
        console.warn(root.pluginId + ": could not read settings:", e)
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Scope {
      id: screenScope

      required property ShellScreen modelData

      Variants {
        model: root.pieces

        delegate: PanelWindow {
          id: win

          required property string modelData // "<family>:<corner>", e.g. "bar:topLeft"

          readonly property bool onBar: modelData.startsWith("bar:")
          readonly property string corner: modelData.substring(modelData.indexOf(":") + 1)
          readonly property bool isTop: corner.startsWith("top")
          readonly property bool isLeft: corner.endsWith("Left")
          readonly property int size: onBar ? root.barRadius : root.screenRadius

          screen: screenScope.modelData
          color: "transparent"
          implicitWidth: size
          implicitHeight: size

          anchors.top: isTop
          anchors.bottom: !isTop
          anchors.left: isLeft
          anchors.right: !isLeft

          // Only the bar family clears the bar; the screen family stays flush
          // with the display on every edge, bar included.
          margins.top: onBar && root.barEdge === "top" ? root.barSize : 0
          margins.bottom: onBar && root.barEdge === "bottom" ? root.barSize : 0
          margins.left: onBar && root.barEdge === "left" ? root.barSize : 0
          margins.right: onBar && root.barEdge === "right" ? root.barSize : 0

          WlrLayershell.namespace: "omarchy-corners-" + (onBar ? "bar" : "screen")
          WlrLayershell.layer: WlrLayer.Top
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          // Reserve nothing, and honour nobody else's zone either: the fills are
          // anchored to the raw screen edges and offset only by the margins above.
          exclusionMode: ExclusionMode.Ignore
          mask: Region {}

          CornerFill {
            anchors.fill: parent
            isTop: win.isTop
            isLeft: win.isLeft
            fill: win.onBar ? root.barColor : root.screenColor
          }
        }
      }
    }
  }
}
