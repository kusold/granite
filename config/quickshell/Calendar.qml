// M9: the calendar panel, ported from Omarchy Quattro's clock plugin
// (shell/plugins/panels/clock/Panel.qml, MIT) into this config's surface
// recipe: full-screen transparent layer on the focused Hyprland monitor,
// scrim closes, card top-centered under the bar (the clock it answers sits
// centered in that bar), layer takes exclusive keyboard focus.
//
// Omarchy behaviors kept: today's date as a centered hero that doubles as
// the way home once the view has stepped away from it; a year-progress rail
// under the hero (whole days done over days in the year, pinned to today
// rather than to the month being browsed); an always-six-rows month grid
// with ISO week numbers down a gutter on the left, today outlined rather
// than filled; a "W" heading that toggles which day weeks start on (locale
// default first, then Sunday <-> Monday); month stepping by chevrons, the
// scroll wheel, and the arrow keys (Up/Down step whole years), t/T or
// Return back to today, w/W flips the week start, Escape closes.
//
// Deliberately NOT here vs Omarchy: the memento-mori life bar and its
// birth-year editing (their settings persistence lives in shell.json, which
// this config has no counterpart of -- the same reason a cycled clock
// format is session-only), the timezone-picker middle click, tooltips as a
// shared component, and the popout/panel-switching coordinator the plugin
// bar hands panels around with. `qs ipc call clock toggle` still opens it
// without touching the bar.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "CalendarModel.js" as Model

Item {
  id: service

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // Matches Bar.qml's reserved strip; the card hangs just below the bar.
  readonly property int barSize: 30

  // ----- tuning ------------------------------------------------------------

  readonly property int cellWidth: 44
  readonly property int cellHeight: 32
  readonly property int cellSpacing: 2
  readonly property int weekColumnWidth: 28
  readonly property int gutterWidth: 10
  readonly property int gridWidth: weekColumnWidth + cellSpacing + gutterWidth + 7 * cellWidth + 6 * cellSpacing
  readonly property int cardWidth: gridWidth + 28

  // ----- state -------------------------------------------------------------

  property bool opened: false

  // ----- today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading flips it.
  property int weekStart: Model.normalizedWeekStart(null, Qt.locale().firstDayOfWeek)

  // The interface is English throughout, so day names are not taken from
  // the system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, Model.keyForDate(today))

  function open() {
    refresh()
    opened = true
  }

  function close() {
    opened = false
  }

  function toggle() {
    if (opened) close()
    else open()
    return opened ? "opened" : "closed"
  }

  function refresh() {
    today = new Date()
    goToToday()
  }

  function goToToday() {
    viewYear = today.getFullYear()
    viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    viewYear = next.year
    viewMonth = next.month
  }

  function toggleWeekStart() {
    weekStart = Model.toggledWeekStart(weekStart)
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock

    precision: SystemClock.Minutes

    onDateChanged: {
      if (Model.keyForDate(clock.date) === Model.keyForDate(service.today)) return
      var followToday = service.viewingCurrentMonth
      service.today = clock.date
      if (followToday) service.goToToday()
    }
  }

  IpcHandler {
    target: "clock"

    function open(): string {
      service.open()
      return "opened"
    }

    function close(): string {
      service.close()
      return "closed"
    }

    function toggle(): string {
      return service.toggle()
    }
  }

  // ----- the overlay -------------------------------------------------------
  //
  // Same surface recipe as the launcher and audio panel, except the card
  // sits top-centered under the bar instead of mid-screen: it answers the
  // clock, and the clock is centered in the bar.

  PanelWindow {
    id: panel

    visible: service.opened

    screen: {
      var monitor = Hyprland.focusedMonitor
      if (monitor) {
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
          if (screens[i].name === monitor.name) return screens[i]
        }
      }
      return Quickshell.screens[0] || null
    }

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "mike-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) Qt.callLater(card.forceActiveFocus)

    Rectangle {
      anchors.fill: parent
      color: "#66000000"

      MouseArea {
        anchors.fill: parent
        onClicked: service.close()
      }
    }

    Rectangle {
      id: card

      width: service.cardWidth
      height: content.implicitHeight + 28
      anchors.top: parent.top
      anchors.topMargin: service.barSize + 6
      anchors.horizontalCenter: parent.horizontalCenter
      radius: 8
      color: "#f0101014"
      border.width: 1
      border.color: "#26ffffff"

      // Swallow clicks inside the card so they don't reach the scrim and
      // close the panel.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      // The scroll wheel steps months. Horizontal wheels and touchpad
      // side-scrolls report y === 0; without the guard they would every one
      // read as "next month".
      WheelHandler {
        onWheel: function(event) {
          if (event.angleDelta.y === 0) return
          service.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
        }
      }

      Keys.onPressed: function(event) {
        switch (event.key) {
          case Qt.Key_Escape:
            service.close()
            event.accepted = true
            break
          case Qt.Key_Left:
            service.moveMonth(-1)
            event.accepted = true
            break
          case Qt.Key_Right:
            service.moveMonth(1)
            event.accepted = true
            break
          case Qt.Key_Up:
            service.moveMonth(-12)
            event.accepted = true
            break
          case Qt.Key_Down:
            service.moveMonth(12)
            event.accepted = true
            break
          case Qt.Key_Return:
          case Qt.Key_Enter:
          case Qt.Key_T:
            service.goToToday()
            event.accepted = true
            break
          case Qt.Key_W:
            service.toggleWeekStart()
            event.accepted = true
            break
        }
      }

      Column {
        id: content

        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ---- Hero: today, centered. Once the view has stepped back it
        //      is also the way home — clicking the date you are looking
        //      for beats hunting for a reset button.
        Item {
          width: parent.width
          height: heroRow.height

          Row {
            id: heroRow

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Text {
              // Baseline-aligned, not center-aligned: "July 26" carries a
              // descender, so centering the two boxes leaves the icon
              // sitting visibly low against the digits.
              anchors.baseline: heroDate.baseline
              text: "󰃭"
              color: heroMouse.containsMouse ? service.accent : service.foreground
              font.family: service.fontFamily
              // Decorative; sized to read at the cap height of the date
              // beside it rather than towering over it.
              font.pixelSize: 30
            }

            Text {
              id: heroDate

              anchors.verticalCenter: parent.verticalCenter
              text: Qt.formatDate(service.today, "MMMM d")
              color: heroMouse.containsMouse ? service.accent : service.foreground
              font.family: service.fontFamily
              font.pixelSize: 34
              font.bold: true
            }
          }

          MouseArea {
            id: heroMouse

            x: heroRow.x
            y: heroRow.y
            width: heroRow.width
            height: heroRow.height
            enabled: !service.viewingCurrentMonth
            hoverEnabled: enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: service.goToToday()
          }
        }

        // ---- Year progress, doubling as the rule under the hero: a plain
        //      hairline said nothing, and whole days done over days in the
        //      year says the same thing louder.
        Item {
          width: service.gridWidth
          height: Math.max(yearLabel.implicitHeight, 14)
          anchors.horizontalCenter: parent.horizontalCenter

          Text {
            id: yearLabel

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: String(service.today.getFullYear())
            color: Qt.darker(service.foreground, 1.5)
            font.family: service.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1
          }

          Text {
            id: yearPercent

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: service.yearDonePercent + "%"
            color: service.foreground
            font.family: service.fontFamily
            font.pixelSize: 11
          }

          Rectangle {
            anchors.left: yearLabel.right
            anchors.right: yearPercent.left
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.rgba(service.foreground.r, service.foreground.g, service.foreground.b, 0.12)

            Rectangle {
              width: Math.round(parent.width * service.yearDone)
              height: parent.height
              radius: parent.radius
              color: service.accent

              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
        }

        // ---- Month grid: week numbers down a gutter on the left, then
        //      the seven day columns. Always six rows, so the popup is
        //      exactly as tall in February as it is in August.
        Item {
          width: service.gridWidth
          height: gridColumn.y + gridColumn.height
          anchors.horizontalCenter: parent.horizontalCenter

          Column {
            id: gridColumn

            // The rail above is a solid rule; the grid needs room to read
            // as its own block rather than hanging off it.
            y: 8
            spacing: 4

            Row {
              id: headerRow

              spacing: service.cellSpacing

              // The week-number heading doubles as the week-start toggle.
              // It is the one control in the panel whose meaning is not
              // self-evident, so it carries a tip naming the day the click
              // will switch to.
              Rectangle {
                width: service.weekColumnWidth
                height: 18
                radius: 4
                color: weekStartMouse.containsMouse ? "#33ffffff" : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "W"
                  color: weekStartMouse.containsMouse ? service.accent : Qt.darker(service.foreground, 1.9)
                  font.family: service.fontFamily
                  font.pixelSize: 10
                  font.letterSpacing: 1
                  font.bold: true
                }

                MouseArea {
                  id: weekStartMouse

                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: service.toggleWeekStart()
                }

                Rectangle {
                  visible: weekStartMouse.containsMouse
                  y: parent.height + 4
                  x: (parent.width - width) / 2
                  width: tipText.implicitWidth + 12
                  height: tipText.implicitHeight + 6
                  radius: 4
                  color: "#f0101014"
                  border.width: 1
                  border.color: "#26ffffff"
                  z: 10

                  Text {
                    id: tipText

                    anchors.centerIn: parent
                    text: "start weeks on " + service.nextWeekStartLabel
                    color: Qt.darker(service.foreground, 1.5)
                    font.family: service.fontFamily
                    font.pixelSize: 10
                  }
                }
              }

              Item {
                width: service.gutterWidth
                height: 18
              }

              Repeater {
                model: service.weekdays

                delegate: Text {
                  required property var modelData

                  width: service.cellWidth
                  height: 18
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: service.weekdayLabel(modelData)
                  color: Qt.darker(service.foreground, 1.5)
                  font.family: service.fontFamily
                  font.pixelSize: 10
                  font.letterSpacing: 1
                  font.bold: true
                }
              }
            }

            Repeater {
              model: service.weeks

              delegate: Row {
                required property var modelData

                spacing: service.cellSpacing

                Text {
                  width: service.weekColumnWidth
                  height: service.cellHeight
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: modelData.week
                  color: Qt.darker(service.foreground, 1.9)
                  font.family: service.fontFamily
                  font.pixelSize: 10
                }

                Item {
                  width: service.gutterWidth
                  height: service.cellHeight
                }

                Repeater {
                  model: modelData.days

                  delegate: Rectangle {
                    required property var modelData

                    width: service.cellWidth
                    height: service.cellHeight
                    radius: 4
                    // Today is outlined, not filled: a lit-up block shouts
                    // over a grid this quiet.
                    color: "transparent"
                    border.width: modelData.today ? 1 : 0
                    border.color: service.accent

                    Text {
                      anchors.centerIn: parent
                      text: modelData.day
                      color: modelData.inMonth
                        ? (modelData.weekend ? Qt.darker(service.foreground, 1.45) : service.foreground)
                        : Qt.darker(service.foreground, 2.2)
                      font.family: service.fontFamily
                      font.pixelSize: 12
                      font.bold: modelData.today
                    }
                  }
                }
              }
            }
          }

          // Hairline down the week-number gutter, drawn only beside the
          // day rows so it does not cut through the header band.
          Rectangle {
            x: gridColumn.x + service.weekColumnWidth + service.cellSpacing + Math.round((service.gutterWidth - width) / 2)
            y: gridColumn.y + headerRow.height + gridColumn.spacing
            width: 1
            height: gridColumn.height - headerRow.height - gridColumn.spacing
            color: service.foreground
            opacity: 0.1
          }
        }

        // ---- Month stepping, spanning the grid it drives. The chevrons
        //      sit on the grid's outer bounds; the label is centered and
        //      fixed-width, so it holds still from "MAY 2026" to
        //      "SEPTEMBER 2026".
        Item {
          width: service.gridWidth
          height: 24
          anchors.horizontalCenter: parent.horizontalCenter

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: 170
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(service.viewDate, "MMMM yyyy").toUpperCase()
            color: Qt.darker(service.foreground, 1.4)
            font.family: service.fontFamily
            font.pixelSize: 12
            font.letterSpacing: 1
          }

          Rectangle {
            anchors.left: parent.left
            width: 24
            height: 24
            radius: 4
            color: prevMouse.containsMouse ? "#33ffffff" : "transparent"

            Text {
              anchors.centerIn: parent
              text: "󰅁"
              color: service.foreground
              font.family: service.fontFamily
              font.pixelSize: 14
            }

            MouseArea {
              id: prevMouse

              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: service.moveMonth(-1)
            }
          }

          Rectangle {
            anchors.right: parent.right
            width: 24
            height: 24
            radius: 4
            color: nextMouse.containsMouse ? "#33ffffff" : "transparent"

            Text {
              anchors.centerIn: parent
              text: "󰅂"
              color: service.foreground
              font.family: service.fontFamily
              font.pixelSize: 14
            }

            MouseArea {
              id: nextMouse

              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: service.moveMonth(1)
            }
          }
        }
      }
    }
  }
}
