import QtQuick

// The panel owns the compositor poll and window state. Bar instances share
// that controller through this service rather than creating additional polls.
QtObject {
    id: bridge

    property var controller: null
    property var widgets: []
    readonly property var minimized: controller ? controller.minimized : []
    readonly property bool fresh: !!controller && controller.fresh && (controller.opened || controller.testMode)
    readonly property var hostedScreens: {
        var screens = [];
        for (var i = 0; i < widgets.length; i++) {
            if (!widgets[i] || typeof widgets[i].screenName !== "string") continue;
            var name = widgets[i].screenName;
            if (screens.indexOf(name) < 0) screens.push(name);
        }
        return screens;
    }

    function attachController(panel) { controller = panel; }
    function detachController(panel) { if (controller === panel) controller = null; }

    function restore(address, identity) {
        if (fresh) controller.action(address, identity, "restore");
    }

    function attachWidget(widget) {
        if (widget && widgets.indexOf(widget) < 0) widgets = widgets.concat([widget]);
    }

    function detachWidget(widget) {
        widgets = widgets.filter(function(current) { return current && current !== widget; });
    }

    // widgetsChanged() is the callable notify signal of the widgets property.
    // Widgets emit it when their output changes, so fallback masks rebind.
    function widgetStatus() {
        var result = [];
        for (var i = 0; i < widgets.length; i++) {
            var widget = widgets[i];
            if (!widget) continue;
            if (typeof widget.status === "function") result.push(widget.status());
            else result.push({ screen: widget.screenName, x: widget.x, y: widget.y,
                w: widget.width, h: widget.height, visible: widget.visible,
                addresses: widget.diagnosticAddresses || [] });
        }
        return result;
    }

    function status() {
        return JSON.stringify({ fresh: fresh, minimized: minimized.length,
            hostedScreens: hostedScreens, widgets: widgetStatus() });
    }
}
