import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as M

Item {
  id: root
  property var manifest: null

  readonly property string pluginId: "omakase"
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/" + pluginId
  readonly property string configPath: configDir + "/config.json"
  readonly property string stateDir: home + "/.local/state/" + pluginId
  readonly property string statePath: stateDir + "/state.json"
  readonly property string journalPath: stateDir + "/journal.json"
  readonly property string planPath: stateDir + "/plan.json"
  readonly property string undoPath: stateDir + "/undo.json"
  readonly property string cacheDir: stateDir + "/cache"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : home + "/.config/omarchy/plugins/" + pluginId

  property var config: ({ home: { lat: 0, lon: 0, city: "" }, radiusKm: 10, refreshIntervalSec: 3600 })
  property var journal: []
  property var plan: []
  property var restaurants: []
  property var recipes: []
  property var drinks: []
  property string lastError: ""
  property bool locatedOnce: false
  property bool firstRun: false
  property var lastUndo: null

  // A rate/decline can be undone within this window.
  readonly property int undoWindowMs: 5 * 60 * 1000

  function stateObject() {
    return {
      updatedAt: Date.now(),
      home: config.home,
      radiusKm: config.radiusKm,
      plan: plan,
      journal: journal,
      lastError: lastError,
      lastActionAt: (lastUndo && lastUndo.at) ? lastUndo.at : 0
    };
  }

  function writeState() {
    stateFile.setText(JSON.stringify(stateObject(), null, 2) + "\n");
  }

  function writeConfig() {
    configFile.setText(JSON.stringify(config, null, 2) + "\n");
  }

  function writeUndo() {
    undoFile.setText(lastUndo ? JSON.stringify(lastUndo, null, 2) + "\n" : "null\n");
  }

  function writeJournal() {
    journalFile.setText(JSON.stringify(journal, null, 2) + "\n");
  }

  function writePlan() {
    planFile.setText(JSON.stringify(plan, null, 2) + "\n");
  }

  function applyUndo(raw) {
    try {
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && parsed.entryId && parsed.item) {
        lastUndo = (Date.now() - (parsed.at || 0) <= undoWindowMs) ? parsed : null;
        return;
      }
    } catch (e) {
      // keep lastUndo null on parse failure
    }
    lastUndo = null;
  }

  function applyConfig(raw) {
    try {
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object") {
        config = M.mergeConfig(config, parsed);
      }
    } catch (e) {
      // keep defaults on parse failure
    }
    if (!locatedOnce && config.home.lat === 0 && config.home.lon === 0) {
      locatedOnce = true;
      locateIp();
    }
    writeState();
    refreshDebounce.restart();
  }

  // Parse a JSON array, falling back to [] on any failure.
  function parseArray(raw) {
    try {
      var parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  function applyJournal(raw) {
    journal = parseArray(raw);
    writeState();
  }

  function applyPlan(raw) {
    plan = parseArray(raw);
    writeState();
  }

  // Cache files feed in-memory catalogs only — they never appear in state.json,
  // so loading one needs no state write (unlike journal/plan, which the widget
  // reads from state).
  function applyCache(kind, raw) {
    var arr = parseArray(raw);
    if (kind === "restaurants") restaurants = arr;
    else if (kind === "recipes") recipes = arr;
    else drinks = arr;
  }

  function allCandidates() {
    return restaurants.concat(recipes);
  }

  function refresh() {
    if (config.home && config.home.lat && config.home.lon) {
      fetchRestaurants();
    }
    fetchRecipes("a"); // TheMealDB "a" returns a broad sample
    fetchDrinks();
    return "ok";
  }

  function runFetch(kind, args) {
    var p = fetchComponent.createObject(root, { svc: root, kind: kind });
    p.command = ["bash", root.sourceDir + "/bin/fetch-" + kind + ".sh"].concat(args || []);
    p.running = true;
  }

  function fetchRestaurants(query) {
    var args = [String(config.home.lat), String(config.home.lon), String(config.radiusKm)];
    if (query) args.push(query);
    runFetch("restaurants", args);
  }

  function fetchRecipes(query) {
    runFetch("recipes", [query]);
  }

  function fetchDrinks() {
    runFetch("drinks", []);
  }

  function handleFetch(kind, exitCode, outText) {
    if (exitCode !== 0) {
      lastError = outText && outText.trim() !== "" ? outText.trim() : "fetch " + kind + " failed";
      writeState();
      return;
    }
    applyCache(kind, outText);
    // On first install only, seed an initial plan once candidates are available
    // and today's plan is empty. Subsequent startups leave an empty plan alone
    // until the next midnight rollover (see refreshTimer).
    if (firstRun && (restaurants.length > 0 || recipes.length > 0)) {
      if (plan.length === 0 || !plan[0].meals || plan[0].meals.length === 0) {
        generatePlan("day");
      }
      markerFile.setText("1\n");
      firstRun = false;
    }
    if (lastError !== "") {
      lastError = "";
      writeState();
    }
  }

  function addMeal(json) {
    try {
      var entry = JSON.parse(json);
      var v = M.validateMeal(entry);
      if (!v.ok) return "error: " + v.error;
      entry.id = entry.id || M.makeId("m");
      entry.timestamp = entry.timestamp || Date.now();
      entry.cuisine = entry.cuisine || M.normalizeCuisine(entry.name);
      journal.push(entry);
      writeJournal();
      writeState();
      return "ok";
    } catch (e) {
      return "error: invalid json";
    }
  }

  function removeMeal(id) {
    journal = journal.filter(function(e) { return e.id !== id; });
    writeJournal();
    writeState();
    return "ok";
  }

  function generatePlan(period) {
    var p = period || "day";
    if (p === "day" && plan.length > 0 && plan[0].date === todayStr() && plan[0].meals && plan[0].meals.length > 0) {
      return "ok"; // sticky: keep today's plan, do not re-scramble
    }
    buildPlan(p);
    return "ok";
  }

  function todayStr() {
    var d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }

  function buildPlan(period) {
    var p = period || "day";
    plan = M.generatePlan(allCandidates(), journal, { period: p, radiusKm: config.radiusKm, drinks: drinks });
    writePlan();
    writeState();
  }

  function recordMeal(id, extras) {
    for (var d = 0; d < plan.length; d++) {
      for (var m = 0; m < plan[d].meals.length; m++) {
        var item = plan[d].meals[m];
        if (item.id !== id) continue;
        var entry = {
          id: M.makeId("m"),
          timestamp: Date.now(),
          mealType: item.mealType,
          name: item.name,
          cuisine: item.cuisine,
          source: item.source,
          drink: item.drink || "",
          restaurantId: item.source === "restaurant" ? item.id : undefined,
          recipeId: item.source === "recipe" ? item.id : undefined,
          declined: !!(extras && extras.declined === true)
        };
        if (extras && typeof extras.rating === "number") entry.rating = extras.rating;
        var n = (extras && typeof extras.notes === "string") ? extras.notes.trim() : "";
        if (n !== "") entry.notes = n;
        journal.push(entry);
        writeJournal();
        lastUndo = {
          entryId: entry.id,
          item: JSON.parse(JSON.stringify(item)),
          dayIndex: d,
          mealIndex: m,
          at: Date.now()
        };
        writeUndo();
        plan[d].meals.splice(m, 1);
        writePlan();
        writeState();
        return "ok";
      }
    }
    return "error: plan item not found";
  }

  function rate(id, rating, notes) {
    var r = Number(rating);
    if (isNaN(r) || r < 1 || r > 5) return "error: rating must be 1-5";
    return recordMeal(id, { rating: r, notes: notes });
  }

  function decline(id, notes) {
    return recordMeal(id, { declined: true, notes: notes });
  }

  function undo() {
    if (!lastUndo) return "error: nothing to undo";
    if (Date.now() - lastUndo.at > undoWindowMs) {
      lastUndo = null;
      writeUndo();
      writeState();
      return "error: too late to undo";
    }
    journal = journal.filter(function(e) { return e.id !== lastUndo.entryId; });
    var day = plan[lastUndo.dayIndex];
    if (!day || !Array.isArray(day.meals)) {
      if (plan.length === 0) plan.push({ date: todayStr(), meals: [] });
      day = plan[0];
    }
    var insertAt = Math.min(Math.max(0, lastUndo.mealIndex), day.meals.length);
    day.meals.splice(insertAt, 0, lastUndo.item);
    // Re-rank the day: removing the rate/decline entry changes the restored
    // meal's score, so recompute it (and any meal whose score shifted) instead
    // of leaving the stale pre-action score on the re-inserted item.
    day.meals = M.reScorePlan(day.meals, allCandidates(), journal, { radiusKm: config.radiusKm, drinks: drinks });
    writeJournal();
    writePlan();
    writeState();
    lastUndo = null;
    writeUndo();
    return "ok";
  }

  function searchRestaurants(query) {
    if (config.home && config.home.lat && config.home.lon) {
      fetchRestaurants(query);
    }
    return "ok";
  }

  function searchRecipes(query) {
    fetchRecipes(query);
    return "ok";
  }

  function validCoords(lat, lon) {
    return isFinite(lat) && isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  function setHome(lat, lon) {
    var nlat = Number(lat);
    var nlon = Number(lon);
    if (!validCoords(nlat, nlon)) {
      return "error: coordinates out of range";
    }
    config.home.lat = nlat;
    config.home.lon = nlon;
    writeConfig();
    refresh();
    return "ok";
  }

  function locateIp() {
    var p = locateComponent.createObject(root, { svc: root });
    p.command = ["bash", root.sourceDir + "/bin/locate-ip.sh"];
    p.running = true;
    return "ok";
  }

  function handleLocate(exitCode, outText) {
    if (exitCode !== 0 || !outText) return;
    try {
      var parsed = JSON.parse(outText);
      var nlat = Number(parsed.lat);
      var nlon = Number(parsed.lon);
      if (!validCoords(nlat, nlon) || nlat === 0 || nlon === 0) {
        return; // reject bogus (0,0) or out-of-range coordinates
      }
      config.home.lat = nlat;
      config.home.lon = nlon;
      config.home.city = parsed.city || "";
      writeConfig();
      refresh();
    } catch (e) {
      // ignore malformed geolocation output
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaveFailed: {
      Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
      stateRetryTimer.restart();
    }
  }

  FileView {
    id: journalFile
    path: root.journalPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyJournal(text())
    onLoadFailed: root.applyJournal("")
    onFileChanged: reload()
  }

  FileView {
    id: planFile
    path: root.planPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPlan(text())
    onLoadFailed: root.applyPlan("")
    onFileChanged: reload()
  }

  FileView {
    id: undoFile
    path: root.undoPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyUndo(text())
    onLoadFailed: root.applyUndo("")
    onFileChanged: reload()
  }

  // First-install marker: absent on the very first run, present afterwards.
  // Its presence gates the one-time plan seeding in handleFetch.
  FileView {
    id: markerFile
    path: root.stateDir + "/.initialized"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.firstRun = false
    onLoadFailed: root.firstRun = true
  }

  // The bin/ fetch scripts write the cache files; the service only reads them
  // back through these watchers, so there is one per catalog kind.
  Instantiator {
    model: ["restaurants", "recipes", "drinks"]
    delegate: FileView {
      required property string modelData
      path: root.cacheDir + "/" + modelData + ".json"
      watchChanges: true
      printErrors: false
      onLoaded: root.applyCache(modelData, text())
      onLoadFailed: root.applyCache(modelData, "")
      onFileChanged: reload()
    }
  }

  Timer {
    id: refreshDebounce
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    // Lower bound of 60s keeps a refreshIntervalSec of 0 from spinning a tight loop.
    interval: Math.max(Math.round(Number(config.refreshIntervalSec)) || 3600, 60) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh();
      // Regenerate the plan only when the day rolls over (local midnight) — a
      // fresh plan for the new day. Empty plans are filled immediately at
      // startup (see handleFetch), not on this timer.
      if (plan.length > 0 && plan[0].date !== todayStr()) {
        root.generatePlan("day");
      }
    }
  }

  Timer {
    id: stateRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.writeState()
  }

  Component {
    id: fetchComponent
    Process {
      id: self
      property var svc: null
      property string kind: ""
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true } // drain: unread, but keeps the child from blocking on a full stderr pipe
      onExited: function(exitCode) {
        self.svc.handleFetch(self.kind, exitCode, out.text);
        self.destroy();
      }
    }
  }

  Component {
    id: locateComponent
    Process {
      id: self
      property var svc: null
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true } // drain: unread, but keeps the child from blocking on a full stderr pipe
      onExited: function(exitCode) {
        self.svc.handleLocate(exitCode, out.text);
        self.destroy();
      }
    }
  }

  IpcHandler {
    target: root.pluginId
    function ping(): string { return "ok" }
    function refresh(): string { return root.refresh() }
    function addMeal(json: string): string { return root.addMeal(json) }
    function removeMeal(id: string): string { return root.removeMeal(id) }
    function generatePlan(period: string): string { return root.generatePlan(period) }
    function rate(id: string, rating: string, notes: string): string { return root.rate(id, rating, notes) }
    function decline(id: string, notes: string): string { return root.decline(id, notes) }
    function undo(): string { return root.undo() }
    function searchRestaurants(query: string): string { return root.searchRestaurants(query) }
    function searchRecipes(query: string): string { return root.searchRecipes(query) }
    function setHome(lat: string, lon: string): string { return root.setHome(lat, lon) }
    function locateIp(): string { return root.locateIp() }
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.configDir]);
    Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
    Quickshell.execDetached(["mkdir", "-p", root.cacheDir]);
  }
}
