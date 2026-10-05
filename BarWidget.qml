pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "BarModel.js" as BarModel

Item {
    id: root

    property var bar: null
    property var settings: ({})
    property string moduleName: "li.window-controls"
    property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
        ? bar.shell.serviceFor("li.window-controls") : null
    property string testScreenName: ""
    property real testScreenWidth: 0
    property real testScreenHeight: 0
    property int page: 0
    property bool ready: false
    property var registeredService: null
    property var frozenChips: null
    property int hoveredChips: 0
    property int activePresses: 0

    readonly property var attachedScreen: QsWindow.window ? QsWindow.window.screen : null
    readonly property string screenName: testScreenName || (attachedScreen ? attachedScreen.name : "")
    readonly property bool vertical: bar ? bar.vertical === true : false
    readonly property real barSize: bar && bar.barSize > 0 ? bar.barSize : 32
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"
    readonly property real screenExtent: vertical
        ? (testScreenHeight > 0 ? testScreenHeight : attachedScreen && attachedScreen.height > 0 ? attachedScreen.height : 720)
        : (testScreenWidth > 0 ? testScreenWidth : attachedScreen && attachedScreen.width > 0 ? attachedScreen.width : 1280)
    readonly property real maxWidth: Math.max(1, Math.min(BarModel.positive(Number(setting("maxWidth", 360)), 360), screenExtent / 4))
    readonly property bool fresh: service && service.fresh === true
    readonly property var chips: BarModel.chipsFor(service ? service.minimized : [], screenName)
    readonly property var displayChips: frozenChips !== null ? frozenChips : chips
    readonly property var layout: BarModel.layout(displayChips.length, maxWidth,
        BarModel.positive(Number(setting("chipWidth", 112)), 112), 4, page)
    readonly property var diagnosticAddresses: layout.items.map(function(item) { return displayChips[item.index].address; })
    readonly property var allAddresses: chips.map(function(chip) { return chip.address; })

    visible: fresh && chips.length > 0
    implicitWidth: visible ? (vertical ? barSize : layout.width) : 0
    implicitHeight: visible ? (vertical ? layout.width : barSize) : 0
    clip: true

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function syncRegistration() {
        if (!ready || registeredService === service) return;
        if (registeredService && typeof registeredService.detachWidget === "function") registeredService.detachWidget(root);
        registeredService = service;
        if (registeredService && typeof registeredService.attachWidget === "function") registeredService.attachWidget(root);
    }

    function metadataFor(address) {
        for (var i = 0; i < displayChips.length; i++) if (displayChips[i].address === address) return displayChips[i];
        return null;
    }

    function currentMetadataFor(address) {
        for (var i = 0; i < chips.length; i++) if (chips[i].address === address) return chips[i];
        return null;
    }

    function placementFor(address) {
        for (var i = 0; i < layout.items.length; i++) {
            var placement = layout.items[i];
            if (displayChips[placement.index].address === address) return placement;
        }
        return null;
    }

    function buttonFor(address) {
        for (var i = 0; i < restoreButtons.count; i++) {
            var button = restoreButtons.itemAt(i);
            if (button && button.targetAddress === address) return button;
        }
        return null;
    }

    function pageAddress(index) {
        return index >= 0 && index < diagnosticAddresses.length ? diagnosticAddresses[index] : "";
    }

    function freezeTargets() {
        if (frozenChips === null) frozenChips = chips.slice();
    }

    function releaseTargets() {
        if (!targetHover.hovered && hoveredChips <= 0 && activePresses <= 0) frozenChips = null;
    }

    function clampPage() { if (page !== layout.page) page = layout.page; }

    function previousPage() { page = Math.max(0, layout.page - 1); }
    function nextPage() { page = Math.min(layout.pages - 1, layout.page + 1); }

    function activate(kind, address, identity) {
        if (!fresh) return;
        if (kind === "previous") previousPage();
        else if (kind === "next") nextPage();
        else if (kind === "restore" && service && typeof service.restore === "function") service.restore(address, identity);
    }

    function status() {
        var point = { x: x, y: y };
        try { if (QsWindow.window) point = mapToGlobal(0, 0); } catch (error) {}
        return { screen: screenName, x: x, y: y, globalX: point.x, globalY: point.y,
            w: width, h: height, visible: visible, fresh: fresh, vertical: vertical,
            page: layout.page, pages: layout.pages, addresses: diagnosticAddresses,
            allAddresses: allAddresses, total: chips.length, registered: registeredService !== null };
    }

    onServiceChanged: { frozenChips = null; syncRegistration(); }
    onScreenNameChanged: {
        frozenChips = null;
        if (registeredService && typeof registeredService.widgetsChanged === "function") registeredService.widgetsChanged();
    }
    onLayoutChanged: Qt.callLater(clampPage)
    Component.onCompleted: { ready = true; syncRegistration(); }
    Component.onDestruction: if (registeredService && typeof registeredService.detachWidget === "function") registeredService.detachWidget(root)

    HoverHandler {
        id: targetHover
        onHoveredChanged: {
            if (hovered) root.freezeTargets();
            else Qt.callLater(root.releaseTargets);
        }
    }

    component BarButton: Item {
        id: button
        property string label: ""
        property string help: ""
        property string kind: "restore"
        property string targetAddress: ""
        property string targetIdentity: ""
        property bool interactive: root.fresh && enabled
        readonly property bool pressable: interactive
        property bool registered: false
        property var registeredBar: null
        property bool holdingPress: false
        property string pressedAddress: ""
        property string pressedIdentity: ""
        property string hoveredAddress: ""
        property string hoveredIdentity: ""
        readonly property var api: root.bar

        Accessible.role: Accessible.Button
        Accessible.name: help || label
        Accessible.onPressAction: triggerPress(Qt.LeftButton)
        clip: true
        opacity: interactive ? 1 : 0.4

        function syncClickRegistration() {
            if (!registered || registeredBar === api) return;
            if (registeredBar && typeof registeredBar.unregisterClickTarget === "function") registeredBar.unregisterClickTarget(button);
            registeredBar = api;
            if (registeredBar && typeof registeredBar.registerClickTarget === "function") registeredBar.registerClickTarget(button);
        }

        function capturePress() {
            if (!interactive || holdingPress) return;
            holdingPress = true;
            pressedAddress = targetAddress;
            pressedIdentity = targetIdentity;
            root.activePresses++;
            if (kind === "restore") root.freezeTargets();
        }

        function clearPress() {
            if (holdingPress) root.activePresses = Math.max(0, root.activePresses - 1);
            holdingPress = false;
            pressedAddress = "";
            pressedIdentity = "";
            Qt.callLater(root.releaseTargets);
        }

        function releasePress(inside) {
            var address = pressedAddress;
            var identity = pressedIdentity;
            var held = holdingPress;
            clearPress();
            if (held && inside && interactive) root.activate(kind, address, identity);
        }

        // Omarchy's host forwards clicks through triggerPress. Hover pinning
        // keeps a replaced/reordered window from receiving the previous click.
        function triggerPress(mouseButton) {
            if (mouseButton !== Qt.LeftButton || !interactive) return;
            var address = holdingPress ? pressedAddress : (hoveredAddress || targetAddress);
            var identity = holdingPress ? pressedIdentity : (hoveredIdentity || targetIdentity);
            if (api && typeof api.hideTooltip === "function") api.hideTooltip(button);
            clearPress();
            root.activate(kind, address, identity);
        }

        onApiChanged: syncClickRegistration()
        onVisibleChanged: if (!visible && api && typeof api.hideTooltip === "function") api.hideTooltip(button)
        Component.onCompleted: { registered = true; syncClickRegistration(); }
        Component.onDestruction: {
            if (holdingPress) root.activePresses = Math.max(0, root.activePresses - 1);
            if (area.containsMouse && kind === "restore") root.hoveredChips = Math.max(0, root.hoveredChips - 1);
            if (registeredBar && typeof registeredBar.unregisterClickTarget === "function") registeredBar.unregisterClickTarget(button);
            Qt.callLater(root.releaseTargets);
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3; anchors.bottomMargin: 3
            radius: 4
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, area.pressed ? 0.22 : area.containsMouse ? 0.14 : 0.06)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, area.containsMouse ? 0.5 : 0.2)
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: Math.min(7, parent.width / 6)
            anchors.rightMargin: Math.min(7, parent.width / 6)
            text: button.label
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Math.min(12, Math.max(1, root.barSize - 10))
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: button.kind === "restore" ? Text.AlignLeft : Text.AlignHCenter
        }
        MouseArea {
            id: area
            anchors.fill: parent
            enabled: button.interactive
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                button.hoveredAddress = button.targetAddress;
                button.hoveredIdentity = button.targetIdentity;
                if (button.kind === "restore") { root.hoveredChips++; root.freezeTargets(); }
                if (button.api && typeof button.api.showTooltip === "function") button.api.showTooltip(button, button.help);
            }
            onExited: {
                button.hoveredAddress = "";
                button.hoveredIdentity = "";
                if (button.kind === "restore") { root.hoveredChips = Math.max(0, root.hoveredChips - 1); Qt.callLater(root.releaseTargets); }
                if (button.api && typeof button.api.hideTooltip === "function") button.api.hideTooltip(button);
            }
            onPressed: button.capturePress()
            onReleased: function(mouse) { button.releasePress(containsMouse && mouse.button === Qt.LeftButton); }
            onCanceled: button.clearPress()
        }
    }

    Item {
        id: content
        width: root.layout.width
        height: root.barSize
        anchors.centerIn: parent
        rotation: root.vertical ? 90 : 0

        ScriptModel {
            id: addressModel
            values: root.displayChips.map(function(chip) { return chip.address; })
            comparisonMode: ObjectComparison.Identity
        }

        Repeater {
            id: restoreButtons
            model: addressModel
            delegate: BarButton {
                required property string modelData
                readonly property var metadata: root.metadataFor(modelData)
                readonly property var placement: root.placementFor(modelData)
                readonly property var currentMetadata: root.currentMetadataFor(modelData)
                objectName: "bar-restore:" + modelData
                targetAddress: modelData
                targetIdentity: metadata ? metadata.stableId || "" : ""
                label: metadata ? metadata.title || "Window" : "Window"
                help: "Restore " + label + (metadata && metadata.class ? " (" + metadata.class + ")" : "")
                visible: placement !== null
                interactive: root.fresh && currentMetadata !== null && currentMetadata.stableId === targetIdentity
                x: placement ? placement.x : 0
                width: placement ? placement.w : 0
                height: content.height
            }
        }

        BarButton {
            id: previous
            kind: "previous"; label: "‹"
            help: "Previous minimized windows"
            visible: root.layout.previous !== null
            enabled: root.layout.page > 0
            x: root.layout.previous ? root.layout.previous.x : 0
            width: root.layout.previous ? root.layout.previous.w : 0
            height: content.height
        }
        BarButton {
            id: next
            kind: "next"; label: "›"
            help: "Next minimized windows"
            visible: root.layout.next !== null
            enabled: root.layout.page + 1 < root.layout.pages
            x: root.layout.next ? root.layout.next.x : 0
            width: root.layout.next ? root.layout.next.w : 0
            height: content.height
        }
        Text {
            visible: root.layout.counter !== null
            x: root.layout.counter ? root.layout.counter.x : 0
            width: root.layout.counter ? root.layout.counter.w : 0
            height: content.height
            text: (root.layout.page + 1) + "/" + root.layout.pages
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Math.min(10, Math.max(1, root.barSize - 10))
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
