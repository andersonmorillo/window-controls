import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Controls.js" as Controls

// Corner controls drawn inside one overlay per screen. Moving a layer-shell
// window's margins does not move it after it maps, so the buttons are plain
// items and only the buttons take clicks.
Item {
  id: root

  property bool opened: true
  property var rows: []
  property var minimized: []
  property var homes: ({})
  property var dragPos: ({})
  property var surfaces: []
  property var placed: ({})
  property bool refreshQueued: false
  property string lastPoll: ""

  // ponytail: at most 12 windows per screen get a corner control. The mask
  // slots are fixed because Region children cannot be created by Repeater.
  // Upgrade path is appending Region objects if a screen ever shows more.
  readonly property int slotCount: 12
  readonly property int chromeW: 102
  readonly property int chromeH: 24
  readonly property int inset: 4
  readonly property int grip: 18

  function open(payloadJson) { opened = true }
  function close() { opened = false }

  function status() {
    var parts = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var seen = placed[row.address]
      parts.push(row.address + "@" + row.x + "," + row.y
        + (seen ? "=" + seen.x + "," + seen.y : "=pending"))
    }
    var shelf = []
    for (var s = 0; s < minimized.length; s++) {
      var chip = minimized[s]
      shelf.push(chip.address + "@" + chip.x + "," + chip.y)
    }
    return (parts.join(" ") || "empty") + " shelf=" + (shelf.join(" ") || "none") + " poll=" + lastPoll
  }

  function workspaceOf(address) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].address === address) return rows[i].workspace
    }
    return ""
  }

  function rememberHome(address, workspace) {
    if (!address || !workspace) return
    var next = {}
    for (var k in homes) next[k] = homes[k]
    next[address] = workspace
    homes = next
  }

  function windowArg(address) {
    return "window = \"address:" + address + "\""
  }

  function dispatch(expr) {
    Hyprland.dispatch(expr)
  }

  function closeWindow(address) {
    dispatch("hl.dsp.window.close({ " + windowArg(address) + " })")
  }

  function toggleMaximized(address) {
    dispatch("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", layout_aware = false, " + windowArg(address) + " })")
  }

  function unsetFullscreen(address) {
    dispatch("hl.dsp.window.fullscreen({ action = \"unset\", layout_aware = false, " + windowArg(address) + " })")
  }

  function floatOn(address) {
    dispatch("hl.dsp.window.float({ action = \"on\", " + windowArg(address) + " })")
  }

  function moveTo(address, x, y) {
    dispatch("hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y) + ", relative = false, " + windowArg(address) + " })")
  }

  function resizeTo(address, w, h) {
    dispatch("hl.dsp.window.resize({ x = " + Math.round(w) + ", y = " + Math.round(h) + ", relative = false, " + windowArg(address) + " })")
  }

  function resizeWindow(address, x, y, w, h) {
    resizeTo(address, Math.max(160, w), Math.max(80, h))
    moveTo(address, x, y)
  }

  // Omarchy's scratchpad is the minimize shelf. The bottom chip opens it again.
  function minimizeWindow(address) {
    rememberHome(address, workspaceOf(address))
    dispatch("hl.dsp.window.move({ workspace = \"special:scratchpad\", follow = false, " + windowArg(address) + " })")
  }

  function restoreWindow(address) {
    var workspace = homes[address] || ""
    if (!workspace) {
      for (var i = 0; i < minimized.length; i++) {
        if (minimized[i].address === address) workspace = minimized[i].fallback
      }
    }
    if (!workspace) return
    dispatch("hl.dsp.window.move({ workspace = \"" + workspace + "\", follow = true, " + windowArg(address) + " })")
  }

  function placeBox(address, box) {
    unsetFullscreen(address)
    floatOn(address)
    moveTo(address, box.x, box.y)
    resizeTo(address, box.w, box.h)
    moveTo(address, box.x, box.y)
  }

  function finishDrag(address, cursorX, cursorY, monitor) {
    var zone = Controls.snapRect(cursorX, cursorY, monitor, 28, 10)
    if (zone) placeBox(address, zone)
  }

  function remember(surface) {
    var next = []
    for (var i = 0; i < surfaces.length; i++) {
      if (surfaces[i] && surfaces[i] !== surface) next.push(surfaces[i])
    }
    next.push(surface)
    surfaces = next
  }

  function forget(surface) {
    var next = []
    for (var i = 0; i < surfaces.length; i++) {
      if (surfaces[i] && surfaces[i] !== surface) next.push(surfaces[i])
    }
    surfaces = next
  }

  function poke() {
    for (var i = 0; i < surfaces.length; i++) {
      if (surfaces[i]) surfaces[i].pokeMask()
    }
  }

  function note(address, x, y) {
    if (!address) return
    var prev = placed[address]
    if (prev && prev.x === x && prev.y === y) return
    var next = {}
    for (var k in placed) next[k] = placed[k]
    next[address] = { x: x, y: y }
    placed = next
  }

  function setDrag(address, x, y) {
    var next = {}
    for (var k in dragPos) next[k] = dragPos[k]
    next[address] = { x: Math.round(x), y: Math.round(y) }
    dragPos = next
    poke()
  }

  function clearDrag(address) {
    var next = {}
    for (var k in dragPos) if (k !== address) next[k] = dragPos[k]
    dragPos = next
    poke()
  }

  function screenFor(monitor) {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0 || !monitor) return null
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === monitor.name) return screens[i]
    }
    for (var j = 0; j < screens.length; j++) {
      var mapped = Hyprland.monitorFor(screens[j])
      if (mapped && mapped.id === monitor.id) return screens[j]
    }
    return screens.length === 1 ? screens[0] : null
  }

  function slotGeom(screenName, index) {
    var n = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].screenName !== screenName) continue
      if (n === index) {
        var row = rows[i]
        var drag = dragPos[row.address]
        if (!drag) return row
        return {
          address: row.address,
          x: drag.x,
          y: drag.y,
          w: row.w,
          h: row.h,
          scale: row.scale,
          fullscreen: row.fullscreen,
          atX: row.atX,
          atY: row.atY,
          floating: row.floating,
          screenName: row.screenName,
          monX: row.monX,
          monY: row.monY,
          monW: row.monW,
          monH: row.monH,
          reserved: row.reserved
        }
      }
      n++
    }
    return { address: "", x: 0, y: 0, w: 0, h: 0, scale: 1, fullscreen: 0, atX: 0, atY: 0, floating: false, screenName: screenName, monX: 0, monY: 0, monW: 0, monH: 0, reserved: [0, 0, 0, 0] }
  }

  function handleGeom(screenName, index) {
    var n = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].screenName !== screenName) continue
      if (n === index) {
        var row = rows[i]
        return {
          address: row.address,
          x: row.handleX,
          y: row.handleY,
          w: grip,
          h: grip,
          scale: row.scale,
          atX: row.atX,
          atY: row.atY,
          winW: row.winW,
          winH: row.winH,
          floating: row.floating,
          fullscreen: row.fullscreen
        }
      }
      n++
    }
    return { address: "", x: 0, y: 0, w: 0, h: 0, scale: 1, atX: 0, atY: 0, winW: 0, winH: 0, floating: false, fullscreen: 0 }
  }

  function chipGeom(screenName, index) {
    var n = 0
    for (var i = 0; i < minimized.length; i++) {
      if (minimized[i].screenName !== screenName) continue
      if (n === index) return minimized[i]
      n++
    }
    return { address: "", title: "", x: 0, y: 0, w: 0, h: 0 }
  }

  function minimizedCount(screenName) {
    var n = 0
    for (var i = 0; i < minimized.length; i++) {
      if (minimized[i].screenName === screenName) n++
    }
    return n
  }

  function countFor(screenName) {
    var n = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].screenName === screenName) n++
    return n
  }

  function ingest(text) {
    var parts = String(text || "").split("---MON---")
    if (parts.length < 2) return
    var clients
    var monitors
    try {
      clients = JSON.parse(parts[0])
      monitors = JSON.parse(parts[1])
    } catch (e) {
      return
    }
    if (!Array.isArray(clients) || !Array.isArray(monitors)) return

    var mons = {}
    for (var i = 0; i < monitors.length; i++) mons[monitors[i].id] = monitors[i]

    var built = []
    var shelf = []
    var shelfCount = {}
    var alive = {}
    for (var c = 0; c < clients.length; c++) {
      var client = clients[c]
      if (!client || !client.address) continue
      alive[client.address] = true
      var mon = mons[client.monitor]
      var screen = screenFor(mon)
      if (!screen && Quickshell.screens && Quickshell.screens.length === 1) screen = Quickshell.screens[0]
      if (!screen) continue
      if (Controls.onShelf(client)) {
        var n = shelfCount[screen.name] || 0
        if (n >= slotCount) continue
        shelfCount[screen.name] = n + 1
        var fallbackMon = mon
        if (!fallbackMon) {
          for (var mid in mons) { fallbackMon = mons[mid]; break }
        }
        shelf.push({
          address: client.address,
          title: Controls.windowLabel(client),
          screenName: screen.name,
          fallback: Controls.workspaceName({ workspace: fallbackMon && fallbackMon.activeWorkspace }),
          x: 8 + n * 112,
          y: screen.height - 32,
          w: 104,
          h: 24
        })
        continue
      }
      if (!Controls.showable(client) || !mon) continue
      var place = Controls.chromeTopLeft(client, mon, screen, chromeW, inset)
      var handle = Controls.resizeHandle(client, mon, screen, grip)
      if (!place || !handle) continue
      built.push({
        address: client.address,
        x: place.x,
        y: place.y,
        w: chromeW,
        h: chromeH,
        handleX: handle.x,
        handleY: handle.y,
        winW: client.size[0],
        winH: client.size[1],
        scale: place.scale,
        fullscreen: client.fullscreen,
        atX: client.at[0],
        atY: client.at[1],
        floating: client.floating === true,
        workspace: Controls.workspaceName(client),
        screenName: screen.name,
        monX: mon.x,
        monY: mon.y,
        monW: mon.width,
        monH: mon.height,
        reserved: mon.reserved || [0, 0, 0, 0]
      })
    }
    var keptHomes = {}
    for (var hk in homes) if (alive[hk]) keptHomes[hk] = homes[hk]
    homes = keptHomes
    built.sort(function(a, b) {
      if (a.address < b.address) return -1
      if (a.address > b.address) return 1
      return 0
    })
    rows = built
    minimized = shelf
    Qt.callLater(root.poke)
  }

  function scheduleRefresh() {
    if (poll.running) {
      refreshQueued = true
      return
    }
    poll.running = true
  }

  Component.onCompleted: {
    console.log("window-controls ready restore")
    scheduleRefresh()
  }

  Component.onDestruction: {
    var held = surfaces
    surfaces = []
    for (var i = 0; i < held.length; i++) {
      if (!held[i]) continue
      try { held[i].visible = false } catch (e) {}
    }
  }

  // ponytail: event debounce plus a 400ms poll. Upgrade path is binding
  // Hyprland.toplevels directly if lastIpcObject starts carrying `at`/`size`.
  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: root.scheduleRefresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.scheduleRefresh() }
  }

  Process {
    id: poll
    command: ["bash", "-c", "hyprctl clients -j; printf '\\n---MON---\\n'; hyprctl monitors -j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
    onExited: function(exitCode) { root.lastPoll = String(exitCode) }
    onRunningChanged: {
      if (running || !root.refreshQueued) return
      root.refreshQueued = false
      root.scheduleRefresh()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: overlay
        required property var modelData

        function g(i) { return root.slotGeom(modelData.name, i) }
        function hnd(i) { return root.handleGeom(modelData.name, i) }
        function sh(i) { return root.chipGeom(modelData.name, i) }
        function pokeMask() { hit.changed() }

        Component.onCompleted: root.remember(overlay)
        Component.onDestruction: root.forget(overlay)

        visible: root.opened && (root.countFor(modelData.name) > 0 || root.minimizedCount(modelData.name) > 0)
        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: false

        anchors.left: true
        anchors.right: true
        anchors.top: true
        anchors.bottom: true

        WlrLayershell.namespace: "li-window-controls"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
          id: hit
          Region { x: overlay.g(0).x; y: overlay.g(0).y; width: overlay.g(0).w; height: overlay.g(0).h }
          Region { x: overlay.g(1).x; y: overlay.g(1).y; width: overlay.g(1).w; height: overlay.g(1).h }
          Region { x: overlay.g(2).x; y: overlay.g(2).y; width: overlay.g(2).w; height: overlay.g(2).h }
          Region { x: overlay.g(3).x; y: overlay.g(3).y; width: overlay.g(3).w; height: overlay.g(3).h }
          Region { x: overlay.g(4).x; y: overlay.g(4).y; width: overlay.g(4).w; height: overlay.g(4).h }
          Region { x: overlay.g(5).x; y: overlay.g(5).y; width: overlay.g(5).w; height: overlay.g(5).h }
          Region { x: overlay.g(6).x; y: overlay.g(6).y; width: overlay.g(6).w; height: overlay.g(6).h }
          Region { x: overlay.g(7).x; y: overlay.g(7).y; width: overlay.g(7).w; height: overlay.g(7).h }
          Region { x: overlay.g(8).x; y: overlay.g(8).y; width: overlay.g(8).w; height: overlay.g(8).h }
          Region { x: overlay.g(9).x; y: overlay.g(9).y; width: overlay.g(9).w; height: overlay.g(9).h }
          Region { x: overlay.g(10).x; y: overlay.g(10).y; width: overlay.g(10).w; height: overlay.g(10).h }
          Region { x: overlay.g(11).x; y: overlay.g(11).y; width: overlay.g(11).w; height: overlay.g(11).h }
          Region { x: overlay.hnd(0).x; y: overlay.hnd(0).y; width: overlay.hnd(0).w; height: overlay.hnd(0).h }
          Region { x: overlay.hnd(1).x; y: overlay.hnd(1).y; width: overlay.hnd(1).w; height: overlay.hnd(1).h }
          Region { x: overlay.hnd(2).x; y: overlay.hnd(2).y; width: overlay.hnd(2).w; height: overlay.hnd(2).h }
          Region { x: overlay.hnd(3).x; y: overlay.hnd(3).y; width: overlay.hnd(3).w; height: overlay.hnd(3).h }
          Region { x: overlay.hnd(4).x; y: overlay.hnd(4).y; width: overlay.hnd(4).w; height: overlay.hnd(4).h }
          Region { x: overlay.hnd(5).x; y: overlay.hnd(5).y; width: overlay.hnd(5).w; height: overlay.hnd(5).h }
          Region { x: overlay.hnd(6).x; y: overlay.hnd(6).y; width: overlay.hnd(6).w; height: overlay.hnd(6).h }
          Region { x: overlay.hnd(7).x; y: overlay.hnd(7).y; width: overlay.hnd(7).w; height: overlay.hnd(7).h }
          Region { x: overlay.hnd(8).x; y: overlay.hnd(8).y; width: overlay.hnd(8).w; height: overlay.hnd(8).h }
          Region { x: overlay.hnd(9).x; y: overlay.hnd(9).y; width: overlay.hnd(9).w; height: overlay.hnd(9).h }
          Region { x: overlay.hnd(10).x; y: overlay.hnd(10).y; width: overlay.hnd(10).w; height: overlay.hnd(10).h }
          Region { x: overlay.hnd(11).x; y: overlay.hnd(11).y; width: overlay.hnd(11).w; height: overlay.hnd(11).h }
          Region { x: overlay.sh(0).x; y: overlay.sh(0).y; width: overlay.sh(0).w; height: overlay.sh(0).h }
          Region { x: overlay.sh(1).x; y: overlay.sh(1).y; width: overlay.sh(1).w; height: overlay.sh(1).h }
          Region { x: overlay.sh(2).x; y: overlay.sh(2).y; width: overlay.sh(2).w; height: overlay.sh(2).h }
          Region { x: overlay.sh(3).x; y: overlay.sh(3).y; width: overlay.sh(3).w; height: overlay.sh(3).h }
          Region { x: overlay.sh(4).x; y: overlay.sh(4).y; width: overlay.sh(4).w; height: overlay.sh(4).h }
          Region { x: overlay.sh(5).x; y: overlay.sh(5).y; width: overlay.sh(5).w; height: overlay.sh(5).h }
          Region { x: overlay.sh(6).x; y: overlay.sh(6).y; width: overlay.sh(6).w; height: overlay.sh(6).h }
          Region { x: overlay.sh(7).x; y: overlay.sh(7).y; width: overlay.sh(7).w; height: overlay.sh(7).h }
          Region { x: overlay.sh(8).x; y: overlay.sh(8).y; width: overlay.sh(8).w; height: overlay.sh(8).h }
          Region { x: overlay.sh(9).x; y: overlay.sh(9).y; width: overlay.sh(9).w; height: overlay.sh(9).h }
          Region { x: overlay.sh(10).x; y: overlay.sh(10).y; width: overlay.sh(10).w; height: overlay.sh(10).h }
          Region { x: overlay.sh(11).x; y: overlay.sh(11).y; width: overlay.sh(11).w; height: overlay.sh(11).h }
        }

        Repeater {
          model: root.slotCount

          delegate: Item {
            id: cluster
            required property int index
            readonly property var geom: root.slotGeom(overlay.modelData.name, index)

            visible: geom.address !== ""
            x: geom.x
            y: geom.y
            width: geom.w > 0 ? geom.w : 0
            height: geom.h > 0 ? geom.h : 0

            onXChanged: root.note(geom.address, x, y)
            onYChanged: root.note(geom.address, x, y)

            Rectangle {
              anchors.fill: parent
              radius: 6
              color: "#e61c1c1c"
              border.color: "#66ffffff"
              border.width: 1

              Row {
                anchors.fill: parent

                MouseArea {
                  id: grip
                  width: 30
                  height: parent.height
                  cursorShape: Qt.SizeAllCursor
                  onPressed: function(mouse) { cluster.beginDrag(mouse) }
                  onPositionChanged: function(mouse) { if (pressed) cluster.drag(mouse) }
                  onReleased: cluster.endDrag()

                  Text {
                    anchors.centerIn: parent
                    text: "⋮⋮"
                    color: "#f2f2f2"
                    font.pixelSize: 11
                  }
                }

                MouseArea {
                  id: minArea
                  width: 24
                  height: parent.height
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.minimizeWindow(cluster.geom.address)

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: minArea.containsMouse ? "#33ffffff" : "transparent"
                  }

                  Text {
                    anchors.centerIn: parent
                    text: "—"
                    color: "#f2f2f2"
                    font.pixelSize: 13
                  }
                }

                MouseArea {
                  id: maxArea
                  width: 24
                  height: parent.height
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleMaximized(cluster.geom.address)

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: maxArea.containsMouse ? "#33ffffff" : "transparent"
                  }

                  Text {
                    anchors.centerIn: parent
                    text: cluster.geom.fullscreen ? "❐" : "□"
                    color: "#f2f2f2"
                    font.pixelSize: 13
                  }
                }

                MouseArea {
                  id: closeArea
                  width: 24
                  height: parent.height
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.closeWindow(cluster.geom.address)

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: closeArea.containsMouse ? "#e81123" : "transparent"
                  }

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#f2f2f2"
                    font.pixelSize: 16
                  }
                }
              }
            }

            function beginDrag(mouse) {
              var row = geom
              if (!row.address) return
              var p = grip.mapToGlobal(mouse.x, mouse.y)
              dragPressX = p.x
              dragPressY = p.y
              dragOriginX = row.atX
              dragOriginY = row.atY
              dragChromeX = x
              dragChromeY = y
              dragScale = row.scale || 1
              dragAddress = row.address
              dragFullscreen = row.fullscreen
              dragFloating = row.floating
              dragMoved = false
              dragCursorX = p.x
              dragCursorY = p.y
              dragMonitor = {
                x: row.monX,
                y: row.monY,
                width: row.monW,
                height: row.monH,
                reserved: row.reserved
              }
            }

            function endDrag() {
              if (dragMoved) root.finishDrag(dragAddress, dragCursorX, dragCursorY, dragMonitor)
              root.clearDrag(dragAddress)
            }

            function drag(mouse) {
              if (!dragAddress) return
              var p = grip.mapToGlobal(mouse.x, mouse.y)
              var dx = p.x - dragPressX
              var dy = p.y - dragPressY
              if (!dragMoved) {
                if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return
                dragMoved = true
                if (dragFullscreen) root.unsetFullscreen(dragAddress)
                if (!dragFloating) root.floatOn(dragAddress)
              }
              dragCursorX = p.x
              dragCursorY = p.y
              root.setDrag(dragAddress, dragChromeX + dx, dragChromeY + dy)
              root.moveTo(dragAddress, dragOriginX + dx * dragScale, dragOriginY + dy * dragScale)
            }

            property real dragPressX: 0
            property real dragPressY: 0
            property real dragOriginX: 0
            property real dragOriginY: 0
            property real dragChromeX: 0
            property real dragChromeY: 0
            property real dragScale: 1
            property string dragAddress: ""
            property int dragFullscreen: 0
            property bool dragFloating: false
            property bool dragMoved: false
            property real dragCursorX: 0
            property real dragCursorY: 0
            property var dragMonitor: null
          }
        }

        Repeater {
          model: root.slotCount

          delegate: Item {
            id: handle
            required property int index
            readonly property var grip: root.handleGeom(overlay.modelData.name, index)

            visible: grip.address !== ""
            x: grip.x
            y: grip.y
            width: grip.w
            height: grip.h

            MouseArea {
              id: handleArea
              anchors.fill: parent
              cursorShape: Qt.SizeFDiagCursor
              onPressed: function(mouse) { handle.beginResize(mouse) }
              onPositionChanged: function(mouse) { if (pressed) handle.doResize(mouse) }

              Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "◢"
                color: "#f2f2f2"
                font.pixelSize: 14
              }
            }

            function beginResize(mouse) {
              if (!grip.address) return
              var p = handleArea.mapToGlobal(mouse.x, mouse.y)
              resizePressX = p.x
              resizePressY = p.y
              resizeOriginX = grip.atX
              resizeOriginY = grip.atY
              resizeOriginW = grip.winW
              resizeOriginH = grip.winH
              resizeScale = grip.scale || 1
              resizeAddress = grip.address
              if (grip.fullscreen) root.unsetFullscreen(grip.address)
              if (!grip.floating) root.floatOn(grip.address)
            }

            function doResize(mouse) {
              if (!resizeAddress) return
              var p = handleArea.mapToGlobal(mouse.x, mouse.y)
              var dw = (p.x - resizePressX) * resizeScale
              var dh = (p.y - resizePressY) * resizeScale
              root.resizeWindow(resizeAddress, resizeOriginX, resizeOriginY, resizeOriginW + dw, resizeOriginH + dh)
            }

            property real resizePressX: 0
            property real resizePressY: 0
            property real resizeOriginX: 0
            property real resizeOriginY: 0
            property real resizeOriginW: 0
            property real resizeOriginH: 0
            property real resizeScale: 1
            property string resizeAddress: ""
          }
        }

        Repeater {
          model: root.slotCount

          delegate: Item {
            id: shelfItem
            required property int index
            readonly property var geom: root.chipGeom(overlay.modelData.name, index)

            visible: geom.address !== ""
            x: geom.x
            y: geom.y
            width: geom.w
            height: geom.h

            Rectangle {
              anchors.fill: parent
              radius: 6
              color: "#e61c1c1c"
              border.color: "#66ffffff"
              border.width: 1

              Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                text: shelfItem.geom.title
                color: "#f2f2f2"
                font.pixelSize: 12
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.restoreWindow(shelfItem.geom.address)
            }
          }
        }
      }
    }
  }
}
