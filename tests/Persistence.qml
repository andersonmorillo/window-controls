import QtQuick
import QtCore
import Quickshell
import "../State.js" as WindowState

ShellRoot {
    id: suite
    readonly property string phase: String(Quickshell.env("WINDOW_CONTROLS_PERSISTENCE_PHASE") || "")
    readonly property var diskStore: diskLoader.item
    readonly property string originalWorkspace: 'dev "quoted" \\ team 🛠'
    readonly property var client: ({ address: "0x180001c", pid: 4242,
        stableId: "native-180001c", class: "qa-editor", initialClass: "qa-editor",
        mapped: true, monitor: 0, monitorName: "eDP-1",
        workspace: { name: originalWorkspace } })
    readonly property var expectedHomes: WindowState.rememberHome({}, client)
    readonly property string expectedJson: JSON.stringify(expectedHomes)

    PersistentProperties {
        id: memory
        reloadableId: "li-window-controls-persistence-test-homes"
        property string homesJson: "{}"
    }

    // Match the plugin's Loader/Settings and file URL pattern exactly. The
    // runner supplies isolated XDG directories shared by both processes.
    Loader {
        id: diskLoader
        active: true
        sourceComponent: Component {
            Settings {
                location: "file://" + Quickshell.statePath("li-window-controls.ini")
                property string homesJson: "{}"
            }
        }
        onLoaded: checkTimer.start()
    }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }

    function run() {
        check(diskStore !== null, "Settings loader did not instantiate");
        check(memory.homesJson === "{}", "new process unexpectedly retained memory-only homes");
        if (phase === "write") {
            check(diskStore.homesJson === "{}", "write phase is not isolated from prior settings");
            memory.homesJson = expectedJson;
            diskStore.homesJson = memory.homesJson;
            diskStore.sync();
            check(diskStore.homesJson === expectedJson, "Settings assignment changed the JSON");
            check(WindowState.restoreWorkspace(WindowState.readHomes(memory.homesJson), client, "fallback")
                === originalWorkspace, "memory store lost workspace or identity");
            console.log("window-controls persistence write passed");
        } else if (phase === "read") {
            check(diskStore.homesJson === expectedJson, "Settings JSON did not survive process restart: " + diskStore.homesJson);
            // The plugin hydrates the memory store from disk when memory is empty.
            memory.homesJson = diskStore.homesJson;
            var homes = WindowState.readHomes(memory.homesJson);
            check(JSON.stringify(homes) === expectedJson, "sanitization altered persisted metadata");
            check(homes[client.address].workspace === originalWorkspace, "named workspace was not restored exactly");
            check(homes[client.address].compositorId === client.stableId, "native compositor identity was lost");
            check(homes[client.address].stableId === WindowState.clientIdentity(client), "complete identity was not restored");
            var minimized = Object.assign({}, client, { workspace: { name: "special:li-window-controls" } });
            check(WindowState.restoreWorkspace(homes, minimized, "9") === originalWorkspace,
                "restart restore used the active workspace fallback");
            var reused = Object.assign({}, minimized, { stableId: "new-native-window" });
            check(WindowState.restoreWorkspace(homes, reused, "9") === "9", "reused native identity accepted persisted home");
            console.log("window-controls persistence read passed");
        } else {
            throw new Error("Set WINDOW_CONTROLS_PERSISTENCE_PHASE to write or read");
        }
        Qt.quit();
    }

    Timer {
        id: checkTimer
        interval: 100
        onTriggered: {
            try { suite.run(); }
            catch (error) {
                console.error("Persistence " + suite.phase + " failed: " + error);
                Qt.exit(1);
            }
        }
    }
}
