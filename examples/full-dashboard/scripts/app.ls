let dirty = false;
let lastSeries = Array(uint8, 10);

function setText(id, text) {
  let el = getElement(id);
  if (el != null) el.text = text;
}

function showToast(title, text) {
  setText("toastTitle", title);
  setText("toastText", text);
}

function setView(title) {
  setText("viewTitle", title);
  session.set("dashboard.view", title);
}

function showOverview(e) {
  setView("Overview");
  showToast("Overview", "Showing service summary.");
}

function showIncidents(e) {
  setView("Incidents");
  showToast("Incidents", "Showing incident queue.");
}

function showSettings(e) {
  setView("Settings");
  showToast("Settings", "Showing saved preferences.");
}

function filterOpen(e) {
  showToast("Filter", "Open incidents only.");
}

function filterHigh(e) {
  showToast("Filter", "High priority incidents.");
}

function filterMine(e) {
  showToast("Filter", "Assigned to current operator.");
}

function filterAll(e) {
  showToast("Filter", "All incidents.");
}

function markDirty(e) {
  dirty = true;
  setText("formStatus", "draft changed");

  let title = getElement("incidentTitle");
  let owner = getElement("incidentOwner");
  if (title != null) storage.set("incident.title", title.text);
  if (owner != null) storage.set("incident.owner", owner.text);
}

function clearDraft(e) {
  let title = getElement("incidentTitle");
  let owner = getElement("incidentOwner");
  if (title != null) title.text = "";
  if (owner != null) owner.text = "";
  storage.remove("incident.title");
  storage.remove("incident.owner");
  dirty = false;
  setText("formStatus", "draft cleared");
}

function createIncident(e) {
  let title = getElement("incidentTitle");
  let owner = getElement("incidentOwner");

  if (title == null || owner == null) return;

  if (!Format.nonEmpty(title.text)) {
    setText("formStatus", "title is required");
    return;
  }

  if (!Format.nonEmpty(owner.text)) {
    setText("formStatus", "owner is required");
    return;
  }

  let req = Request("/api/incidents", "POST");
  req.contentType = "application/json";
  req.body = jsonEncode({ title: title.text, owner: owner.text });
  req.timeout = 5000;

  req.send(func(r) {
    if (!r.ok) {
      setText("formStatus", "create failed: " + r.error);
      return;
    }

    setText("formStatus", "created");
    showToast("Incident created", title.text);
    dirty = false;
  });
}

function refreshData(e) {
  let req = Request("/api/dashboard", "GET");
  req.timeout = 4000;

  req.send(func(r) {
    if (!r.ok) {
      showToast("Refresh failed", r.error);
      return;
    }

    setText("availability", Format.percent(9998));
    setText("latency", Format.ms(184));
    drawTraffic();
    showToast("Refreshed", "Latest dashboard data loaded.");
  });
}

function drawTraffic() {
  let canvas = getElement("trafficChart");
  if (canvas == null) return;

  lastSeries[0] = 34;
  lastSeries[1] = 42;
  lastSeries[2] = 58;
  lastSeries[3] = 63;
  lastSeries[4] = 74;
  lastSeries[5] = 69;
  lastSeries[6] = 84;
  lastSeries[7] = 77;
  lastSeries[8] = 90;
  lastSeries[9] = 88;

  let ctx = canvas.context();
  Charts.drawTraffic(ctx, lastSeries);
}

function restoreDraft() {
  let title = storage.get("incident.title");
  let owner = storage.get("incident.owner");
  let titleEl = getElement("incidentTitle");
  let ownerEl = getElement("incidentOwner");

  if (title != null && titleEl != null) titleEl.text = title;
  if (owner != null && ownerEl != null) ownerEl.text = owner;
}

document.on("rendered", func(e) {
  restoreDraft();
  drawTraffic();

  let view = session.get("dashboard.view");
  if (view != null) setText("viewTitle", view);
});

document.on("resize", func(e) {
  drawTraffic();
});

document.on("error", func(e) {
  showToast("Script error", e.code + ": " + e.message);
});
