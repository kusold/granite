// Quickshell desktop shell, M1 + M2 + M3 + M4 + M5 + M6 + M7 + M8 + M15: one
// bar per screen (workspaces, focused window title, clock, system tray),
// the notifications daemon (toast stack, do-not-disturb, in-memory
// history), the launcher (fuzzy app search over desktop entries, launched
// through uwsm), the lock screen (ext-session-lock + PAM), the idle policy
// (lock / suspend timers), the session menu (power actions), the clipboard
// history (wl-paste capture, searchable picker), the background +
// screensaver (per-screen wallpaper surface, thumbnail picker, idle
// slideshow), the OSD (volume / brightness / media popups for the media
// keys), and the audio + media panel (MPRIS now-playing + transport over
// the shared media service, output/input volume, default device picking),
// and the calendar panel behind the bar clock (month grid with ISO week
// numbers, year-progress rail — see Calendar.qml).
//
// The architecture follows Omarchy Quattro: a single long-running Quickshell
// instance hosts the whole desktop; bar, launcher, notifications, lock, etc.
// grow here as milestones. See https://github.com/basecamp/omarchy (MIT).
import Quickshell
import QtQuick

ShellRoot {
  Variants {
    model: Quickshell.screens

    delegate: Component {
      Bar {
        required property var modelData

        screen: modelData
        calendar: calendar
      }
    }
  }

  // One notifications daemon for the session; it opens its own toast
  // window per screen (see Notifications.qml).
  Notifications { }

  // The launcher opens its own overlay on the focused monitor (see
  // Launcher.qml).
  Launcher { }

  // M4: lock + idle. Idle locks through the Lock instance in-process; the
  // session menu locks/suspends through it too. The lock also shows the
  // current background blurred behind its field.
  Background { id: background }
  Lock {
    id: lock

    backgroundService: background
  }
  Idle { lock: lock }
  SessionMenu { lock: lock }

  // M5: the clipboard history — capture watchers plus the picker overlay
  // (see Clipboard.qml).
  Clipboard { }

  // M6: the screensaver — an idle slideshow over the background's library
  // (see Screensaver.qml).
  Screensaver {
    background: background
    lock: lock
  }

  // M7: the OSD — volume / brightness / media popups for the media keys
  // (see Osd.qml).
  Osd {
    id: osd

    media: media
  }

  // M8: the media service — the MPRIS player ladder shared by the OSD's
  // media keys, the panel below, and scripts (see Media.qml) — and the
  // audio + media panel (see AudioPanel.qml).
  Media {
    id: media

    osd: osd
  }
  AudioPanel {
    media: media
    osd: osd
  }

  // M15: the calendar panel — the bar clock's click target, ported from
  // Omarchy Quattro's clock plugin (see Calendar.qml).
  Calendar {
    id: calendar
  }
}
