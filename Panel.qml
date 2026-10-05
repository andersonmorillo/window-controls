pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Controls.js" as Controls
import "State.js" as WindowState

Item {
    id: root

    property bool opened: true
    property var service: null
    property var shell: null
    property var attachedService: null
    readonly property var sharedService: service || (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("li.window-controls") : null)
    readonly property var hostedScreens: sharedService ? sharedService.hostedScreens : []
    property bool testMode: false
    property var testScreens: []
    property var testCommands: []
    property bool testNativeValidation: false
    property var testNativeToplevels: []
    property var rows: []
    property var minimized: []
    property var windows: []
    property var homes: ({})
    property var shelves: ({})
    property var monitors: []
    property var clients: []
    property var surfaces: []
    property var dragPos: ({})
    property var shelfPages: ({})
    property var pendingRestores: ({})
    property var retiredAddresses: ({})
    readonly property var diskStore: diskLoader.item
    property var gesture: null
    property var snapshot: null
    property bool ready: false
    property bool refreshQueued: false
    property string lastPoll: "pending"
    property string lastError: ""
    property string pollOutput: ""
    property string pollStderr: ""
    property bool pollTimedOut: false
    property bool pollExpired: false
    property double lastValidAt: 0
    property double clockNow: Date.now()
    property int buttonSize: 28
    readonly property int chromeW: buttonSize * 4
    readonly property int chromeH: buttonSize
    readonly property int inset: 4
    readonly property int grip: 18
    readonly property var layoutScreens: testMode && testScreens.length ? testScreens : Quickshell.screens
    readonly property bool fresh: !pollExpired && lastValidAt > 0 && clockNow - lastValidAt < 3000
    readonly property string nativeFocusedAddress: Hyprland.activeToplevel ? nativeAddress(Hyprland.activeToplevel.address) : ""
    // Native activation can be unavailable even when native windows are mapped.
    // An explicitly empty active-window snapshot clears the previous highlight.
    readonly property string focusedAddress: snapshot && snapshot.activeWindow !== undefined
        ? nativeAddress(snapshot.activeWindow.address) : nativeFocusedAddress
    readonly property var emptyGeom: ({ address: "", x: 0, y: 0, w: 0, h: 0, chromeVisible: false, handleVisible: false })

    PersistentProperties {
        id: memory
        reloadableId: "li-window-controls-homes"
        property string homesJson: "{}"
        onReloaded: if (root.ready) root.loadHomes()
    }

    Loader {
        id: diskLoader
        active: !root.testMode
        sourceComponent: Component {
            Settings {
                location: "file://" + Quickshell.statePath("li-window-controls.ini")
                property string homesJson: "{}"
            }
        }
        onLoaded: if (root.ready) root.loadHomes()
    }

    function loadHomes() {
        var saved = memory.homesJson;
        if (saved === "{}" && diskStore) saved = diskStore.homesJson;
        homes = WindowState.readHomes(saved);
        rebuild();
    }

    function saveHomes(next) {
        homes = next;
        if (testMode) return;
        var encoded = JSON.stringify(homes);
        memory.homesJson = encoded;
        if (diskStore && diskStore.homesJson !== encoded) {
            diskStore.homesJson = encoded;
            diskStore.sync();
        }
    }

    function open(payloadJson) {
        clockNow = Date.now();
        opened = true;
        scheduleRefresh();
    }

    function connectService() {
        if (attachedService === sharedService) return;
        if (attachedService) attachedService.detachController(root);
        attachedService = sharedService;
        if (attachedService) attachedService.attachController(root);
        Qt.callLater(poke);
    }

    function barHosted(screenName) { return hostedScreens.indexOf(screenName) >= 0; }

    function close() {
        opened = false;
        pendingRestores = ({});
        cancelGesture();
        eventRefresh.stop();
        refreshQueued = false;
    }

    function status() {
        return JSON.stringify({ version: "1.3.0", windows: windows.length, minimized: minimized.length,
            shelves: shelves, poll: lastPoll, error: lastError,
            barWidgets: sharedService ? sharedService.widgetStatus() : [],
            validAgeMs: lastValidAt ? Math.max(0, Date.now() - lastValidAt) : null,
            fresh: fresh, focusedAddress: focusedAddress,
            gesture: gesture ? { address: gesture.address, kind: gesture.kind, moved: gesture.moved } : null,
            controls: rows.map(function(row) { return { address: row.address, screen: row.screenName,
                chrome: { visible: row.chromeVisible && fresh, x: row.x, y: row.y, w: row.w, h: row.h },
                handle: { visible: row.handleVisible && fresh, x: row.handleX, y: row.handleY, w: row.handleW, h: row.handleH } }; }),
            chips: minimized.map(function(chip) { return { address: chip.address, screen: chip.screenName,
                visible: chip.pageVisible && fresh && !barHosted(chip.screenName), x: chip.x, y: chip.y, w: chip.w, h: chip.h }; }),
            regions: surfaces.map(function(surface) { return { screen: surface.modelData.name, count: surface.regionCount }; }) });
    }

    function clientFor(address) {
        for (var i = 0; i < clients.length; i++) if (clients[i] && clients[i].address === address) return clients[i];
        return null;
    }

    function rowFor(address) {
        for (var i = 0; i < rows.length; i++) if (rows[i].address === address) return rows[i];
        return emptyGeom;
    }

    function chipFor(address) {
        for (var i = 0; i < minimized.length; i++) if (minimized[i].address === address) return minimized[i];
        return emptyGeom;
    }

    function nativeAddress(value) {
        if (typeof value !== "string" || value === "") return "";
        return Controls.safeAddress(value.indexOf("0x") === 0 ? value : "0x" + value).toLowerCase();
    }

    function retireAddress(value) {
        var address = nativeAddress(value);
        if (!address) return;
        var next = Object.assign({}, retiredAddresses);
        var client = clientFor(address);
        next[address] = client ? WindowState.clientIdentity(client) : "";
        retiredAddresses = next;
        cancelRestore(address);
        if (gesture && gesture.address.toLowerCase() === address) cancelGesture();
    }

    function isLive(address, identity) {
        var client = clientFor(address);
        if (!fresh || Date.now() - lastValidAt >= 3000 || !client || client.mapped !== true || !Controls.safeAddress(address)
            || (identity && WindowState.clientIdentity(client) !== identity)) return false;
        var retired = retiredAddresses[address.toLowerCase()];
        if (retired !== undefined && (!retired || retired === WindowState.clientIdentity(client))) return false;
        if (testMode && !testNativeValidation) return true;
        // Native toplevel state closes the interval between a press/release
        // and the next geometry poll, including compositor address reuse.
        var live = testMode ? testNativeToplevels : Hyprland.toplevels.values;
        for (var i = 0; i < live.length; i++) {
            if (!live[i] || nativeAddress(live[i].address) !== address.toLowerCase()) continue;
            var object = live[i].lastIpcObject;
            // Native bindings may be unavailable or still initializing. A
            // populated identity can reject reuse; an absent binding must not
            // disable mapped windows or minimized clients omitted by a protocol.
            if (object && object.pid > 0 && nativeAddress(object.address)) {
                var normalized = Object.assign({}, object, { address: nativeAddress(object.address) });
                return WindowState.clientIdentity(normalized) === WindowState.clientIdentity(client);
            }
            return true;
        }
        return true;
    }

    function dispatch(expr) {
        if (testMode) {
            testCommands = testCommands.concat([expr]);
            return;
        }
        if (opened && fresh) Hyprland.dispatch(expr);
    }

    function dispatchWindow(address, prefix) {
        if (!isLive(address, "")) return;
        dispatch(prefix + "window = " + Controls.luaString("address:" + address) + " })");
    }

    function closeWindow(address) { cancelRestore(address); dispatchWindow(address, "hl.dsp.window.close({ "); }
    function focusWindow(address) { dispatchWindow(address, "hl.dsp.focus({ "); }
    function setMaximized(address) { dispatchWindow(address, 'hl.dsp.window.fullscreen({ mode = "maximized", action = "set", layout_aware = false, '); }
    function toggleMaximized(address) { dispatchWindow(address, 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", layout_aware = false, '); }
    function unsetFullscreen(address) { dispatchWindow(address, 'hl.dsp.window.fullscreen({ action = "unset", layout_aware = false, '); }
    function floatOn(address) { dispatchWindow(address, 'hl.dsp.window.float({ action = "on", '); }

    function moveTo(address, x, y) {
        if (!isFinite(x) || !isFinite(y)) return;
        dispatchWindow(address, "hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y) + ", relative = false, ");
    }

    function resizeTo(address, w, h, exact) {
        if (!isFinite(w) || !isFinite(h)) return;
        var minimumW = exact ? 1 : 160;
        var minimumH = exact ? 1 : 80;
        dispatchWindow(address, "hl.dsp.window.resize({ x = " + Math.max(minimumW, Math.round(w)) + ", y = " + Math.max(minimumH, Math.round(h)) + ", relative = false, ");
    }

    function resizeWindow(address, x, y, w, h) {
        resizeTo(address, w, h);
        moveTo(address, x, y);
    }

    function minimizeWindow(address) {
        var client = clientFor(address);
        if (!isLive(address, "") || !client) return;
        cancelRestore(address);
        saveHomes(WindowState.rememberHome(homes, client));
        dispatchWindow(address, 'hl.dsp.window.move({ workspace = "special:li-window-controls", follow = false, ');
    }

    function restoreWindow(address) {
        var client = clientFor(address);
        if (!isLive(address, "") || !client || !WindowState.isMinimized(client, homes)) return;
        var workspace = WindowState.restoreWorkspace(homes, client, chipFor(address).fallback);
        if (!workspace) return;
        var pending = Object.assign({}, pendingRestores);
        pending[address] = { identity: WindowState.clientIdentity(client), workspace: workspace };
        pendingRestores = pending;
        dispatchWindow(address, "hl.dsp.window.move({ workspace = " + Controls.luaString(workspace) + ", follow = true, ");
    }

    function cancelRestore(address) {
        if (!pendingRestores[address]) return;
        var pending = Object.assign({}, pendingRestores);
        delete pending[address];
        pendingRestores = pending;
    }

    function activateWindow(address) {
        var client = clientFor(address);
        if (!isLive(address, "") || !client) return;
        cancelRestore(address);
        if (WindowState.isMinimized(client, homes)) restoreWindow(address);
        else focusWindow(address);
    }

    function maximizeWindow(address) {
        var client = clientFor(address);
        if (!isLive(address, "") || !client) return;
        if (WindowState.isMinimized(client, homes)) {
            restoreWindow(address);
            if (!pendingRestores[address]) return;
            var pending = Object.assign({}, pendingRestores);
            pending[address] = Object.assign({}, pending[address], { maximize: true, requestedAt: Date.now() });
            pendingRestores = pending;
        } else {
            cancelRestore(address);
            focusWindow(address);
            setMaximized(address);
        }
    }

    function importLegacy(payloadJson) {
        var addresses;
        try {
            var payload = JSON.parse(payloadJson);
            addresses = Array.isArray(payload) ? payload : payload.addresses;
        } catch (e) { return "Invalid address list"; }
        if (!Array.isArray(addresses) || !fresh) return "A current snapshot and explicit addresses are required";
        saveHomes(WindowState.importLegacy(homes, clients, monitors, addresses));
        rebuild();
        return "Imported selected legacy windows";
    }

    function placeBox(address, box) {
        unsetFullscreen(address);
        floatOn(address);
        moveTo(address, box.x, box.y);
        resizeTo(address, box.w, box.h, true);
        moveTo(address, box.x, box.y);
    }

    function finishDrag(address, cursorX, cursorY) {
        var destination = Controls.monitorAt(cursorX, cursorY, monitors);
        var zone = destination ? Controls.snapRect(cursorX, cursorY, destination, 28, 10) : null;
        if (zone) placeBox(address, zone);
    }

    function action(address, identity, kind) {
        if (!isLive(address, identity)) return;
        if (kind === "minimize") minimizeWindow(address);
        else if (kind === "maximize") toggleMaximized(address);
        else if (kind === "close") closeWindow(address);
        else if (kind === "restore") restoreWindow(address);
        else if (kind === "activate") activateWindow(address);
        else if (kind === "bar-maximize") maximizeWindow(address);
        scheduleRefresh();
    }

    function setPage(screenName, delta) {
        var shelf = shelves[screenName];
        if (!shelf) return;
        var next = Object.assign({}, shelfPages);
        next[screenName] = Math.max(0, Math.min(shelf.pages - 1, shelf.page + delta));
        shelfPages = next;
        rebuild();
    }

    function buildState(value) {
        return WindowState.buildSnapshot(value, layoutScreens, homes, {
            chromeW: chromeW, chromeH: chromeH, inset: inset, grip: grip,
            chipW: 128, chipH: 28, shelfGap: 8, shelfPages: shelfPages,
            focusedAddress: value.activeWindow !== undefined ? nativeAddress(value.activeWindow.address) : nativeFocusedAddress
        });
    }

    function applyState(built) {
        rows = built.rows;
        minimized = built.minimized;
        windows = built.windows;
        monitors = built.monitors;
        clients = built.clients;
        shelves = built.shelves;
        var pending = Object.assign({}, pendingRestores);
        for (var address in pending) {
            var current = clientFor(address);
            var request = pending[address];
            if (!current || current.mapped !== true || WindowState.clientIdentity(current) !== request.identity
                || (request.maximize && Date.now() - request.requestedAt >= 5000)) {
                delete pending[address];
            } else if (Controls.workspaceName(current, true) === request.workspace) {
                delete built.homes[address];
                delete pending[address];
                // Maximize only after the compositor confirms the restore.
                // This avoids changing fullscreen state on a special workspace.
                if (request.maximize && isLive(address, request.identity)) {
                    focusWindow(address);
                    setMaximized(address);
                }
            }
        }
        pendingRestores = pending;
        var retired = Object.assign({}, retiredAddresses);
        for (var key in retired) {
            var liveClient = clientFor(key);
            if (!liveClient || !retired[key] || WindowState.clientIdentity(liveClient) !== retired[key]) delete retired[key];
        }
        retiredAddresses = retired;
        saveHomes(built.homes);
        if (gesture) {
            var sourceExists = monitors.some(function(monitor) { return monitor && monitor.name === gesture.screenName; });
            if (!sourceExists || !isLive(gesture.address, gesture.identity)) cancelGesture();
        }
        Qt.callLater(poke);
    }

    function rebuild() {
        if (snapshot) applyState(buildState(snapshot));
    }

    function ingest(text) {
        try {
            var parsed = Controls.parseSnapshot(text);
            var built = buildState(parsed);
            snapshot = parsed;
            lastValidAt = Date.now();
            clockNow = lastValidAt;
            pollExpired = false;
            lastError = "";
            applyState(built);
            return true;
        } catch (e) {
            lastError = "Snapshot: " + String(e.message || e);
            console.warn("window-controls " + lastError);
            return false;
        }
    }

    function scheduleRefresh() {
        if (testMode || !opened) return;
        if (poll.running) { refreshQueued = true; return; }
        pollOutput = "";
        pollStderr = "";
        pollTimedOut = false;
        poll.running = true;
    }

    function poke() {
        for (var i = 0; i < surfaces.length; i++) if (surfaces[i]) surfaces[i].pokeMask();
    }

    function remember(surface) { surfaces = surfaces.concat([surface]); }
    function forget(surface) { surfaces = surfaces.filter(function(item) { return item && item !== surface; }); }
    function beginGesture(address, kind, x, y, screenName) {
        cancelGesture();
        var row = rowFor(address);
        if (!isLive(address, row.stableId) || !row.address) return;
        gesture = { address: address, identity: row.stableId, kind: kind, screenName: screenName || row.screenName,
            pressX: x, pressY: y, cursorX: x, cursorY: y, x: row.atX, y: row.atY,
            w: row.winW, h: row.winH, chromeX: row.x, chromeY: row.y,
            chromeW: row.w, chromeH: row.h, handleX: row.handleX, handleY: row.handleY,
            handleW: row.handleW, handleH: row.handleH,
            floating: row.floating, fullscreen: row.fullscreen, moved: false };
    }

    function updateGesture(x, y) {
        if (!gesture) return;
        if (!isLive(gesture.address, gesture.identity)) { cancelGesture(); return; }
        var next = Object.assign({}, gesture);
        var dx = x - next.pressX;
        var dy = y - next.pressY;
        if (!next.moved && Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
        if (!next.moved) {
            if (next.fullscreen) unsetFullscreen(next.address);
            if (!next.floating) floatOn(next.address);
            next.moved = true;
        }
        next.cursorX = x;
        next.cursorY = y;
        gesture = next;
        if (next.kind === "move") {
            var positions = {};
            positions[next.address] = { x: next.chromeX + dx, y: next.chromeY + dy };
            dragPos = positions;
            moveTo(next.address, next.x + dx, next.y + dy);
        } else {
            resizeWindow(next.address, next.x, next.y, next.w + dx, next.h + dy);
        }
        poke();
    }

    function endGesture() {
        var ended = gesture;
        cancelGesture();
        if (ended && ended.moved && ended.kind === "move" && isLive(ended.address, ended.identity))
            finishDrag(ended.address, ended.cursorX, ended.cursorY);
        scheduleRefresh();
    }

    function cancelGesture() {
        gesture = null;
        dragPos = {};
        poke();
    }

    function controlGeom(address, screenName) {
        var row = rowFor(address);
        if (gesture && gesture.address === address && gesture.kind === "move") {
            if (gesture.screenName !== screenName) return emptyGeom;
            return Object.assign({}, row, { screenName: screenName, chromeVisible: true,
                x: dragPos[address] ? dragPos[address].x : gesture.chromeX,
                y: dragPos[address] ? dragPos[address].y : gesture.chromeY,
                w: gesture.chromeW, h: gesture.chromeH });
        }
        return row.screenName === screenName ? row : emptyGeom;
    }

    function resizeGeom(address, screenName) {
        var row = rowFor(address);
        if (gesture && gesture.address === address && gesture.kind === "resize") {
            if (gesture.screenName !== screenName) return emptyGeom;
            return Object.assign({}, row, { screenName: screenName, handleVisible: true,
                handleX: gesture.handleX + (gesture.moved ? Math.max(160 - gesture.w, gesture.cursorX - gesture.pressX) : 0),
                handleY: gesture.handleY + (gesture.moved ? Math.max(80 - gesture.h, gesture.cursorY - gesture.pressY) : 0),
                handleW: gesture.handleW, handleH: gesture.handleH });
        }
        return row.screenName === screenName ? row : emptyGeom;
    }

    onNativeFocusedAddressChanged: if (ready && (!snapshot || snapshot.activeWindow === undefined)) rebuild()
    onSharedServiceChanged: connectService()
    onHostedScreensChanged: Qt.callLater(poke)
    onOpenedChanged: {
        if (!opened) cancelGesture();
        else {
            clockNow = Date.now();
            if (ready) scheduleRefresh();
        }
    }
    onFreshChanged: {
        if (!fresh) cancelGesture();
        Qt.callLater(poke);
    }
    Component.onCompleted: {
        ready = true;
        connectService();
        if (!testMode) loadHomes();
        scheduleRefresh();
    }
    Component.onDestruction: {
        if (attachedService) attachedService.detachController(root);
        if (!testMode && diskStore) diskStore.sync();
        for (var i = 0; i < surfaces.length; i++) if (surfaces[i]) surfaces[i].visible = false;
    }

    Timer {
        interval: root.gesture ? 70 : 1000
        running: root.opened && !root.testMode
        repeat: true
        onTriggered: root.scheduleRefresh()
    }
    Timer {
        interval: 250
        running: root.opened
        repeat: true
        onTriggered: root.clockNow = Date.now()
    }
    Timer {
        id: eventRefresh
        interval: 40
        onTriggered: root.scheduleRefresh()
    }
    Timer {
        id: pollDeadline
        interval: 2200
        onTriggered: {
            root.pollTimedOut = true;
            root.pollExpired = true;
            root.lastError = "Poll timed out";
            poll.signal(15);
            pollKill.start();
        }
    }
    Timer {
        id: pollKill
        interval: 500
        onTriggered: if (poll.running) poll.signal(9)
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var name = event.name || "";
            if (!root.testMode && name === "closewindow") root.retireAddress(event.data);
            if (!root.opened || root.testMode) return;
            if (/^(openwindow|closewindow|movewindow|activewindow|focusedmon|workspace|monitor|fullscreen|changefloatingmode|windowtitle|configreloaded)/.test(name)) {
                if (!eventRefresh.running) eventRefresh.start();
            }
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { if (root.ready) { root.rebuild(); root.scheduleRefresh(); } }
    }

    Process {
        id: poll
        command: ["timeout", "--signal=TERM", "--kill-after=0.5s", "2s", "bash", "-c", "set -e; clients=$(hyprctl clients -j); monitors=$(hyprctl monitors -j); active_window=$(hyprctl activewindow -j); printf '{\"clients\":%s,\"monitors\":%s,\"activeWindow\":%s}\\n' \"$clients\" \"$monitors\" \"$active_window\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.pollOutput = text
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.pollStderr = text
        }
        onExited: function(exitCode) {
            root.lastPoll = String(exitCode);
            pollDeadline.stop();
            pollKill.stop();
            if (exitCode === 0 && !root.pollTimedOut) root.ingest(root.pollOutput);
            else {
                if (exitCode === 124 || exitCode === 137 || root.pollTimedOut) {
                    root.pollExpired = true;
                    root.lastError = "Poll timed out";
                } else root.lastError = "Poll exit " + exitCode + (root.pollStderr ? ": " + root.pollStderr.trim() : "");
                console.warn("window-controls " + root.lastError);
            }
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.scheduleRefresh);
            }
        }
        onRunningChanged: if (running) pollDeadline.restart()
    }

    Component {
        id: regionFactory
        Region {
            property Item target
            x: target ? Math.round(target.x) : 0
            y: target ? Math.round(target.y) : 0
            width: target && target.visible && target.enabled ? Math.round(target.width) : 0
            height: target && target.visible && target.enabled ? Math.round(target.height) : 0
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Component {
            PanelWindow {
                id: overlay
                required property var modelData
                property int regionCount: 0
                readonly property var shelf: root.shelves[modelData.name] || null
                screen: modelData
                visible: root.opened && root.fresh && ((root.gesture && root.gesture.screenName === modelData.name) || root.rows.some(function(row) {
                    return row.screenName === modelData.name && (row.chromeVisible || row.handleVisible);
                }) || (!root.barHosted(modelData.name) && root.minimized.some(function(chip) { return chip.screenName === modelData.name; })))
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
                mask: Region { id: hit }

                function pokeMask() { hit.changed(); }
                function attach(item) {
                    var region = regionFactory.createObject(hit, { target: item });
                    hit.regions.push(region);
                    regionCount = hit.regions.length;
                    hit.changed();
                    return region;
                }
                function detach(region) {
                    if (!region) return;
                    var index = hit.regions.indexOf(region);
                    if (index >= 0) hit.regions.splice(index, 1);
                    regionCount = hit.regions.length;
                    region.destroy();
                    hit.changed();
                }
                function clusterFor(address) {
                    for (var i = 0; i < chromeRepeater.count; i++) {
                        var item = chromeRepeater.itemAt(i);
                        if (item && item.objectName === "chrome:" + address) return item;
                    }
                    return null;
                }
                function handleFor(address) {
                    for (var i = 0; i < handleRepeater.count; i++) {
                        var item = handleRepeater.itemAt(i);
                        if (item && item.objectName === "resize:" + address) return item;
                    }
                    return null;
                }
                Component.onCompleted: root.remember(overlay)
                Component.onDestruction: root.forget(overlay)

                ScriptModel {
                    id: windowModel
                    values: root.rows.map(function(row) { return row.address; })
                    comparisonMode: ObjectComparison.Identity
                }
                ScriptModel {
                    id: shelfModel
                    values: root.minimized.map(function(chip) { return chip.address; })
                    comparisonMode: ObjectComparison.Identity
                }

                Repeater {
                    id: chromeRepeater
                    model: windowModel
                    delegate: Item {
                        id: cluster
                        required property string modelData
                        readonly property var geom: root.controlGeom(modelData, overlay.modelData.name)
                        property var region: null
                        readonly property string description: (geom.title || "Window") + (geom.class ? " (" + geom.class + ")" : "")
                        objectName: "chrome:" + modelData
                        visible: root.fresh && geom.chromeVisible === true
                        x: geom.x || 0
                        y: geom.y || 0
                        width: geom.w || 0
                        height: geom.h || 0
                        Component.onCompleted: region = overlay.attach(cluster)
                        Component.onDestruction: overlay.detach(region)
                        onXChanged: overlay.pokeMask()
                        onYChanged: overlay.pokeMask()
                        onVisibleChanged: overlay.pokeMask()
                        onWidthChanged: overlay.pokeMask()
                        onHeightChanged: overlay.pokeMask()

                        Rectangle {
                            anchors.fill: parent
                            color: "#f51b2028"
                            radius: 6
                            border.color: "#9eabbc"
                            border.width: 1
                        }
                        Row {
                            anchors.fill: parent
                            Item {
                                id: moveGrip
                                width: cluster.width / 4
                                height: cluster.height
                                Accessible.role: Accessible.Grip
                                Accessible.name: "Move " + cluster.description
                                property bool hovered: moveArea.containsMouse
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.text: "Move " + cluster.description
                                QQC.ToolTip.delay: 600
                                Text { anchors.centerIn: parent; text: "⋮⋮"; color: "#ffffff"; font.pixelSize: 12 }
                                MouseArea {
                                    id: moveArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.SizeAllCursor
                                    onPressed: function(mouse) {
                                        var p = mapToGlobal(mouse.x, mouse.y);
                                        root.beginGesture(cluster.modelData, "move", p.x, p.y, overlay.modelData.name);
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!pressed) return;
                                        var p = mapToGlobal(mouse.x, mouse.y);
                                        root.updateGesture(p.x, p.y);
                                    }
                                    onReleased: root.endGesture()
                                    onCanceled: root.cancelGesture()
                                }
                            }
                            ControlButton {
                                width: cluster.width / 4; height: cluster.height
                                label: "—"; help: "Minimize " + cluster.description
                                targetAddress: cluster.modelData; targetIdentity: cluster.geom.stableId || ""
                                onActivated: function(address, identity) { root.action(address, identity, "minimize"); }
                            }
                            ControlButton {
                                width: cluster.width / 4; height: cluster.height
                                label: cluster.geom.fullscreen ? "❐" : "□"
                                help: (cluster.geom.fullscreen ? "Restore size of " : "Maximize ") + cluster.description
                                targetAddress: cluster.modelData; targetIdentity: cluster.geom.stableId || ""
                                onActivated: function(address, identity) { root.action(address, identity, "maximize"); }
                            }
                            ControlButton {
                                width: cluster.width / 4; height: cluster.height
                                label: "×"; help: "Close " + cluster.description; destructive: true
                                targetAddress: cluster.modelData; targetIdentity: cluster.geom.stableId || ""
                                onActivated: function(address, identity) { root.action(address, identity, "close"); }
                            }
                        }
                    }
                }

                Repeater {
                    id: handleRepeater
                    model: windowModel
                    delegate: Item {
                        id: handle
                        required property string modelData
                        readonly property var geom: root.resizeGeom(modelData, overlay.modelData.name)
                        property var region: null
                        objectName: "resize:" + modelData
                        visible: root.fresh && geom.screenName === overlay.modelData.name && geom.handleVisible === true
                            && (!root.gesture || root.gesture.address !== modelData || root.gesture.kind !== "move")
                        x: geom.handleX || 0
                        y: geom.handleY || 0
                        width: geom.handleW || 0
                        height: geom.handleH || 0
                        Accessible.role: Accessible.Grip
                        Accessible.name: "Resize " + (geom.title || "Window")
                        Component.onCompleted: region = overlay.attach(handle)
                        Component.onDestruction: overlay.detach(region)
                        onVisibleChanged: overlay.pokeMask()
                        onXChanged: overlay.pokeMask()
                        onYChanged: overlay.pokeMask()
                        Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "◢"; color: "#ffffff"; font.pixelSize: 16 }
                        MouseArea {
                            id: resizeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeFDiagCursor
                            QQC.ToolTip.visible: containsMouse
                            QQC.ToolTip.text: "Resize " + (handle.geom.title || "Window")
                            QQC.ToolTip.delay: 600
                            onPressed: function(mouse) {
                                var p = mapToGlobal(mouse.x, mouse.y);
                                root.beginGesture(handle.modelData, "resize", p.x, p.y, overlay.modelData.name);
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed) return;
                                var p = mapToGlobal(mouse.x, mouse.y);
                                root.updateGesture(p.x, p.y);
                            }
                            onReleased: root.endGesture()
                            onCanceled: root.cancelGesture()
                        }
                    }
                }

                Repeater {
                    model: shelfModel
                    delegate: ControlButton {
                        id: chip
                        required property string modelData
                        readonly property var geom: root.chipFor(modelData)
                        property var region: null
                        objectName: "shelf:" + modelData
                        visible: root.fresh && !root.barHosted(overlay.modelData.name) && geom.screenName === overlay.modelData.name && geom.pageVisible === true
                        x: geom.x || 0; y: geom.y || 0; width: geom.w || 0; height: geom.h || 0
                        targetAddress: modelData; targetIdentity: geom.stableId || ""
                        help: "Restore " + (geom.title || "Window") + (geom.class ? " (" + geom.class + ")" : "")
                        onActivated: function(address, identity) { root.action(address, identity, "restore"); }
                        Component.onCompleted: region = overlay.attach(chip)
                        Component.onDestruction: overlay.detach(region)
                        onVisibleChanged: overlay.pokeMask()
                        onXChanged: overlay.pokeMask()
                        onYChanged: overlay.pokeMask()
                        Rectangle { anchors.fill: parent; z: -1; radius: 6; color: "#f51b2028"; border.color: "#9eabbc" }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: chip.geom.title || "Window"
                            textFormat: Text.PlainText
                            color: "#ffffff"; font.pixelSize: 12; elide: Text.ElideRight
                        }
                    }
                }

                Item {
                    id: pager
                    readonly property var geom: overlay.shelf ? overlay.shelf.pager : null
                    property var region: null
                    visible: root.fresh && !root.barHosted(overlay.modelData.name) && geom !== null
                    x: geom ? geom.x : 0; y: geom ? geom.y : 0
                    width: geom ? geom.w : 0; height: geom ? geom.h : 0
                    Component.onCompleted: region = overlay.attach(pager)
                    Component.onDestruction: overlay.detach(region)
                    onVisibleChanged: overlay.pokeMask()
                    onXChanged: overlay.pokeMask()
                    onYChanged: overlay.pokeMask()
                    Rectangle { anchors.fill: parent; radius: 6; color: "#f51b2028"; border.color: "#9eabbc" }
                    ControlButton {
                        anchors.left: parent.left; height: parent.height; width: Math.min(36, parent.width / 3)
                        label: "‹"; help: "Previous minimized windows"
                        enabled: overlay.shelf && overlay.shelf.page > 0
                        opacity: enabled ? 1 : 0.4
                        onActivated: root.setPage(overlay.modelData.name, -1)
                    }
                    Text {
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - Math.min(36, parent.width / 3) * 2 - 4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: overlay.shelf ? (overlay.shelf.page + 1) + " / " + overlay.shelf.pages : ""
                        color: "#ffffff"; font.pixelSize: 11
                    }
                    ControlButton {
                        anchors.right: parent.right; height: parent.height; width: Math.min(36, parent.width / 3)
                        label: "›"; help: "Next minimized windows"
                        enabled: overlay.shelf && overlay.shelf.page + 1 < overlay.shelf.pages
                        opacity: enabled ? 1 : 0.4
                        onActivated: root.setPage(overlay.modelData.name, 1)
                    }
                }
            }
        }
    }
}
