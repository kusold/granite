// One toast card: app icon (the notification's image, a themed icon, or a
// bell glyph fallback), bold summary, wrapped body, hover-revealed close
// button, and an urgency-tinted countdown bar along the bottom. Styled to
// match Bar.qml. Purely presentational — Notifications.qml owns the server
// object, the lifetime, and dismissal.
import Quickshell
import QtQuick

Rectangle {
  id: root

  // Palette and font match Bar.qml.
  property string fontFamily: "JetBrainsMono Nerd Font"
  property color foreground: "#f2f2f2"
  property color accent: "#00ff99"
  property color critical: "#ff5555"

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // NotificationUrgency: Low = 0, Normal = 1, Critical = 2.
  property int urgency: 1
  // 1 -> 0 while the toast counts down (Notifications.qml drives it); a
  // critical toast never ticks and keeps the countdown bar hidden.
  property real remainingLifetime: 1.0

  signal closeRequested()
  signal cardClicked()

  readonly property bool hovered: hover.hovered
  readonly property color dimColor: Qt.darker(foreground, 1.5)
  readonly property color urgencyColor: urgency === 2 ? critical : urgency === 0 ? dimColor : accent

  // Prefer the notification's own image, then the sender's themed icon.
  // iconPath(icon, true) yields "" for unknown icon names so the glyph
  // fallback shows instead of Qt's broken-image placeholder.
  readonly property string iconSource: {
    var value = String(image || "")
    if (value.length > 0) return value
    value = String(appIcon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0 || value.indexOf("/") === 0)
      return value
    return Quickshell.iconPath(value, true)
  }

  width: 380
  height: contentRow.implicitHeight + 24
  radius: 8
  color: "#f0101014"
  border.width: 1
  border.color: urgency === 2 ? "#66ff5555" : "#26ffffff"

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  Row {
    id: contentRow

    anchors.fill: parent
    anchors.margins: 12
    spacing: 12

    Item {
      id: iconSlot

      width: 36
      height: 36
      anchors.verticalCenter: parent.verticalCenter
      // Collapse the slot when neither an icon nor the glyph can render,
      // letting the text claim the full card width.
      visible: iconImage.status === Image.Ready || glyph.text.length > 0

      Image {
        id: iconImage

        anchors.fill: parent
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
      }

      // Bell glyph while no image is resolved (or is still loading).
      Text {
        id: glyph

        anchors.centerIn: parent
        visible: iconImage.status !== Image.Ready
        text: root.iconSource.length === 0 ? "󰂚" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 24
      }
    }

    Column {
      id: texts

      width: contentRow.width - (iconSlot.visible ? iconSlot.width + contentRow.spacing : 0)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Text {
        width: texts.width
        visible: summary.length > 0
        // The spec defines the summary as a single line of plain text.
        textFormat: Text.PlainText
        text: summary
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 2
      }

      Text {
        width: texts.width
        visible: text.length > 0
        textFormat: Text.PlainText
        text: body
        color: root.dimColor
        font.family: root.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 3
      }
    }
  }

  // Hover-revealed close. Stacked after the content so its MouseArea sits
  // above the full-card one and the click never reaches cardClicked.
  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 4
    anchors.rightMargin: 4
    width: 20
    height: 20
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: "✕"
      color: closeArea.containsMouse ? root.foreground : root.dimColor
      font.family: root.fontFamily
      font.pixelSize: 11
    }

    MouseArea {
      id: closeArea

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }

  // Countdown bar, tinted by urgency. Visible only once the lifetime is
  // actually ticking down (critical and replayed toasts never show it).
  Rectangle {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: parent.width * root.remainingLifetime
    height: 2
    visible: root.remainingLifetime < 1.0
    color: root.urgencyColor
  }
}
