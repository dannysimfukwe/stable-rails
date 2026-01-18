const { invoke } = window.__TAURI__.core;
const { open } = window.__TAURI__.opener;
const { listen } = window.__TAURI__.event;

const appsGrid = document.querySelector("#apps-grid");
const runView = document.querySelector("#run-view");
const runAppName = document.querySelector("#run-app-name");
const runAppUrl = document.querySelector("#run-app-url");
const runUptime = document.querySelector("#run-uptime");
const runNote = document.querySelector("#run-note");
const backToApps = document.querySelector("#back-to-apps");
const openRunning = document.querySelector("#open-running");
const openLocal = document.querySelector("#open-local");
const restartRunning = document.querySelector("#restart-running");
const stopRunning = document.querySelector("#stop-running");
const shareRunning = document.querySelector("#share-running");
const doctorOutput = document.querySelector("#doctor-output");
const statusText = document.querySelector(".status-text");
const appsFolder = document.querySelector("#apps-folder");
const addAppSubmit = document.querySelector("#add-app-submit");
const newAppSubmit = document.querySelector("#new-app-submit");
const activityPanel = document.querySelector("#activity-panel");
const activityStatus = document.querySelector("#activity-status");
const activityLog = document.querySelector("#activity-log");

const views = {
  apps: document.querySelector("#apps-view"),
  doctor: document.querySelector("#doctor-view"),
  run: runView,
};

const navButtons = document.querySelectorAll(".nav-item");

const state = {
  apps: [],
  busy: false,
  running: null,
  uptimeTimer: null,
};

function setStatus(message, isError = false) {
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
  if (!activityPanel) return;
  activityStatus.textContent = message;
  activityPanel.classList.remove("is-busy");
}

function appendLog(line) {
  if (!activityPanel) return;
  if (activityLog.textContent === "Logs will appear here.") {
    activityLog.textContent = "";
  }
  activityLog.textContent += `${line}\n`;
  activityLog.scrollTop = activityLog.scrollHeight;
}

function switchView(view) {
  Object.keys(views).forEach((key) => {
    views[key].classList.toggle("is-hidden", key !== view);
  });

  navButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.view === view);
  });
}

function renderApps(apps) {
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
                <span class="app-name">${app.name}</span>
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

async function loadApps() {
  setStatus("Syncing apps...");
  try {
    const apps = await invoke("list_apps");
    state.apps = apps;
    renderApps(apps);
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
  try {
    await invoke("create_app", { name });
    input.value = "";
    showToast("Rails app created");
    loadApps();
    appendLog("Create complete.");
    if (activityPanel) {
      activityStatus.textContent = "Complete";
      activityPanel.classList.remove("is-busy");
    }
  } catch (error) {
    setStatus("Create failed", true);
    if (activityPanel) {
      activityStatus.textContent = "Create failed";
      activityPanel.classList.remove("is-busy");
    }
    appendLog(`ERROR: ${error}`);
    showToast(String(error));
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
  runAppName.textContent = app.name;
  runAppUrl.textContent = app.url;
  runNote.textContent = "Caddy serves https with local TLS.";
  runUptime.textContent = formatUptime(state.running.startedAt);
  if (state.uptimeTimer) {
    clearInterval(state.uptimeTimer);
  }
  state.uptimeTimer = setInterval(() => {
    runUptime.textContent = formatUptime(state.running.startedAt);
  }, 1000);
  switchView("run");
}

async function openUrl(url) {
  try {
    await open(url);
  } catch (error) {
    try {
      window.open(url, "_blank");
    } catch (fallbackError) {
      showToast(`Unable to open ${url}`);
    }
  }
}

async function openLocalFallback(url) {
  await openUrl(url);
  if (url.startsWith("https://")) {
    await openUrl("http://127.0.0.1:3000");
  }
}

async function handleAppAction(action, name) {
  const actionMap = {
    start: "start_app",
    stop: "stop_app",
    restart: "restart_app",
    remove: "remove_app",
  };

  if (action === "remove") {
    const confirmDelete = window.confirm(
      `Remove ${name}? This deletes the folder from ${appsFolder.textContent || "~/.stable_apps"}.`
    );
    if (!confirmDelete) return;
  }

  if (action === "open") {
    const app = state.apps.find((entry) => entry.name === name);
    if (app) {
      await openLocalFallback(app.url);
    }
    return;
  }

  const command = actionMap[action];
  if (!command) return;

  setStatus(`${action} in progress...`);
  try {
    await invoke(command, { name });
    showToast(`${name} ${action}ed`);
      if (action === "start") {
      const app = state.apps.find((entry) => entry.name === name);
      if (app) {
        showRunView(app);
      }
    }
    if (action !== "stop") {
      loadApps();
    } else {
      setStatus("Ready");
    }
  } catch (error) {
    setStatus(`${action} failed`, true);
    showToast(String(error));
  }
}

function wireEvents() {
  navButtons.forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });

  document
    .querySelector("#refresh-apps")
    .addEventListener("click", loadApps);
  document.querySelector("#run-doctor").addEventListener("click", runDoctor);
  document.querySelector("#add-app").addEventListener("click", () => {
    const input = document.querySelector("#existing-app-path");
    if (input?.value?.trim()) {
      addApp();
    } else {
      input?.focus();
    }
  });
  document.querySelector("#new-app").addEventListener("click", () => {
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
  document
    .querySelector("#open-folder")
    .addEventListener("click", async () => {
      try {
        const folder = await invoke("apps_folder");
        await openUrl(folder);
      } catch (error) {
        showToast(String(error));
      }
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

  appsFolder.textContent = "~/.stable_apps";
}

async function loadAppsFolder() {
  try {
    const folder = await invoke("apps_folder");
    appsFolder.textContent = folder;
  } catch (error) {
    appsFolder.textContent = "~/.stable_apps";
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
  });
});
