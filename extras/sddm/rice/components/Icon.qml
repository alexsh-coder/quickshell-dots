import QtQuick

Text {
    property real fill: 0
    property int weight: 400

    font.family: "Material Symbols Rounded"
    font.pixelSize: 22
    font.variableAxes: ({ FILL: fill, wght: weight, opsz: 24 })
    verticalAlignment: Text.AlignVCenter
}
