const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

let appsGrid, runView, runAppName, runAppUrl, runUptime, runNote;
let backToApps, openRunning, openLocal, restartRunning, stopRunning, shareRunning;
let doctorOutput, statusText, appsFolder, addAppSubmit, newAppSubmit;
let activityPanel, activityStatus, activityLog;

const views = {};

const state = {
  apps: [],
  busy: false,
  running: null,
  uptimeTimer: null,
};

function setStatus(message, isError = false) {
  if (!statusText) statusText = document.querySelector(".status-text");
  if (!statusText) return;
  statusText.textContent = message;
  statusText.parentElement.style.background = isError
    ? "rgba(229, 72, 77, 0.25)"
    : "rgba(248, 250, 252, 0.08)";
}

function showToast(message) {
  const toast = document.createElement("div");
  toast.className = "toast";
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 2800);
}

function resetActivity(message = "Idle") {
  if (!activityPanel) activityPanel = document.querySelector("#activity-panel");
  if (!activityPanel) return;
  if (!activityStatus) activityStatus = document.querySelector("#activity-status");
  if (!activityStatus) return;
  activityStatus.textContent = message;
  activityPanel.classList.remove("is-busy");
}

function appendLog(line) {
  if (!activityPanel) activityPanel = document.querySelector("#activity-panel");
  if (!activityPanel) return;
  if (!activityLog) activityLog = document.querySelector("#activity-log");
  if (!activityLog) return;
  if (activityLog.textContent === "Logs will appear here.") {
    activityLog.textContent = "";
  }
  activityLog.textContent += `${line}\n`;
  activityLog.scrollTop = activityLog.scrollHeight;
}

function switchView(view) {
  if (!views.apps) {
    views.apps = document.querySelector("#apps-view");
    views.doctor = document.querySelector("#doctor-view");
    views.run = document.querySelector("#run-view");
  }
  Object.keys(views).forEach((key) => {
    views[key].classList.toggle("is-hidden", key !== view);
  });

  const btns = document.querySelectorAll(".nav-item");
  btns.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.view === view);
  });
}

function renderApps(apps) {
  if (!appsGrid) {
    appsGrid = document.querySelector("#apps-grid");
  }
  if (!appsGrid) return;
  if (!apps.length) {
    appsGrid.innerHTML = `
      <div class="apps-table-container">
        <table class="apps-table">
          <thead>
            <tr>
              <th>App</th>
              <th>Domain</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td colspan="4" style="text-align:center;padding:32px;color:var(--ink-soft);">
                No apps yet. Create a new Rails app or add an existing folder.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    `;
    return;
  }

  appsGrid.innerHTML = `
    <div class="apps-table-container">
      <table class="apps-table">
        <thead>
          <tr>
            <th>App</th>
            <th>Domain</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${apps.map(app => `
            <tr>
              <td>
                <button type="button" class="app-name-link" data-action="details" data-app="${app.name}">${app.name}</button>
              </td>
              <td>
                <button type="button" class="link" data-action="open" data-app="${app.name}">${app.url}</button>
              </td>
              <td>
                <span class="status-badge ${state.running?.name === app.name ? 'running' : ''}">
                  ${state.running?.name === app.name ? 'Running' : 'Stopped'}
                </span>
              </td>
              <td class="actions-cell">
                <div class="actions-row">
                  <button type="button" class="btn-action btn-open" data-action="open" data-app="${app.name}">Open</button>
                  <button type="button" class="btn-action btn-start" data-action="start" data-app="${app.name}">Start</button>
                  <button type="button" class="btn-action btn-stop" data-action="stop" data-app="${app.name}">Stop</button>
                  <button type="button" class="btn-action btn-restart" data-action="restart" data-app="${app.name}">Restart</button>
                  <button type="button" class="btn-action btn-remove" data-action="remove" data-app="${app.name}">Remove</button>
                </div>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function updateButtonStates() {
  const startAllBtn = document.querySelector("#start-all");
  const stopAllBtn = document.querySelector("#stop-all");
  const hasApps = state.apps.length > 0;
  const hasStoppedApps = state.apps.some(app => state.running?.name !== app.name);
  const hasRunningApp = state.running !== null;

  if (startAllBtn) {
    startAllBtn.disabled = !hasApps || !hasStoppedApps;
    startAllBtn.style.opacity = (!hasApps || !hasStoppedApps) ? "0.5" : "1";
  }
  if (stopAllBtn) {
    stopAllBtn.disabled = !hasRunningApp;
    stopAllBtn.style.opacity = !hasRunningApp ? "0.5" : "1";
  }
}

async function loadApps() {
  setStatus("Syncing apps...");
  try {
    const apps = await invoke("list_apps");
    state.apps = apps;
    renderApps(apps);
    updateButtonStates();
    setStatus("Ready");
  } catch (error) {
    setStatus("Error loading apps", true);
    showToast(String(error));
  }
}

async function runDoctor() {
  setStatus("Running doctor...");
  try {
    const result = await invoke("doctor");
    doctorOutput.textContent = result.report;
    setStatus("Doctor complete");
  } catch (error) {
    setStatus("Doctor failed", true);
    showToast(String(error));
  }
}

async function addApp() {
  const input = document.querySelector("#existing-app-path");
  if (!input) return;
  const folder = input.value.trim();
  if (!folder) {
    showToast("Enter a folder path first");
    return;
  }
  setStatus("Adding app...");
  try {
    await invoke("add_app", { folder });
    input.value = "";
    showToast("App added");
    loadApps();
  } catch (error) {
    setStatus("Add failed", true);
    showToast(String(error));
  }
}

async function newApp() {
  const input = document.querySelector("#new-app-name");
  if (!input) return;
  const name = input.value.trim();
  if (!name) {
    showToast("Enter an app name first");
    return;
  }
  setStatus("Creating app...");
  if (activityPanel) {
    activityStatus.textContent = "Creating app...";
    activityLog.textContent = "";
    activityPanel.classList.add("is-busy");
  }
  appendLog("Initializing create...");
  startAppCreationChecker();
  try {
    await invoke("create_app", { name });
    input.value = "";
    showToast("App creation started in background");
  } catch (error) {
    stopAppCreationChecker();
    setStatus("Create failed", true);
    if (activityPanel) {
      activityStatus.textContent = "Create failed";
      activityPanel.classList.remove("is-busy");
    }
    appendLog(`ERROR: ${error}`);
    showToast(String(error));
  }
}

let appCreationCheckInterval = null;

function startAppCreationChecker() {
  if (appCreationCheckInterval) return;
  appCreationCheckInterval = setInterval(() => {
    loadApps();
  }, 2000);
}

function stopAppCreationChecker() {
  if (appCreationCheckInterval) {
    clearInterval(appCreationCheckInterval);
    appCreationCheckInterval = null;
  }
}

function formatUptime(startedAt) {
  const diff = Date.now() - startedAt;
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  }
  return `${seconds}s`;
}

function showRunView(app) {
  state.running = {
    ...app,
    startedAt: Date.now(),
  };
  const appNameLink = document.getElementById("run-app-name-link");
  if (appNameLink) appNameLink.textContent = app.name;
  runAppUrl.textContent = app.url;
  runNote.textContent = "Your app is served via Caddy with TLS.";
  runUptime.textContent = formatUptime(state.running.startedAt);
  if (state.uptimeTimer) {
    clearInterval(state.uptimeTimer);
  }
  state.uptimeTimer = setInterval(() => {
    runUptime.textContent = formatUptime(state.running.startedAt);
  }, 1000);
  switchView("run");
}

function showAppDetails(app) {
  state.running = app;
  const appNameLink = document.getElementById("run-app-name-link");
  if (appNameLink) appNameLink.textContent = app.name;
  runAppUrl.textContent = app.url;
  runNote.textContent = "Configure your app settings below.";
  runUptime.textContent = "Not running";
  switchView("run");
}

async function handleAppAction(action, name) {
  if (action === "remove") {
    try {
      const confirmed = await invoke("confirm_dialog", {
        title: "Remove App",
        message: `Remove ${name}? This deletes the folder from ~/.stable_apps.`
      });
      if (!confirmed) return;
    } catch (error) {
      showToast(`Confirm error: ${error}`);
      return;
    }
  }

  if (action === "open") {
    const app = state.apps.find((entry) => entry.name === name);
    if (app) {
      showToast(`Opening ${app.url}...`);
      await invoke("open_url", { url: app.url });
    }
    return;
  }

  if (action === "details") {
    const app = state.apps.find((entry) => entry.name === name);
    if (app) {
      showAppDetails(app);
    }
    return;
  }

  const actionMap = {
    start: "start_app",
    stop: "stop_app",
    restart: "restart_app",
    remove: "remove_app",
  };

  const command = actionMap[action];
  if (!command) return;

  setStatus(`${action} in progress...`);
  try {
    await invoke(command, { name });
    showToast(`${name} ${action}ed`);

    if (action === "start") {
      const app = state.apps.find((entry) => entry.name === name);
      if (app) {
        state.running = { name: app.name };
        loadApps();
        showRunView(app);
      }
    } else if (action === "stop") {
      state.running = null;
      loadApps();
      switchView("apps");
      setStatus("Ready");
    } else if (action === "remove") {
      state.running = null;
      loadApps();
      setStatus("Ready");
    } else {
      loadApps();
    }
  } catch (error) {
    setStatus(`${action} failed`, true);
    showToast(`${action} failed: ${String(error)}`);
  }
}

function wireEvents() {
  appsGrid = document.querySelector("#apps-grid");
  runView = document.querySelector("#run-view");
  runAppName = document.querySelector("#run-app-name");
  runAppUrl = document.querySelector("#run-app-url");
  runUptime = document.querySelector("#run-uptime");
  runNote = document.querySelector("#run-note");
  backToApps = document.querySelector("#back-to-apps");
  openRunning = document.querySelector("#open-running");
  openLocal = document.querySelector("#open-local");
  restartRunning = document.querySelector("#restart-running");
  stopRunning = document.querySelector("#stop-running");
  shareRunning = document.querySelector("#share-running");
  doctorOutput = document.querySelector("#doctor-output");
  statusText = document.querySelector(".status-text");
  appsFolder = document.querySelector("#apps-folder");
  addAppSubmit = document.querySelector("#add-app-submit");
  newAppSubmit = document.querySelector("#new-app-submit");
  activityPanel = document.querySelector("#activity-panel");
  activityStatus = document.querySelector("#activity-status");
  activityLog = document.querySelector("#activity-log");

  views.apps = document.querySelector("#apps-view");
  views.doctor = document.querySelector("#doctor-view");
  views.run = runView;

  const navItems = document.querySelectorAll(".nav-item");
  navItems.forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });

  document
    .querySelector("#refresh-apps")
    .addEventListener("click", loadApps);
  document.querySelector("#run-doctor")?.addEventListener("click", runDoctor);
  document.querySelector("#add-app")?.addEventListener("click", () => {
    const input = document.querySelector("#existing-app-path");
    if (input?.value?.trim()) {
      addApp();
    } else {
      input?.focus();
    }
  });
  document.querySelector("#new-app")?.addEventListener("click", () => {
    const input = document.querySelector("#new-app-name");
    if (input?.value?.trim()) {
      newApp();
    } else {
      input?.focus();
    }
  });
  if (addAppSubmit) {
    addAppSubmit.addEventListener("click", addApp);
  }
  if (newAppSubmit) {
    newAppSubmit.addEventListener("click", newApp);
  }

  document.querySelector("#existing-app-path")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      addApp();
    }
  });
  document.querySelector("#new-app-name")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      newApp();
    }
  });

  document.querySelector("#open-folder")?.addEventListener("click", async () => {
    try {
      const folder = await invoke("apps_folder");
      await invoke("open_folder", { path: folder });
    } catch (error) {
      showToast(String(error));
    }
  });

  document.querySelector("#start-all")?.addEventListener("click", async () => {
    const stoppedApps = state.apps.filter(app => state.running?.name !== app.name);
    if (!stoppedApps.length) {
      showToast("No stopped apps to start");
      return;
    }
    setStatus("Starting all apps...");
    for (const app of stoppedApps) {
      try {
        await invoke("start_app", { name: app.name });
      } catch (error) {
        showToast(`Failed to start ${app.name}`);
      }
    }
    showToast("Started all apps");
    loadApps();
  });

  document.querySelector("#stop-all")?.addEventListener("click", async () => {
    if (!state.running) {
      showToast("No running apps");
      return;
    }
    setStatus("Stopping all apps...");
    try {
      await invoke("stop_app", { name: state.running.name });
      showToast("Stopped all apps");
      loadApps();
      switchView("apps");
    } catch (error) {
      setStatus("Stop failed", true);
      showToast(String(error));
    }
  });

  const appNameLink = document.getElementById("run-app-name-link");
  appNameLink?.addEventListener("click", () => {
    if (state.running) {
      showAppDetails(state.running);
    }
  });

  const toggleSettingsBtn = document.getElementById("toggle-settings");
  const settingsPanel = document.getElementById("settings-panel");
  toggleSettingsBtn?.addEventListener("click", () => {
    settingsPanel?.classList.toggle("is-hidden");
    toggleSettingsBtn.textContent = settingsPanel?.classList.contains("is-hidden") ? "Expand" : "Collapse";
  });

  backToApps?.addEventListener("click", () => {
    switchView("apps");
  });

  openRunning?.addEventListener("click", () => {
    if (state.running) {
      openLocalFallback(state.running.url);
    }
  });

  restartRunning?.addEventListener("click", async () => {
    if (!state.running) return;
    await handleAppAction("restart", state.running.name);
  });

  openLocal?.addEventListener("click", async () => {
    await openLocalFallback("http://127.0.0.1:3000");
  });

  stopRunning?.addEventListener("click", async () => {
    if (!state.running) return;
    await handleAppAction("stop", state.running.name);
    switchView("apps");
  });

  shareRunning?.addEventListener("click", async () => {
    if (!state.running) return;
    const url = state.running.url;
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(url);
      showToast("Link copied");
    } else {
      showToast(url);
    }
  });

  if (appsGrid) {
    appsGrid.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-action]");
      if (!button) return;
      handleAppAction(button.dataset.action, button.dataset.app);
    });
  }

  if (appsFolder) {
    appsFolder.textContent = "~/.stable_apps";
  }
}

async function loadAppsFolder() {
  if (!appsFolder) appsFolder = document.querySelector("#apps-folder");
  try {
    const folder = await invoke("apps_folder");
    if (appsFolder) appsFolder.textContent = folder;
  } catch (error) {
    if (appsFolder) appsFolder.textContent = "~/.stable_apps";
  }
}

window.addEventListener("DOMContentLoaded", () => {
  wireEvents();
  loadApps();
  loadAppsFolder();

  setTimeout(() => {
    loadApps();
  }, 600);

  resetActivity();

  listen("stable:progress", (event) => {
    if (activityStatus) {
      activityStatus.textContent = event.payload.message;
    }
    activityPanel?.classList.add("is-busy");
  });

  listen("stable:log", (event) => {
    appendLog(event.payload.line);
    const line = event.payload.line;
    if (line.includes("Stable app ready") || line.includes("Create complete") || line.includes("App domain:")) {
      stopAppCreationChecker();
      if (activityStatus) {
        activityStatus.textContent = "Complete";
      }
      activityPanel?.classList.remove("is-busy");
      loadApps();
      showToast("App created successfully!");
    }
    if (line.includes("ERROR:")) {
      stopAppCreationChecker();
      if (activityStatus) {
        activityStatus.textContent = "Create failed";
      }
      activityPanel?.classList.remove("is-busy");
    }
  });
});
