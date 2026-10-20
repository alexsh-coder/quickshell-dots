import QtQuick
import qs.config

Text {
    property real fill: 1
    property int weight: 600

    font.family: Theme.iconFont
    font.pixelSize: 28
    font.variableAxes: ({ FILL: fill, wght: weight, opsz: 24 })
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
}
