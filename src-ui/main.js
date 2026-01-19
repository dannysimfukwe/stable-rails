const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

let appsGrid, runView, runAppName, runAppUrl, runUptime, runNote;
let backToApps, openRunning, openLocal, restartRunning, stopRunning, shareRunning;
let doctorOutput, statusText, appsFolder, addAppSubmit, newAppSubmit, addAppBrowse;
let activityPanel, activityStatus, activityLog;
let consoleOutput, consoleInput, tableList, sqlInput, redisResults, logsOutput;
let currentAppTab = "overview";

const views = {};

const state = {
  apps: [],
  busy: false,
  runningApps: [],
  currentApp: null,
  uptimeTimer: null,
  consoleHistory: [],
  consoleHistoryIndex: -1,
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

  const hero = document.querySelector(".hero");
  if (hero) {
    hero.classList.toggle("is-hidden", view === "run");
  }
}

function switchAppTab(tab) {
  currentAppTab = tab;
  document.querySelectorAll(".app-tab").forEach((t) => {
    t.classList.toggle("is-active", t.dataset.tab === tab);
  });
  document.querySelectorAll(".tab-content").forEach((c) => {
    c.classList.toggle("is-active", c.id === `tab-${tab}`);
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
                <span class="status-badge ${state.runningApps.includes(app.name) ? 'running' : ''}">
                  ${state.runningApps.includes(app.name) ? 'Running' : 'Stopped'}
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
  const hasStoppedApps = state.apps.some(app => !state.runningApps.includes(app.name));
  const hasRunningApp = state.runningApps.length > 0;

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
  const addBtn = document.querySelector("#add-app-submit");
  if (!input) return;
  const folder = input.value.trim();
  if (!folder) {
    showToast("Select a folder first");
    return;
  }
  setStatus("Adding app...");
  try {
    await invoke("add_app", { folder });
    input.value = "";
    if (addBtn) {
      addBtn.style.display = "none";
    }
    showToast("App added");
    loadApps();
  } catch (error) {
    setStatus("Add failed", true);
    showToast(String(error));
  }
}

async function browseFolder() {
  try {
    const result = await invoke("pick_folder", { title: "Select Rails App Folder" });
    if (result) {
      const input = document.querySelector("#existing-app-path");
      const addBtn = document.querySelector("#add-app-submit");
      if (input) {
        input.value = result;
      }
      if (addBtn) {
        addBtn.style.display = "inline-flex";
      }
    }
  } catch (error) {
    showToast(`Error selecting folder: ${error}`);
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
  if (!state.runningApps.includes(app.name)) {
    state.runningApps.push(app.name);
  }
  state.currentApp = app;
  
  document.getElementById("run-app-name").textContent = app.name;
  const runAppUrlEl = document.getElementById("run-app-url");
  if (runAppUrlEl) {
    runAppUrlEl.textContent = app.url;
    runAppUrlEl.href = app.url;
  }
  
  const portEl = document.getElementById("run-port");
  if (portEl) portEl.textContent = app.port || 3000;

  const runStatus = document.getElementById("run-status");
  if (runStatus) {
    runStatus.textContent = "Running";
    runStatus.classList.add("running");
  }

  if (state.uptimeTimer) {
    clearInterval(state.uptimeTimer);
  }
  state.uptimeTimer = setInterval(() => {
    const uptimeEl = document.getElementById("run-uptime");
    if (uptimeEl) uptimeEl.textContent = formatUptime(Date.now());
  }, 1000);
  
  switchView("run");
  switchAppTab("overview");
  
  loadAppInfo(app.name);
}

async function loadAppInfo(appName) {
  try {
    const config = await invoke("load_app_config", { name: appName });
    if (config) {
      const rubyEl = document.getElementById("run-ruby-version");
      const railsEl = document.getElementById("run-rails-version");
      if (rubyEl) rubyEl.textContent = config.ruby_version || "-";
      if (railsEl) railsEl.textContent = config.rails_version || "-";
    }
  } catch (e) {
    console.log("Could not load app info:", e);
  }
}

async function loadTables() {
  if (!state.currentApp) return;
  try {
    const tables = await invoke("db_tables", { name: state.currentApp.name });
    const tableListEl = document.getElementById("table-list");
    if (tableListEl) {
      if (tables && tables.length > 0) {
        tableListEl.innerHTML = tables.map(t => `
          <li class="table-item" data-table="${t}">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
              <line x1="3" y1="9" x2="21" y2="9"/>
              <line x1="3" y1="15" x2="21" y2="15"/>
              <line x1="9" y1="3" x2="9" y2="21"/>
              <line x1="15" y1="3" x2="15" y2="21"/>
            </svg>
            ${t}
          </li>
        `).join("");
      } else {
        tableListEl.innerHTML = '<li class="table-item">No tables found</li>';
      }
    }
  } catch (e) {
    const tableListEl = document.getElementById("table-list");
    if (tableListEl) {
      tableListEl.innerHTML = '<li class="table-item">Unable to load tables</li>';
    }
  }
}

async function runSqlQuery() {
  const sql = sqlInput?.value?.trim();
  if (!sql || !state.currentApp) return;
  
  const resultsEl = document.getElementById("query-results");
  if (resultsEl) {
    resultsEl.innerHTML = '<p>Running query...</p>';
  }
  
  try {
    const result = await invoke("db_query", { name: state.currentApp.name, sql });
    if (result && result.rows) {
      if (result.rows.length === 0) {
        if (resultsEl) resultsEl.innerHTML = '<p class="placeholder">No results returned</p>';
        return;
      }
      
      let html = '<table><thead><tr>';
      for (const col of result.columns) {
        html += `<th>${col}</th>`;
      }
      html += '</tr></thead><tbody>';
      
      for (const row of result.rows) {
        html += '<tr>';
        for (const val of row) {
          html += `<td>${val === null ? '<em>NULL</em>' : val}</td>`;
        }
        html += '</tr>';
      }
      html += '</tbody></table>';
      
      if (resultsEl) resultsEl.innerHTML = html;
    } else {
      if (resultsEl) resultsEl.innerHTML = '<p class="placeholder">Query executed successfully (no rows returned)</p>';
    }
  } catch (e) {
    if (resultsEl) resultsEl.innerHTML = `<p style="color: #f87171;">Error: ${e}</p>`;
  }
}

async function scanRedisKeys() {
  const pattern = document.getElementById("redis-key")?.value?.trim() || "*";
  if (!state.currentApp) return;
  
  const resultsEl = document.getElementById("redis-results");
  if (resultsEl) {
    resultsEl.innerHTML = '<p>Scanning...</p>';
  }
  
  try {
    const keys = await invoke("redis_scan", { name: state.currentApp.name, pattern });
    if (keys && keys.length > 0) {
      if (resultsEl) {
        resultsEl.innerHTML = keys.map(k => `
          <div class="redis-key-item" data-key="${k}">${k}</div>
        `).join("");
      }
    } else {
      if (resultsEl) resultsEl.innerHTML = '<p class="placeholder">No keys found</p>';
    }
  } catch (e) {
    if (resultsEl) resultsEl.innerHTML = `<p style="color: #f87171;">Error: ${e}</p>`;
  }
}

function consoleLog(text, type = "output") {
  if (!consoleOutput) return;
  const line = document.createElement("div");
  line.className = `console-line ${type}`;
  line.textContent = text;
  consoleOutput.appendChild(line);
  consoleOutput.scrollTop = consoleOutput.scrollHeight;
}

async function sendConsoleCommand() {
  const cmd = consoleInput?.value?.trim();
  if (!cmd || !state.currentApp) return;
  
  state.consoleHistory.push(cmd);
  state.consoleHistoryIndex = state.consoleHistory.length;
  
  consoleLog(`>> ${cmd}`, "input");
  consoleInput.value = "";
  
  try {
    const result = await invoke("rails_console", { name: state.currentApp.name, command: cmd });
    if (result) {
      consoleLog(result, "output");
    }
  } catch (e) {
    consoleLog(`Error: ${e}`, "error");
  }
}

function handleConsoleKeydown(e) {
  if (e.key === "Enter") {
    sendConsoleCommand();
  } else if (e.key === "ArrowUp") {
    if (state.consoleHistoryIndex > 0) {
      state.consoleHistoryIndex--;
      consoleInput.value = state.consoleHistory[state.consoleHistoryIndex];
    }
    e.preventDefault();
  } else if (e.key === "ArrowDown") {
    if (state.consoleHistoryIndex < state.consoleHistory.length - 1) {
      state.consoleHistoryIndex++;
      consoleInput.value = state.consoleHistory[state.consoleHistoryIndex];
    } else {
      state.consoleHistoryIndex = state.consoleHistory.length;
      consoleInput.value = "";
    }
    e.preventDefault();
  }
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
      state.currentApp = app;
      
      document.getElementById("run-app-name").textContent = app.name;
      const runAppUrlEl = document.getElementById("run-app-url");
      if (runAppUrlEl) {
        runAppUrlEl.textContent = app.url;
        runAppUrlEl.href = app.url;
      }
      
      const portEl = document.getElementById("run-port");
      if (portEl) portEl.textContent = app.port || 3000;

      const isRunning = state.runningApps.includes(app.name);
      const runStatus = document.getElementById("run-status");
      if (runStatus) {
        runStatus.textContent = isRunning ? "Running" : "Stopped";
        runStatus.classList.toggle("running", isRunning);
      }

      if (isRunning) {
        if (state.uptimeTimer) {
          clearInterval(state.uptimeTimer);
        }
        state.uptimeTimer = setInterval(() => {
          const uptimeEl = document.getElementById("run-uptime");
          if (uptimeEl) uptimeEl.textContent = formatUptime(Date.now());
        }, 1000);
      } else {
        const uptimeEl = document.getElementById("run-uptime");
        if (uptimeEl) uptimeEl.textContent = "Not running";
        if (state.uptimeTimer) {
          clearInterval(state.uptimeTimer);
          state.uptimeTimer = null;
        }
      }
      
      switchView("run");
      switchAppTab("overview");
      
      loadAppInfo(app.name);
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
        if (!state.runningApps.includes(app.name)) {
          state.runningApps.push(app.name);
        }
        loadApps();
        showRunView(app);
      }
    } else if (action === "stop") {
      state.runningApps = state.runningApps.filter(n => n !== name);
      loadApps();
      if (state.currentApp && state.currentApp.name === name) {
        const runStatus = document.getElementById("run-status");
        if (runStatus) {
          runStatus.textContent = "Stopped";
          runStatus.classList.remove("running");
        }
      }
      if (state.runningApps.length > 0 && state.currentApp && state.currentApp.name === name) {
        switchView("apps");
      } else if (state.runningApps.length === 0 || !state.runningApps.includes(state.currentApp?.name)) {
        switchView("apps");
      }
      setStatus("Ready");
    } else if (action === "restart") {
      loadApps();
    } else if (action === "remove") {
      state.runningApps = state.runningApps.filter(n => n !== name);
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
  addAppBrowse = document.querySelector("#add-app-browse");
  activityPanel = document.querySelector("#activity-panel");
  activityStatus = document.querySelector("#activity-status");
  activityLog = document.querySelector("#activity-log");
  consoleOutput = document.getElementById("console-output");
  consoleInput = document.getElementById("console-input");
  tableList = document.getElementById("table-list");
  sqlInput = document.getElementById("sql-input");
  redisResults = document.getElementById("redis-results");
  logsOutput = document.getElementById("logs-output");

  views.apps = document.querySelector("#apps-view");
  views.doctor = document.querySelector("#doctor-view");
  views.run = runView;

  const navItems = document.querySelectorAll(".nav-item");
  navItems.forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });

  document.querySelectorAll(".app-tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      switchAppTab(tab.dataset.tab);
      if (tab.dataset.tab === "database") {
        loadTables();
      }
    });
  });

  document.querySelector("#refresh-apps").addEventListener("click", loadApps);
  document.querySelector("#run-doctor")?.addEventListener("click", runDoctor);
  document.querySelector("#add-app")?.addEventListener("click", () => {
    browseFolder();
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
  if (addAppBrowse) {
    addAppBrowse.addEventListener("click", browseFolder);
  }
  if (newAppSubmit) {
    newAppSubmit.addEventListener("click", newApp);
  }

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
    const stoppedApps = state.apps.filter(app => !state.runningApps.includes(app.name));
    if (!stoppedApps.length) {
      showToast("No stopped apps to start");
      return;
    }
    setStatus("Starting all apps...");
    for (const app of stoppedApps) {
      try {
        await invoke("start_app", { name: app.name });
        if (!state.runningApps.includes(app.name)) {
          state.runningApps.push(app.name);
        }
      } catch (error) {
        showToast(`Failed to start ${app.name}`);
      }
    }
    showToast("Started all apps");
    loadApps();
  });

  document.querySelector("#stop-all")?.addEventListener("click", async () => {
    if (!state.runningApps.length) {
      showToast("No running apps");
      return;
    }
    setStatus("Stopping all apps...");
    for (const name of state.runningApps) {
      try {
        await invoke("stop_app", { name });
      } catch (error) {
        showToast(`Failed to stop ${name}`);
      }
    }
    state.runningApps = [];
    showToast("Stopped all apps");
    loadApps();
    switchView("apps");
  });

  backToApps?.addEventListener("click", () => {
    switchView("apps");
  });

  openRunning?.addEventListener("click", () => {
    if (state.currentApp) {
      invoke("open_url", { url: state.currentApp.url });
    }
  });

  restartRunning?.addEventListener("click", async () => {
    if (state.currentApp) {
      await handleAppAction("restart", state.currentApp.name);
    }
  });

  openLocal?.addEventListener("click", async () => {
    if (state.currentApp) {
      invoke("open_url", { url: `http://127.0.0.1:${state.currentApp.port || 3000}` });
    }
  });

  stopRunning?.addEventListener("click", async () => {
    if (state.currentApp) {
      await handleAppAction("stop", state.currentApp.name);
      switchView("apps");
    }
  });

  shareRunning?.addEventListener("click", async () => {
    if (state.currentApp && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(state.currentApp.url);
      showToast("Link copied");
    }
  });

  if (consoleInput) {
    consoleInput.addEventListener("keydown", handleConsoleKeydown);
  }

  document.getElementById("clear-console")?.addEventListener("click", () => {
    if (consoleOutput) {
      consoleOutput.innerHTML = '<div class="console-line prompt">irb(main):001:0> </div>';
    }
  });

  document.getElementById("refresh-tables")?.addEventListener("click", loadTables);

  document.getElementById("new-query")?.addEventListener("click", () => {
    const queryArea = document.getElementById("query-area");
    if (queryArea) queryArea.style.display = "block";
  });

  document.getElementById("cancel-query")?.addEventListener("click", () => {
    const queryArea = document.getElementById("query-area");
    if (queryArea) queryArea.style.display = "none";
  });

  document.getElementById("run-query")?.addEventListener("click", runSqlQuery);

  document.getElementById("redis-scan")?.addEventListener("click", scanRedisKeys);

  document.getElementById("clear-logs")?.addEventListener("click", () => {
    if (logsOutput) logsOutput.textContent = "No logs yet.";
  });

  document.getElementById("save-settings")?.addEventListener("click", async () => {
    if (!state.currentApp) return;
    const env = document.getElementById("setting-rails-env")?.value;
    const tls = document.getElementById("setting-tls")?.checked;
    const caddy = document.getElementById("setting-caddy")?.checked;
    
    try {
      await invoke("save_app_settings", {
        name: state.currentApp.name,
        railsEnv: env,
        port: state.currentApp.port || 3000,
        customDomain: "",
        tlsEnabled: tls,
        caddyEnabled: caddy
      });
      showToast("Settings saved");
    } catch (e) {
      showToast(`Error saving settings: ${e}`);
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
