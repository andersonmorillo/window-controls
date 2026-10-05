import QtQuick
import Quickshell
import ".." as Plugin

ShellRoot {
    id: suite
    property int phase: 0
    property string screenName: ""
    property var data: null
    property var originalCluster: null
    property var seenChips: ({})
    property var seenBarChips: ({})
    property var pressedBarButton: null
    property string pressedBarAddress: ""

    Plugin.Service { id: bridge }
    QtObject {
        id: fakeShell
        property var liveService: null
        function serviceFor(id) { return id === "li.window-controls" ? liveService : null; }
    }
    // Third-party widgets receive this narrow facade, which has no screen.
    // Its service becomes available after widget construction as in the host.
    QtObject {
        id: fakeBar
        property var shell: fakeShell
        property color foreground: "#ffffff"
        property color barForeground: foreground
        property color background: "#20242b"
        property color urgent: "#ff5566"
        property string fontFamily: "Sans"
        property string position: "top"
        property bool vertical: false
        property int barSize: 32
        property var clickTargets: []
        function registerClickTarget(target) {
            if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target]);
        }
        function unregisterClickTarget(target) {
            clickTargets = clickTargets.filter(function(current) { return current !== target; });
        }
        function showTooltip(target, text) {}
        function hideTooltip(target) {}
    }

    FloatingWindow {
        visible: false
        implicitWidth: 480; implicitHeight: 32
        screen: Quickshell.screens.length ? Quickshell.screens[0] : null
        Loader {
            id: primaryBarLoader
            active: false
            // An invisible test window has no native QWindow yet, so inject
            // its monitor without adding screen fields to the bar facade.
            sourceComponent: Component { Plugin.BarWidget { testScreenName: suite.screenName; testScreenWidth: 480 } }
            onLoaded: {
                item.bar = fakeBar;
                item.moduleName = "li.window-controls";
                item.settings = { maxWidth: 240 };
            }
        }
    }
    FloatingWindow {
        visible: false
        implicitWidth: 600; implicitHeight: 32
        screen: Quickshell.screens.length ? Quickshell.screens[0] : null
        Loader {
            id: secondaryBarLoader
            active: false
            sourceComponent: Component { Plugin.BarWidget { testScreenName: "qa-other"; testScreenWidth: 600 } }
            onLoaded: { item.bar = fakeBar; item.settings = { maxWidth: 240 }; }
        }
    }

    Plugin.Panel { id: panel; opened: false; testMode: true; testNativeValidation: true }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }

    function windowClient(index, minimized) {
        return { address: "0x" + (4096 + index).toString(16), pid: 1000 + index,
            stableId: "native-" + index, class: "qa", initialClass: "qa",
            title: "Window " + index + " ---MON--- ---MONITORS--- <plain text>",
            mapped: true, visible: !minimized, hidden: false, floating: false,
            fullscreen: 0, focusHistoryID: index, monitor: 0,
            workspace: { id: minimized ? -99 : 1, name: minimized ? "special:li-window-controls" : "dev team" },
            at: [(index % 5) * 156, 36 + Math.floor(index / 5) * 170], size: [152, 166] };
    }

    function load() { check(panel.ingest(JSON.stringify(data)), "valid snapshot rejected: " + panel.lastError); }

    function fixtureClient(address) {
        for (var i = 0; i < data.clients.length; i++) if (data.clients[i].address === address) return data.clients[i];
        throw new Error("Missing fixture client " + address);
    }

    function windowIdentity(address) {
        for (var i = 0; i < bridge.windows.length; i++) if (bridge.windows[i].address === address) return bridge.windows[i].stableId;
        throw new Error("Missing bar window " + address);
    }

    function maximizeCommands() {
        return panel.testCommands.filter(function(command) { return command.indexOf("window.fullscreen") >= 0; });
    }

    function checkExplicitMaximize(address, count) {
        var commands = maximizeCommands();
        check(commands.length === count, "expected " + count + " maximize commands for " + address + ", got " + commands.length);
        check(commands.every(function(command) {
            return command.indexOf("address:" + address) >= 0
                && command.indexOf('mode = "maximized"') >= 0
                && command.indexOf('action = "set"') >= 0;
        }), "bar maximize toggled or targeted a different window");
    }

    function run() {
        var target, identity, before, row, surface;
        if (phase === 0) {
            check(Quickshell.screens.length > 0, "offscreen QScreen missing");
            screenName = Quickshell.screens[0].name;
            panel.testScreens = [{ name: screenName, width: 800, height: 600 }];
            data = { clients: [], monitors: [{ id: 0, name: screenName, x: 0, y: 0,
                width: 800, height: 600, scale: 1, transform: 0, reserved: [0, 32, 0, 0],
                activeWorkspace: { id: 1, name: "dev team" } }] };
            for (var i = 0; i < 15; i++) data.clients.push(windowClient(i, false));
            data.activeWindow = { address: "0x1000" };
            load();
            check(panel.rows.length === 15, "window count capped");
            check(Array.isArray(panel.windows) && panel.windows.length === 15,
                "bar window model must include all fifteen open normal windows");
            var focusedWindows = panel.windows.filter(function(window) { return window.focused; });
            check(focusedWindows.length === 1 && focusedWindows[0].address === "0x1000",
                "authoritative activeWindow must mark the focused window when the native binding is unavailable");
            data.activeWindow = {};
            load();
            check(panel.windows.every(function(window) { return window.focused === false; }),
                "explicit no-focus snapshot must override a client's focusHistoryID zero");
            var focusRows = panel.rows;
            var focusWindows = panel.windows;
            var focusSnapshot = panel.snapshot;
            var focusTimestamp = panel.lastValidAt;
            var focusFresh = panel.fresh;
            [null, []].forEach(function(invalidActiveWindow) {
                var invalidFocus = Object.assign({}, data, { activeWindow: invalidActiveWindow });
                check(panel.ingest(JSON.stringify(invalidFocus)) === false,
                    "malformed activeWindow was accepted");
                check(panel.rows === focusRows && panel.windows === focusWindows && panel.snapshot === focusSnapshot
                    && panel.lastValidAt === focusTimestamp && panel.fresh === focusFresh,
                    "malformed focus snapshot replaced valid geometry, windows, or freshness");
            });
            data.activeWindow = { address: "0x1000" };
            load();
            delete data.activeWindow;
        } else if (phase === 1) {
            check(panel.surfaces.length >= 1, "overlay not instantiated");
            surface = panel.surfaces[0];
            check(surface.regionCount === 31, "dynamic mask incomplete: " + surface.regionCount);
            originalCluster = surface.clusterFor("0x1000");
            check(originalCluster !== null, "address delegate missing");
            data.clients.reverse();
            data.clients[14].at = [8, 36];
            load();
        } else if (phase === 2) {
            check(panel.surfaces[0].clusterFor("0x1000") === originalCluster, "reordering replaced address delegate");
            before = panel.rows;
            var timestamp = panel.lastValidAt;
            check(panel.ingest("not json") === false, "malformed snapshot accepted");
            check(panel.ingest(JSON.stringify({clients: [null], monitors: data.monitors})) === false, "invalid client array accepted");
            check(panel.rows === before && panel.lastValidAt === timestamp, "bad snapshot changed live state");
            target = "0x1000";
            row = panel.rowFor(target);
            var nativeClient = data.clients.filter(function(client) { return client.address === target; })[0];
            panel.testNativeToplevels = [{address: "1000", lastIpcObject: nativeClient}];
            check(panel.isLive(target, row.stableId), "bare native address rejected");
            panel.testNativeToplevels = [{address: target, lastIpcObject: nativeClient}];
            check(panel.isLive(target, row.stableId), "prefixed native address rejected");
            var wrongNative = Object.assign({}, nativeClient, {stableId: "different-native-id"});
            panel.testNativeToplevels = [{address: "1000", lastIpcObject: wrongNative}];
            check(!panel.isLive(target, row.stableId), "native identity mismatch accepted");
            panel.testNativeToplevels = [];
            check(panel.isLive(target, row.stableId), "fresh fallback rejected with no native binding");
            panel.retireAddress("1000");
            check(!panel.isLive(target, row.stableId), "closed native address remained live");
            load();
            check(!panel.isLive(target, row.stableId), "old snapshot resurrected retired identity");
            nativeClient.stableId = "new-native-after-close";
            load();
            check(panel.isLive(target, panel.rowFor(target).stableId), "replacement native identity stayed retired");
            row = panel.rowFor(target);
            panel.testCommands = [];
            panel.beginGesture(target, "resize", 100, 100, screenName);
            panel.endGesture();
            check(panel.testCommands.length === 0, "resize click changed layout");
            panel.beginGesture(target, "resize", 100, 100, screenName);
            panel.updateGesture(102, 102);
            check(panel.testCommands.length === 0, "small movement dispatched");
            panel.updateGesture(107, 109);
            check(panel.testCommands.length === 3, "resize did not float/resize/move");
            check(panel.testCommands[1].indexOf("x = 160, y = 175") >= 0, "resize dimensions incorrect");
            panel.cancelGesture();
            check(panel.gesture === null && Object.keys(panel.dragPos).length === 0, "canceled gesture remained active");
            panel.testCommands = [];
            panel.placeBox(target, { x: 100, y: 10, w: 90, h: 60 });
            check(panel.testCommands[3].indexOf("x = 90, y = 60") >= 0, "snap dimensions expanded beyond work area");
            panel.testCommands = [];
            panel.beginGesture(target, "move", 100, 100, screenName);
            panel.updateGesture(110, 112);
            check(panel.testCommands[1].indexOf("x = 18, y = 48") >= 0, "move used incorrect coordinates");
            identity = row.stableId;
            data.clients = data.clients.filter(function(client) { return client.address !== target; });
            load();
            check(panel.gesture === null, "closed window kept a gesture");
            before = panel.testCommands.length;
            panel.action(target, identity, "close");
            check(panel.testCommands.length === before, "closed target dispatched");
            data.clients.push(windowClient(0, false));
            data.clients[data.clients.length - 1].stableId = "native-reused";
            load();
            before = panel.testCommands.length;
            panel.action(target, identity, "close");
            check(panel.testCommands.length === before, "reused address accepted stale identity");
        } else if (phase === 3) {
            target = "0x1000";
            row = panel.rowFor(target);
            panel.testCommands = [];
            panel.action(target, row.stableId, "minimize");
            check(panel.homes[target].workspace === "dev team", "original workspace not remembered");
            check(panel.testCommands[0].indexOf("special:li-window-controls") >= 0, "minimize used another special workspace");
            for (var m = 0; m < data.clients.length; m++) if (data.clients[m].address === target) {
                data.clients[m].workspace = { id: -99, name: "special:li-window-controls" };
                data.clients[m].visible = false;
            }
            load();
            check(panel.minimized.length === 1, "minimized client missing");
            panel.testCommands = [];
            panel.action(target, panel.chipFor(target).stableId, "restore");
            check(panel.testCommands[0].indexOf('workspace = "dev team"') >= 0, "restore lost named workspace");
            for (var r = 0; r < data.clients.length; r++) if (data.clients[r].address === target) {
                data.clients[r].workspace = { id: 1, name: "dev team" };
                data.clients[r].visible = true;
            }
            load();
            check(!panel.homes[target] && !panel.pendingRestores[target], "confirmed restore kept old metadata");
            data.clients = [];
            for (var chip = 0; chip < 29; chip++) data.clients.push(windowClient(chip, true));
            panel.testScreens = [{ name: screenName, width: 340, height: 180 }];
            data.monitors[0].width = 340;
            data.monitors[0].height = 180;
            load();
            check(panel.minimized.length === 29 && panel.shelves[screenName].pages > 1, "shelf overflow not paginated");
            check(panel.shelves[screenName].anchor === "top", "minimized windows not positioned at top");
            check(panel.minimized.filter(function(entry) { return entry.pageVisible; })[0].y === 40, "shelf overlaps reserved top bar");
            for (var page = 0; page < panel.shelves[screenName].pages; page++) {
                panel.minimized.forEach(function(entry) { if (entry.pageVisible) seenChips[entry.address] = true; });
                panel.setPage(screenName, 1);
            }
            check(Object.keys(seenChips).length === 29, "shelf pages leave windows unreachable");
        } else if (phase === 4) {
            check(panel.surfaces[0].regionCount === 30, "deleted controls leaked input regions");
            target = data.clients[0].address;
            identity = panel.chipFor(target).stableId;
            panel.clockNow = panel.lastValidAt + 4000;
            check(!panel.fresh, "snapshot did not become stale");
            panel.testCommands = [];
            panel.action(target, identity, "restore");
            check(panel.testCommands.length === 0, "stale controls accepted input");
            data.clients = [];
            load();
        } else if (phase === 5) {
            check(panel.surfaces[0].regionCount === 1, "empty model leaked dynamic regions");
            check(panel.rows.length === 0 && panel.minimized.length === 0, "empty valid state not applied");
        } else if (phase === 6) {
            panel.testScreens = [{ name: screenName, width: 340, height: 180 },
                { name: "qa-other", width: 600, height: 400 }];
            data.monitors.push({ id: 1, name: "qa-other", x: 340, y: 0, width: 600, height: 400,
                scale: 1, transform: 0, reserved: [0, 32, 0, 0], activeWorkspace: { name: "3" } });
            for (var b = 0; b < 28; b++) {
                var barClient = windowClient(b, true);
                if (b >= 21) barClient.monitor = 1;
                data.clients.push(barClient);
            }
            var activeNormal = windowClient(100, false);
            activeNormal.at = [12, 44];
            var inactiveNormal = windowClient(101, false);
            inactiveNormal.visible = false;
            inactiveNormal.workspace = { name: "qa inactive" };
            var maximizedNormal = windowClient(102, false);
            maximizedNormal.fullscreen = 1;
            maximizedNormal.at = [180, 44];
            data.clients.push(activeNormal, inactiveNormal, maximizedNormal);
            data.activeWindow = { address: activeNormal.address };
            // The host assigns the controller's service after construction.
            panel.service = bridge;
            load();
            check(bridge.controller === panel, "late service injection did not attach the controller");
            check(bridge.minimized.length === 28 && bridge.fresh, "bridge did not mirror controller state");
            check(bridge.windows.length === 31, "bridge omitted normal or inactive-workspace windows");
            check(panel.rows.every(function(row) { return row.address !== inactiveNormal.address; }),
                "inactive workspace unexpectedly received corner controls");
            var inactiveMetadata = bridge.windows.filter(function(entry) { return entry.address === inactiveNormal.address; })[0];
            check(inactiveMetadata && inactiveMetadata.workspace === "qa inactive" && inactiveMetadata.minimized === false,
                "all-window model lost inactive workspace metadata");
            check(typeof inactiveMetadata.focused === "boolean" && typeof inactiveMetadata.fullscreen === "number",
                "bar metadata is missing focus or fullscreen state");
            var activeMetadata = bridge.windows.filter(function(window) { return window.focused; });
            check(activeMetadata.length === 1 && activeMetadata[0].address === activeNormal.address,
                "all-window metadata did not select the authoritative normal window");
            bridge.detachController(fakeShell);
            check(bridge.controller === panel, "unrelated teardown cleared the active controller");
            primaryBarLoader.active = true;
        } else if (phase === 7) {
            check(primaryBarLoader.item !== null, "bar widget did not instantiate");
            check(primaryBarLoader.item.screenName === screenName, "bar monitor fixture was not applied");
            check(primaryBarLoader.item.service === null, "service unexpectedly available before host injection");
            check(!panel.barHosted(screenName), "unconnected bar suppressed restoration fallback");
            // Mimic the scoped shell's service lookup changing after load.
            fakeShell.liveService = bridge;
        } else if (phase === 8) {
            var widget = primaryBarLoader.item;
            check(widget.service === bridge, "late scoped service lookup did not rebind");
            check(panel.barHosted(screenName) && !panel.barHosted("qa-other"), "bar ownership leaked across monitors");
            check(widget.allAddresses.length === 24, "primary bar omitted normal windows or did not filter by monitor");
            check(["0x1064", "0x1065", "0x1066"].every(function(address) { return widget.allAddresses.indexOf(address) >= 0; }),
                "normal and inactive-workspace windows are missing from the bar");
            check(widget.allAddresses.every(function(address) {
                var titleButton = widget.buttonFor(address);
                return titleButton !== null && titleButton.activeWindow === (address === "0x1064");
            }), "bar focus indicators do not match authoritative window metadata");
            check(widget.layout.pages > 1 && widget.diagnosticAddresses.length > 0, "native bar overflow lacks visible pagination");
            check(widget.implicitWidth <= 240 && widget.implicitHeight <= fakeBar.barSize, "bar widget exceeds its configured width or bar height");
            var fallbackStatus = JSON.parse(panel.status()).chips;
            check(fallbackStatus.filter(function(chip) { return chip.screen === screenName && chip.visible; }).length === 0,
                "hosted monitor still renders duplicate overlay restore buttons");
            check(fallbackStatus.some(function(chip) { return chip.screen === "qa-other" && chip.visible; }),
                "monitor without a bar lost its restoration fallback");
        } else if (phase === 9) {
            load();
            var pagedWidget = primaryBarLoader.item;
            var rendered = pagedWidget.diagnosticAddresses;
            check(rendered.length > 0, "bar page renders no restore buttons");
            for (var renderedIndex = 0; renderedIndex < rendered.length; renderedIndex++) {
                var renderedButton = pagedWidget.buttonFor(rendered[renderedIndex]);
                var renderedMaximize = pagedWidget.maximizeButtonFor(rendered[renderedIndex]);
                check(renderedButton !== null && renderedMaximize !== null, "bar entry is missing its title or maximize button");
                check(renderedButton.activeWindow === (rendered[renderedIndex] === "0x1064"),
                    "rendered bar page shows an incorrect focused-window marker");
                check(renderedButton.width > 0 && renderedButton.height > 0, "rendered restore button has empty geometry");
                check(renderedMaximize.width > 0 && renderedMaximize.height > 0, "rendered maximize button has empty geometry");
                check(renderedButton.x >= 0 && renderedButton.x + renderedButton.width <= pagedWidget.width,
                    "restore button extends past the bar widget");
                seenBarChips[rendered[renderedIndex]] = true;
            }
            if (pagedWidget.page + 1 < pagedWidget.layout.pages) { pagedWidget.nextPage(); return; }
            check(Object.keys(seenBarChips).length === 24, "native bar pages leave open windows unreachable");
            secondaryBarLoader.active = true;
        } else if (phase === 10) {
            load();
            check(secondaryBarLoader.item !== null, "second bar widget did not instantiate");
            check(secondaryBarLoader.item.allAddresses.length === 7, "second bar did not filter by monitor");
            check(secondaryBarLoader.item.allAddresses.every(function(address) { return primaryBarLoader.item.allAddresses.indexOf(address) < 0; }),
                "native bar restoration models overlap monitors");
            check(panel.barHosted("qa-other"), "second bar did not suppress its fallback");
            check(bridge.widgets.length === 2, "widget registration was duplicated or lost");
            check(fakeBar.clickTargets.length === 66, "each open window must register title and maximize targets");
            primaryBarLoader.item.page = 0;
        } else if (phase === 11) {
            pressedBarAddress = primaryBarLoader.item.pageAddress(0);
            pressedBarButton = primaryBarLoader.item.buttonFor(pressedBarAddress);
            check(pressedBarButton !== null, "pressed restore button missing");
            pressedBarButton.capturePress();
            for (var changed = 0; changed < data.clients.length; changed++) {
                if (data.clients[changed].address === pressedBarAddress) data.clients[changed].stableId = "reused-during-bar-press";
            }
            panel.testCommands = [];
            load();
        } else if (phase === 12) {
            check(pressedBarButton !== null, "identity update unexpectedly destroyed the address delegate");
            pressedBarButton.releasePress(true);
            check(panel.testCommands.length === 0, "bar restore accepted the identity replaced during its press");
        } else if (phase === 13) {
            // Target thawing runs through Qt.callLater after release. Let the
            // next event turn supply current metadata for a new press.
            var currentButton = primaryBarLoader.item.buttonFor(pressedBarAddress);
            check(fakeBar.clickTargets.indexOf(currentButton) >= 0, "restore button was not registered with the host");
            currentButton.triggerPress(Qt.LeftButton);
            check(panel.testCommands.length === 1 && panel.testCommands[0].indexOf("follow = true") >= 0,
                "host-forwarded bar restore did not route through the controller");
            currentButton.triggerPress(Qt.RightButton);
            check(panel.testCommands.length === 1, "unsupported host mouse button dispatched restoration");
        } else if (phase === 14) {
            load();
            panel.testCommands = [];
            primaryBarLoader.item.buttonFor("0x1064").triggerPress(Qt.LeftButton);
            primaryBarLoader.item.buttonFor("0x1065").triggerPress(Qt.LeftButton);
            check(panel.testCommands.length === 2 && panel.testCommands.every(function(command) {
                return command.indexOf("hl.dsp.focus(") >= 0;
            }), "normal and inactive-workspace titles must focus their windows");
            panel.testCommands = [];
            var normalMaximize = primaryBarLoader.item.maximizeButtonFor("0x1066");
            check(fakeBar.clickTargets.indexOf(normalMaximize) >= 0, "maximize affordance is not registered with the host");
            normalMaximize.triggerPress(Qt.LeftButton);
            normalMaximize.triggerPress(Qt.LeftButton);
            checkExplicitMaximize("0x1066", 2);
            check(panel.testCommands.filter(function(command) { return command.indexOf("hl.dsp.focus(") >= 0; }).length === 2,
                "maximize did not focus the selected normal window");
            panel.testCommands = [];
            pressedBarButton = primaryBarLoader.item.maximizeButtonFor("0x1064");
            pressedBarButton.capturePress();
            fixtureClient("0x1064").stableId = "replacement-during-maximize-press";
            load();
        } else if (phase === 15) {
            pressedBarButton.releasePress(true);
            check(panel.testCommands.length === 0, "maximize accepted an identity replaced during its press");
            // Remember a real home through the controller before exercising
            // restore confirmation alongside an authoritative focus change.
            fixtureClient("0x1001").workspace = { name: "dev team" };
            fixtureClient("0x1001").visible = true;
            load();
            panel.minimizeWindow("0x1001");
            check(panel.homes["0x1001"] && panel.homes["0x1001"].workspace === "dev team",
                "restore interaction fixture did not remember its original workspace");
            fixtureClient("0x1001").workspace = { name: "special:li-window-controls" };
            fixtureClient("0x1001").visible = false;
            load();
            panel.testCommands = [];
            primaryBarLoader.item.buttonFor("0x1001").triggerPress(Qt.LeftButton);
            check(panel.testCommands.length === 1 && panel.testCommands[0].indexOf('workspace = "dev team"') >= 0
                && panel.testCommands[0].indexOf("follow = true") >= 0, "minimized title did not restore its original workspace");
            panel.testCommands = [];
            primaryBarLoader.item.maximizeButtonFor("0x1001").triggerPress(Qt.LeftButton);
            check(panel.testCommands.length === 1 && panel.testCommands[0].indexOf('workspace = "dev team"') >= 0,
                "minimized maximize did not begin by restoring");
            checkExplicitMaximize("0x1001", 0);
            check(panel.pendingRestores["0x1001"] && panel.pendingRestores["0x1001"].maximize === true,
                "minimized maximize was not queued for restore confirmation");
        } else if (phase === 16) {
            panel.testCommands = [];
            load();
            checkExplicitMaximize("0x1001", 0);
            fixtureClient("0x1001").workspace = { name: "special:unrelated" };
            load();
            checkExplicitMaximize("0x1001", 0);
            check(panel.pendingRestores["0x1001"] && panel.pendingRestores["0x1001"].maximize,
                "restore confirmation was inferred from the wrong workspace");
        } else if (phase === 17) {
            fixtureClient("0x1001").workspace = { name: "dev team" };
            fixtureClient("0x1001").visible = true;
            data.activeWindow = { address: "0x1001" };
            panel.pollExpired = true;
            load();
            check(panel.fresh && panel.focusedAddress === "0x1001", "valid restore snapshot did not recover freshness and focus");
            checkExplicitMaximize("0x1001", 1);
            check(panel.testCommands.some(function(command) { return command.indexOf("hl.dsp.focus(") >= 0; }),
                "confirmed minimized maximize did not focus its restored window");
            check(!panel.pendingRestores["0x1001"], "confirmed maximize retained its pending request");
            check(!panel.homes["0x1001"], "focus change resurrected a confirmed restore's old home metadata");
        } else if (phase === 18) {
            panel.testCommands = [];
            bridge.maximize("0x1002", windowIdentity("0x1002"));
            fixtureClient("0x1002").mapped = false;
            load();
            checkExplicitMaximize("0x1002", 0);
            check(!panel.pendingRestores["0x1002"], "unmapped window retained a queued maximize");
            fixtureClient("0x1002").mapped = true;
            fixtureClient("0x1002").stableId = "new-window-after-unmap";
            load();
        } else if (phase === 19) {
            panel.testCommands = [];
            bridge.maximize("0x1003", windowIdentity("0x1003"));
            fixtureClient("0x1003").stableId = "new-native-after-queued-maximize";
            load();
            check(!panel.pendingRestores["0x1003"], "reused native identity retained a queued maximize");
            fixtureClient("0x1003").workspace = { name: "dev team" };
            fixtureClient("0x1003").visible = true;
            load();
            checkExplicitMaximize("0x1003", 0);
        } else if (phase === 20) {
            panel.testCommands = [];
            bridge.maximize("0x1004", windowIdentity("0x1004"));
            panel.retireAddress("1004");
            load();
            fixtureClient("0x1004").workspace = { name: "dev team" };
            fixtureClient("0x1004").visible = true;
            load();
            checkExplicitMaximize("0x1004", 0);
            check(!panel.pendingRestores["0x1004"], "native close event retained a queued maximize");
        } else if (phase === 21) {
            panel.testCommands = [];
            bridge.maximize("0x1006", windowIdentity("0x1006"));
            check(panel.pendingRestores["0x1006"], "timeout fixture was not queued");
            panel.pendingRestores["0x1006"].requestedAt = Date.now() - 6000;
            load();
            fixtureClient("0x1006").workspace = { name: "dev team" };
            fixtureClient("0x1006").visible = true;
            load();
            checkExplicitMaximize("0x1006", 0);
            check(!panel.pendingRestores["0x1006"], "expired maximize applied after a delayed restoration");
        } else if (phase === 22) {
            panel.testCommands = [];
            bridge.maximize("0x1007", windowIdentity("0x1007"));
            bridge.activateWindow("0x1007", windowIdentity("0x1007"));
            fixtureClient("0x1007").workspace = { name: "dev team" };
            fixtureClient("0x1007").visible = true;
            load();
            checkExplicitMaximize("0x1007", 0);
            check(!panel.pendingRestores["0x1007"], "new title action left an older maximize queued");
        } else if (phase === 23) {
            panel.testCommands = [];
            bridge.maximize("0x1005", windowIdentity("0x1005"));
            panel.close();
            fixtureClient("0x1005").workspace = { name: "dev team" };
            fixtureClient("0x1005").visible = true;
            load();
            checkExplicitMaximize("0x1005", 0);
            check(!panel.pendingRestores["0x1005"], "closed controller retained a queued maximize");
            primaryBarLoader.active = false;
        } else if (phase === 24) {
            check(bridge.widgets.length === 1, "destroyed native bar retained its service registration");
            check(fakeBar.clickTargets.length === 16, "destroyed bar retained host click targets");
            check(!panel.barHosted(screenName) && panel.barHosted("qa-other"), "bar removal did not restore only its own fallback");
            check(JSON.parse(panel.status()).chips.some(function(chip) { return chip.screen === screenName && chip.visible; }),
                "bar removal left primary minimized windows inaccessible");
            panel.service = null;
            check(bridge.controller === null && !bridge.fresh && bridge.minimized.length === 0 && bridge.windows.length === 0,
                "controller teardown left bridge state live");
        } else if (phase === 25) {
            panel.service = bridge;
            load();
            check(bridge.controller === panel && bridge.windows.length === 31, "retained bridge did not accept a replacement controller attachment");
            secondaryBarLoader.active = false;
        } else if (phase === 26) {
            check(bridge.widgets.length === 0 && bridge.hostedScreens.length === 0, "bar teardown leaked hosted screens");
            check(fakeBar.clickTargets.length === 0, "bar teardown leaked host click targets");
            check(!panel.barHosted(screenName) && !panel.barHosted("qa-other"), "empty service still suppresses restoration fallbacks");
            console.log("window-controls QML smoke passed: masks, gestures, identities, all-window bar, focus, explicit maximize, restore confirmation, queued-action cancellation and lifecycle");
            Qt.quit();
        }
        phase++;
    }

    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            try { suite.run(); }
            catch (error) { console.error("QML smoke failed at phase " + suite.phase + ": " + error); Qt.exit(1); }
        }
    }
}
