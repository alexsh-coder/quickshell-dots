import QtQuick

// Works around ListView leaving gaps when model changes interrupt its add/move/displaced
// transitions: once things calm down, puts every delegate back at its layout position.
// Delegates need `required property int index`.
Timer {
    id: root

    required property ListView view
    property bool paused: false

    interval: 700
    onTriggered: {
        if (paused || !view.visible)
            return;
        const items = Array.prototype.filter.call(view.contentItem.children, c => typeof c.index === "number" && c.index >= 0).sort((a, b) => a.index - b.index);
        if (!items.length)
            return;
        let y = items[0].y;
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (i > 0)
                y += items[i - 1].index === it.index - 1 ? items[i - 1].height + view.spacing : (it.index - items[i - 1].index) * (it.height + view.spacing);
            if (Math.abs(it.y - y) > 0.5)
                it.y = y;
            if (it.opacity < 1)
                it.opacity = 1;
        }
    }

    property Connections _c: Connections {
        target: root.view
        function onCountChanged() { root.restart(); }
        function onVisibleChanged() { root.restart(); }
        function onContentHeightChanged() { root.restart(); }
    }
}
