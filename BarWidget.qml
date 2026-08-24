import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as M

Panel {
  id: root
  moduleName: "omakase"
  manageIpc: false

  readonly property string pluginId: "omakase"
  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/" + pluginId + "/state.json"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Shared row-state fills, resolved against the panel foreground so every
  // CursorSurface row paints the same hover/selected chrome as first-party
  // panels (tailscale, network, audio).
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)

  property var state: ({})
  property string view: "plan"

  // Undo stays available for this long after the last rating or decline.
  readonly property int undoWindowMs: 5 * 60 * 1000
  property int nowMs: Date.now()
  readonly property bool undoRecent: root.state.lastActionAt > 0 && (root.nowMs - root.state.lastActionAt) < root.undoWindowMs

  implicitWidth: barRow.implicitWidth
  implicitHeight: barRow.implicitHeight

  // Today's plan = the first day's meals.
  readonly property var todayMeals: {
    var p = root.state.plan;
    return (p && p.length > 0 && Array.isArray(p[0].meals)) ? p[0].meals : [];
  }

  // Full journal, newest first.
  readonly property var historyJournal: {
    var j = root.state.journal || [];
    return Array.isArray(j)
      ? j.slice().sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0); })
      : [];
  }

  // Meals grouped by mealType, preserving plan order within each group.
  readonly property var mealTypes: ["breakfast", "lunch", "dinner", "snack"]
  readonly property var mealsByType: {
    var groups = {};
    for (var i = 0; i < root.mealTypes.length; i++) groups[root.mealTypes[i]] = [];
    var meals = root.todayMeals;
    for (var j = 0; j < meals.length; j++) {
      var mt = String(meals[j].mealType || "");
      if (groups[mt]) groups[mt].push(meals[j]);
    }
    return groups;
  }

  function runIpc(args) {
    Quickshell.execDetached(["omarchy-shell", "-q", root.pluginId].concat(args));
  }

  function cleanNote(notes) {
    return (notes !== undefined && notes !== null) ? String(notes).trim() : "";
  }

  function rate(id, rating, notes) {
    runIpc(["rate", String(id), String(rating), cleanNote(notes)]);
  }
  function decline(id, notes) {
    runIpc(["decline", String(id), cleanNote(notes)]);
  }
  function undo() { runIpc(["undo"]); }
  function formatDate(ts) { return M.formatTimestamp(Number(ts)); }

  function openWebsite(raw) {
    var u = String(raw || "");
    if (u === "") return;
    if (u.indexOf("://") === -1) u = "https://" + u;
    Quickshell.execDetached(["xdg-open", u]);
  }

  // Copy text to the clipboard. Passed as a positional arg to avoid shell
  // injection; wl-copy is preferred on Wayland with xclip as fallback.
  function copyToClipboard(text) {
    var t = String(text || "");
    if (t === "") return;
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null", "sh", t]);
  }

  function reloadState() {
    try {
      root.state = JSON.parse(String(stateFile.text() || "{}"));
    } catch (e) {
      root.state = {};
    }
  }

  function toggleView() {
    root.view = (root.view === "plan") ? "history" : "plan";
  }

  // Map a cuisine string to a Material Symbols food glyph (Nerd Fonts v3
  // supplementary plane). Falls back to the flatware glyph for unknown
  // cuisines so the row always has a leading icon.
  function cuisineGlyph(cuisine) {
    var s = String(cuisine || "").toLowerCase();
    if (s.indexOf("italian") !== -1) return "󰐉";
    if (s.indexOf("japanese") !== -1) return "󱅾";
    if (s.indexOf("sushi") !== -1) return "󰈺";
    if (s.indexOf("chinese") !== -1) return "󰟪";
    if (s.indexOf("thai") !== -1) return "󰟪";
    if (s.indexOf("vietnamese") !== -1) return "󱅾";
    if (s.indexOf("indian") !== -1) return "󰋥";
    if (s.indexOf("mexican") !== -1) return "󰝢";
    if (s.indexOf("french") !== -1) return "󰼾";
    if (s.indexOf("greek") !== -1) return "󰊎";
    if (s.indexOf("mediterranean") !== -1) return "󰊎";
    if (s.indexOf("american") !== -1) return "󰚅";
    if (s.indexOf("bbq") !== -1) return "󱐟";
    if (s.indexOf("breakfast") !== -1) return "󱡊";
    if (s.indexOf("bakery") !== -1) return "󰳮";
    if (s.indexOf("dessert") !== -1) return "󰃩";
    if (s.indexOf("seafood") !== -1) return "󰈺";
    if (s.indexOf("vegan") !== -1) return "󰌪";
    if (s.indexOf("vegetarian") !== -1) return "󰌪";
    if (s.indexOf("coffee") !== -1) return "󰅶";
    if (s.indexOf("cafe") !== -1) return "󰅶";
    if (s.indexOf("bar") !== -1) return "󰂘";
    if (s.indexOf("drink") !== -1) return "󰡶";
    return "󰩰";
  }

  function mealTypeLabel(mt) {
    return String(mt || "").toUpperCase();
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadState()
    onLoadFailed: root.state = ({})
    onFileChanged: reload()
  }

  component Field: Column {
    id: self
    property string label: ""
    property string placeholder: ""
    property alias text: input.text
    signal fieldTextChanged(string text)
    width: parent.width
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      text: self.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: input
      width: parent.width
      placeholderText: self.placeholder
      foreground: root.foreground
      font.family: root.fontFamily
      onTextChanged: self.fieldTextChanged(text)
      Keys.onEscapePressed: focus = false
    }
  }

  Row {
    id: barRow
    spacing: Style.space(2)

    WidgetButton {
      bar: root.bar
      text: "\uf2e7" // nerd-font fa-utensils (Font Awesome, retained in Nerd Fonts v3)
      labelVisible: true
      hasVisualContent: true
      horizontalMargin: Style.space(6)
      tooltipText: "Omakase — what should I eat?"
      onPressed: function(b) {
        if (b === Qt.LeftButton) root.toggle();
      }
    }
  }

  Item {
    id: anchorStub
    anchors.right: barRow.right
    anchors.verticalCenter: barRow.verticalCenter
    width: Math.min(barRow.width, Style.space(220))
    height: 1
  }

  KeyboardPanel {
    id: popup
    anchorItem: anchorStub
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Flickable {
      id: flick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width - Style.space(10)
        spacing: Style.space(12)

        // The hero's trailingControl resolves its `root` to PanelHero, not
        // this Panel, so panel state is bridged through this header Item.
        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight

          readonly property string viewLabel: root.view === "plan" ? "History" : "Plan"
          function toggleView() { root.toggleView() }

          PanelHero {
            id: hero
            width: parent.width
            title: "Omakase"
            meta: root.state.home && root.state.home.city ? root.state.home.city : "No home set"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text { text: "\uf2e7"; color: root.foreground; font.family: root.fontFamily }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: header.viewLabel === "History" ? "\uf1da" : "\uf2e7" // fa-history / fa-utensils
                tooltipText: "Switch to " + header.viewLabel
                foreground: hero.foreground
                fontFamily: root.fontFamily
                onClicked: header.toggleView()
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- Plan view: today's meals grouped by mealType.
        Column {
          visible: root.view === "plan"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "󰃶  TODAY"
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 1.2
          }

          Text {
            visible: root.todayMeals.length === 0
            width: parent.width
            text: "No meals planned for today."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            visible: root.todayMeals.length > 0
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: root.mealTypes
              delegate: Column {
                required property string modelData
                readonly property var groupMeals: root.mealsByType[modelData] || []
                visible: groupMeals.length > 0
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: root.mealTypeLabel(modelData)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  font.letterSpacing: 1.2
                }

                Repeater {
                  model: groupMeals
                  delegate: MealRow {
                    required property var modelData
                    width: parent.width
                    meal: modelData
                  }
                }
              }
            }
          }
        }

        // ---- History view: journal entries, newest first.
        Column {
          visible: root.view === "history"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "󰋚  HISTORY"
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 1.2
          }

          Text {
            visible: root.historyJournal.length === 0
            width: parent.width
            text: "No meals logged yet."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            visible: root.historyJournal.length > 0
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.historyJournal
              delegate: HistoryRow {
                required property int index
                required property var modelData
                width: parent.width
                entry: modelData
                isNewest: index === 0
              }
            }
          }
        }

        PanelSeparator { visible: !!root.state.lastError; foreground: root.foreground }

        Text {
          text: root.state.lastError || ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          visible: !!root.state.lastError
        }
      }
    }
  }

  // A meal row: cuisine glyph, name, blurb caption, and a "Pairs with" drink
  // line. Clicking expands a note field; the action row is [✕][1][2][3][4][5].
  component MealRow: CursorSurface {
    id: mealRow
    property var meal: null
    property bool expanded: false
    property string note: ""

    readonly property bool isRestaurant: meal && meal.source === "restaurant"
    readonly property bool hasWebsite: isRestaurant && !!meal.website
    readonly property string captionText: meal && meal.blurb ? String(meal.blurb) : ""

    readonly property string shareText: {
      var m = meal;
      if (!m) return "";
      var parts = [String(m.name || "")];
      if (m.cuisine) parts.push(String(m.cuisine));
      if (m.address) parts.push(String(m.address));
      if (m.website) parts.push(String(m.website));
      if (m.drink) parts.push("pairs with " + String(m.drink));
      return parts.join(" · ");
    }

    hasCursor: mouse.containsMouse
    current: expanded
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: body.implicitHeight + Style.spacing.xl

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mealRow.expanded = !mealRow.expanded
    }

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(6)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.cuisineGlyph(meal ? meal.cuisine : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            text: String(meal ? meal.name : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            visible: mealRow.captionText !== ""
            text: mealRow.captionText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Row {
            visible: meal && !!meal.drink
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "Pairs with: " + String(meal.drink || "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Image {
              visible: !!meal.drinkThumb
              source: meal.drinkThumb
              width: Style.space(16)
              height: Style.space(16)
              fillMode: Image.PreserveAspectFit
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Row {
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(2)

          PanelActionButton {
            visible: mealRow.hasWebsite
            iconText: "\uf08e" // fa-external-link (free FA, retained in Nerd Fonts v3)
            tooltipText: "Open website"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openWebsite(mealRow.meal.website)
          }

          PanelActionButton {
            iconText: "\uf0c5" // fa-copy (free FA, retained in Nerd Fonts v3)
            tooltipText: "Copy to share"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.copyToClipboard(mealRow.shareText)
          }

          PanelActionButton {
            iconText: "\uf00d" // fa-times
            tooltipText: "Decline"
            foreground: root.foreground
            hoverColor: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.decline(mealRow.meal.id, mealRow.note)
          }

          Repeater {
            model: [1, 2, 3, 4, 5]
            delegate: PanelActionButton {
              required property int modelData
              iconText: String(modelData)
              tooltipText: "Rate " + String(modelData)
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.rate(mealRow.meal.id, modelData, mealRow.note)
            }
          }
        }
      }

      Column {
        visible: mealRow.expanded
        width: parent.width
        spacing: Style.space(6)

        Field {
          label: "Note"
          placeholder: "Optional note"
          text: mealRow.note
          onFieldTextChanged: (t) => mealRow.note = t
        }
      }
    }
  }

  // A journal entry: name + rating/declined on the first line, date · cuisine
  // below. The newest entry shows undo while the 5-minute window lasts.
  component HistoryRow: CursorSurface {
    id: historyRow
    property var entry: null
    property bool isNewest: false

    readonly property bool hasRating: entry && typeof entry.rating === "number"
    readonly property string metaText: {
      var parts = [];
      if (entry && entry.timestamp) parts.push(root.formatDate(entry.timestamp));
      if (entry && entry.cuisine) parts.push(String(entry.cuisine));
      if (entry && entry.drink) parts.push("with " + String(entry.drink));
      if (entry && entry.notes) parts.push(String(entry.notes));
      return parts.join(" · ");
    }

    hasCursor: mouse.containsMouse
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: body.implicitHeight + Style.spacing.xl

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
    }

    RowLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "\uf017" // fa-clock
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Row {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            text: String(entry ? entry.name : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            visible: historyRow.hasRating
            text: "★".repeat(entry.rating)
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            visible: entry && entry.declined === true
            text: "declined"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          PanelActionButton {
            visible: historyRow.isNewest && root.undoRecent
            iconText: "\uf0e2" // fa-undo
            tooltipText: "Undo"
            foreground: root.foreground
            fontFamily: root.fontFamily
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.undo()
          }
        }

        Text {
          visible: historyRow.metaText !== ""
          text: historyRow.metaText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
    }
  }

  Timer {
    id: undoRefresh
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: {
    if (opened) {
      root.nowMs = Date.now();
      Qt.callLater(function() {
        if (flick) flick.contentY = 0;
        if (keyCatcher) keyCatcher.forceActiveFocus();
      });
    }
  }
}
