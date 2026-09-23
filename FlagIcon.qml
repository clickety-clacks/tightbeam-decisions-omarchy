import QtQuick
import QtQuick.Shapes

// Tightbeam decisions mark: a swallowtail flag, "flagged for you". Drawn on a
// 24-unit grid as vector paths so it takes any color (theme foreground, or the
// accent when something is new) and stays crisp at bar size.
Item {
  id: root
  property color color: "black"
  property real size: 24
  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: 3
      capStyle: ShapePath.RoundCap
      PathSvg { path: "M5 3V21.5" }
    }
    ShapePath {
      fillColor: root.color
      strokeColor: root.color
      strokeWidth: 1.2
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M6 3.5H21L16.5 9L21 14.5H6Z" }
    }
  }
}
