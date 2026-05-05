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
  currentTable: null,
  currentColumns: [],
  uptimeTimer: null,
  consoleHistory: [],
  consoleHistoryIndex: -1,
  consoleMode: "command", // "command" or "console"
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
  console.log("switchView called with:", view);
  if (!views.apps) {
    views.apps = document.querySelector("#apps-view");
    views.dependencies = document.querySelector("#dependencies-view");
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

  if (view === "dependencies") {
    console.log("Loading dependencies...");
    loadDependencies();
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
  if (tab === "env" && state.currentApp) {
    loadEnvFile();
  }
  if (tab === "deploy" && state.currentApp) {
    loadDeployConfig();
  }
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

async function loadAppsWithRunningState() {
  setStatus("Syncing apps...");
  try {
    const apps = await invoke("list_apps");
    state.apps = apps;
    
    // Update runningApps based on actual server state
    state.runningApps = apps.filter(app => app.status === 'running').map(app => app.name);
    
    renderApps(apps);
    updateButtonStates();
    setStatus("Ready");
  } catch (error) {
    setStatus("Error loading apps", true);
    showToast(String(error));
  }
}

async function loadDependencies() {
  try {
    const status = await invoke("dependencies_status");
    console.log("Status:", JSON.stringify(status));

    function updateStatus(statusId, dep) {
      const statusEl = document.getElementById(statusId);
      if (!statusEl) return;

      if (dep.installed) {
        statusEl.textContent = dep.version || "Installed";
        statusEl.style.color = "#22c55e";
      } else {
        statusEl.textContent = dep.message || "Not installed";
        statusEl.style.color = "#ef4444";
      }
    }

    updateStatus("deps-homebrew-status", status.homebrew);
    updateStatus("deps-caddy-status", status.caddy);
    updateStatus("deps-mkcert-status", status.mkcert);
    updateStatus("deps-ruby-status", status.ruby);

  } catch (error) {
    console.error("Error:", error);
    const ids = ["deps-homebrew-status", "deps-caddy-status", "deps-mkcert-status", "deps-ruby-status"];
    ids.forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        el.textContent = "Error loading";
        el.style.color = "#ef4444";
      }
    });
  }
}

async function installDependency(dep) {
  const statusEl = document.getElementById(`${dep}-status`);
  const actionBtn = document.getElementById(`install-${dep}`);
  if (statusEl) {
    statusEl.textContent = "Installing...";
    statusEl.className = "dep-status installing";
  }
  if (actionBtn) actionBtn.disabled = true;

  try {
    const result = await invoke("install_dependency", { dep });
    showToast(result);
    await loadDependencies();
  } catch (error) {
    showToast("Failed to install " + dep + ": " + error);
    await loadDependencies();
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

function openAddExistingModal() {
  const modal = document.getElementById("add-existing-modal");
  if (!modal) return;
  document.getElementById("modal-app-name").value = "";
  document.getElementById("modal-app-path").value = "";
  modal.style.display = "flex";
  document.getElementById("modal-app-name")?.focus();
}

function closeAddExistingModal() {
  const modal = document.getElementById("add-existing-modal");
  if (modal) modal.style.display = "none";
}

async function modalBrowseFolder() {
  try {
    const result = await invoke("pick_folder", { title: "Select Rails App Folder" });
    if (result) {
      const input = document.getElementById("modal-app-path");
      if (input) input.value = result;
    }
  } catch (error) {
    showToast(`Error selecting folder: ${error}`);
  }
}

async function modalAddApp() {
  const nameInput = document.getElementById("modal-app-name");
  const pathInput = document.getElementById("modal-app-path");
  if (!nameInput || !pathInput) return;

  const name = nameInput.value.trim();
  const folder = pathInput.value.trim();

  if (!name) {
    showToast("Enter an app name first");
    return;
  }
  if (!folder) {
    showToast("Select a folder first");
    return;
  }

  closeAddExistingModal();
  setStatus("Adding app...");
  try {
    await invoke("add_app", { folder });
    showToast("App added");
    loadAppsWithRunningState();
  } catch (error) {
    setStatus("Add failed", true);
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
    loadAppsWithRunningState();
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

async function loadNewAppRubyVersions() {
  const select = document.getElementById("new-app-ruby");
  if (!select) return;
  try {
    const versions = await invoke("list_ruby_versions");
    // Keep the "System default" option
    select.innerHTML = '<option value="">System default</option>';
    versions.forEach((v) => {
      const opt = document.createElement("option");
      opt.value = v;
      opt.textContent = `Ruby ${v}`;
      select.appendChild(opt);
    });
  } catch (e) {
    console.error("Failed to load Ruby versions:", e);
  }
}

function openNewAppModal() {
  const modal = document.getElementById("new-app-modal");
  if (!modal) return;
  modal.style.display = "flex";
  document.getElementById("new-app-name").value = "";
  document.getElementById("new-app-name").focus();
  loadNewAppRubyVersions();
}

function closeNewAppModal() {
  const modal = document.getElementById("new-app-modal");
  if (modal) modal.style.display = "none";
}

async function newApp() {
  const nameInput = document.getElementById("new-app-name");
  if (!nameInput) return;
  const name = nameInput.value.trim();
  if (!name) {
    showToast("Enter an app name first");
    return;
  }

  const options = {
    ruby_version: document.getElementById("new-app-ruby")?.value || null,
    api_only: document.getElementById("new-app-api")?.checked || false,
    database: document.getElementById("new-app-database")?.value || "sqlite3",
    install_devise: document.getElementById("new-app-devise")?.checked || false,
    install_rspec: document.getElementById("new-app-rspec")?.checked || false,
    install_factory_bot: document.getElementById("new-app-factory-bot")?.checked || false,
    install_sidekiq: document.getElementById("new-app-sidekiq")?.checked || false,
    install_dotenv: document.getElementById("new-app-dotenv")?.checked || false,
  };

  closeNewAppModal();
  setStatus("Creating app...");
  if (activityPanel) {
    activityStatus.textContent = "Creating app...";
    activityLog.textContent = "";
    activityPanel.classList.add("is-busy");
  }
  appendLog("Initializing create...");
  startAppCreationChecker();
  try {
    await invoke("create_app", { name, options });
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
    loadAppsWithRunningState();
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

function clearDeployForm() {
  const fields = [
    "deploy-server",
    "deploy-ssh-user",
    "deploy-app-name",
    "deploy-registry-username",
    "deploy-registry-password",
    "deploy-domain",
    "deploy-master-key",
  ];
  fields.forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.value = "";
  });
  const registrySelect = document.getElementById("deploy-registry");
  if (registrySelect) registrySelect.value = "Docker Hub";
}

function resetAppTabs() {
  // Reset deploy tab — clear output, hide panels, wipe form fields
  const deployOutput = document.getElementById("deploy-output");
  if (deployOutput) deployOutput.textContent = "";

  const deployForm = document.getElementById("deploy-config-form");
  const deployConfigured = document.getElementById("deploy-configured");
  if (deployForm) deployForm.style.display = "none";
  if (deployConfigured) deployConfigured.style.display = "none";
  clearDeployForm();

  // Reset console
  const consoleOutputEl = document.getElementById("console-output");
  if (consoleOutputEl) {
    consoleOutputEl.innerHTML = '<div class="console-line prompt">irb(main):001:0&gt; </div>';
  }
  state.consoleMode = "command";
  state.consoleHistory = [];
  state.consoleHistoryIndex = -1;

  // Reset database
  const tableListEl = document.getElementById("table-list");
  if (tableListEl) tableListEl.innerHTML = '<li class="table-item">Loading tables...</li>';
  state.currentTable = null;
  state.currentColumns = [];

  // Reset logs
  const logsOutputEl = document.getElementById("logs-output");
  if (logsOutputEl) logsOutputEl.textContent = "No logs yet. Start the app to see logs here.";

  // Reset redis
  const redisResultsEl = document.getElementById("redis-results");
  if (redisResultsEl) redisResultsEl.innerHTML = '<p class="placeholder">Enter a key pattern to search Redis keys</p>';

  // Reset env
  const envTbody = document.getElementById("env-tbody");
  if (envTbody) envTbody.innerHTML = '<tr><td colspan="3" class="placeholder">Loading .env file...</td></tr>';
}

function showRunView(app) {
  if (!state.runningApps.includes(app.name)) {
    state.runningApps.push(app.name);
  }
  state.currentApp = app;
  resetAppTabs();
  
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
      if (rubyEl) rubyEl.textContent = config.ruby_version || config.ruby || "-";
      if (railsEl) railsEl.textContent = config.rails_version || "-";

      // Check if app is actually running
      const apps = await invoke("list_apps");
      const appInfo = apps.find((a) => a.name === appName);
      const isRunning = appInfo && appInfo.status === 'running';

      const runStatus = document.getElementById("run-status");
      if (runStatus) {
        runStatus.textContent = isRunning ? "Running" : "Stopped";
        runStatus.classList.toggle("running", isRunning);
      }

      if (config.started_at && isRunning) {
        const startTime = config.started_at * 1000;
        const uptimeEl = document.getElementById("run-uptime");
        if (uptimeEl) uptimeEl.textContent = formatUptime(startTime);
        
        if (state.uptimeTimer) {
          clearInterval(state.uptimeTimer);
        }
        state.uptimeTimer = setInterval(() => {
          const uptimeEl = document.getElementById("run-uptime");
          if (uptimeEl) uptimeEl.textContent = formatUptime(startTime);
        }, 1000);
      } else if (!isRunning) {
        const uptimeEl = document.getElementById("run-uptime");
        if (uptimeEl) uptimeEl.textContent = "Not running";
        if (state.uptimeTimer) {
          clearInterval(state.uptimeTimer);
          state.uptimeTimer = null;
        }
      }
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

        tableListEl.querySelectorAll('.table-item').forEach(item => {
          item.addEventListener('click', () => {
            const tableName = item.dataset.table;
            if (tableName) {
              const queryArea = document.getElementById('query-area');
              const sqlInput = document.getElementById('sql-input');
              const queryResults = document.getElementById('query-results');
              if (queryArea) queryArea.style.display = 'none';
              if (sqlInput) sqlInput.value = `SELECT * FROM ${tableName} LIMIT 100;`;
              if (queryResults) {
                queryResults.innerHTML = '<p>Loading...</p>';
                runTableQuery(tableName);
              }
            }
          });
        });
      } else {
        tableListEl.innerHTML = '<li class="table-item">No tables found</li>';
      }
    }
  } catch (e) {
    const tableListEl = document.getElementById("table-list");
    if (tableListEl) {
      tableListEl.innerHTML = `<li class="table-item" style="color: #f87171;">Error: ${e}</li>`;
    }
  }
}

async function runTableQuery(tableName) {
  if (!state.currentApp) return;
  state.currentTable = tableName;
  const resultsEl = document.getElementById("query-results");
  if (!resultsEl) return;

  resultsEl.innerHTML = `<p style="color: #94a3b8;">Running query: SELECT * FROM ${tableName} LIMIT 100...</p>`;

  try {
    const result = await invoke("db_query", { name: state.currentApp.name, sql: `SELECT * FROM ${tableName} LIMIT 100` });
    console.log('db_query result:', JSON.stringify(result));

    state.currentColumns = result.columns || [];
    if (result && result.rows && result.rows.length > 0) {
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
      resultsEl.innerHTML = html;
    } else {
      resultsEl.innerHTML = `<p class="placeholder">No data in "${tableName}" (table is empty)</p>`;
    }
  } catch (e) {
    console.log('db_query error:', e);
    resultsEl.innerHTML = `<p style="color: #f87171; white-space: pre-wrap; font-size: 12px;">Error: ${e}</p>`;
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

async function loadEnvFile() {
  if (!state.currentApp) return;
  const tbody = document.getElementById("env-tbody");
  if (!tbody) return;
  
  tbody.innerHTML = '<tr><td colspan="3" class="placeholder">Loading .env file...</td></tr>';
  
  try {
    const vars = await invoke("get_env_file", { name: state.currentApp.name });
    if (vars.length === 0) {
      tbody.innerHTML = '<tr><td colspan="3" class="placeholder">No .env file found</td></tr>';
      return;
    }
    
    tbody.innerHTML = vars.map(([key, value], index) => `
      <tr data-index="${index}">
        <td><input type="text" value="${key}" class="env-key" data-index="${index}"></td>
        <td><input type="text" value="${value}" class="env-value" data-index="${index}"></td>
        <td><button class="ghost" onclick="deleteEnvVar(${index})">Delete</button></td>
      </tr>
    `).join("");
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="3" class="placeholder" style="color:#ef4444;">Error: ${e}</td></tr>`;
  }
}

async function saveEnvFile() {
  if (!state.currentApp) return;
  const tbody = document.getElementById("env-tbody");
  if (!tbody) return;
  
  const rows = tbody.querySelectorAll("tr[data-index]");
  const vars = [];
  rows.forEach(row => {
    const keyInput = row.querySelector(".env-key");
    const valueInput = row.querySelector(".env-value");
    if (keyInput && valueInput && keyInput.value.trim()) {
      vars.push([keyInput.value.trim(), valueInput.value.trim()]);
    }
  });
  
  try {
    await invoke("save_env_file", { name: state.currentApp.name, vars });
    showToast(".env saved — restarting app...");
    // Restart the app to pick up new env vars
    await invoke("restart_app", { name: state.currentApp.name });
    showToast("App restarted with new environment variables");
  } catch (e) {
    showToast("Error saving .env: " + e);
  }
}

function deleteEnvVar(index) {
  const tbody = document.getElementById("env-tbody");
  if (!tbody) return;
  const row = tbody.querySelector(`tr[data-index="${index}"]`);
  if (row) row.remove();
}

async function addEnvVar() {
  const tbody = document.getElementById("env-tbody");
  if (!tbody) return;
  
  const existingRows = tbody.querySelectorAll("tr[data-index]");
  const newIndex = existingRows.length;
  
  const newRow = document.createElement("tr");
  newRow.setAttribute("data-index", newIndex);
  newRow.innerHTML = `
    <td><input type="text" value="" class="env-key" data-index="${newIndex}" placeholder="KEY"></td>
    <td><input type="text" value="" class="env-value" data-index="${newIndex}" placeholder="value"></td>
    <td><button class="ghost" onclick="deleteEnvVar(${newIndex})">Delete</button></td>
  `;
  tbody.appendChild(newRow);
}

async function loadDeployConfig() {
  if (!state.currentApp) return;
  const formEl = document.getElementById("deploy-config-form");
  const configuredEl = document.getElementById("deploy-configured");
  const summaryEl = document.getElementById("deploy-config-summary");
  const outputEl = document.getElementById("deploy-output");

  // Reset output and always clear form fields first (prevent stale data from prev app)
  if (outputEl) outputEl.textContent = "";
  clearDeployForm();

  try {
    const result = await invoke("get_deploy_config", { name: state.currentApp.name });

    if (result.configured && result.config) {
      // Show configured state
      if (formEl) formEl.style.display = "none";
      if (configuredEl) configuredEl.style.display = "block";

      const cfg = result.config;
      let html = '<div class="config-summary-grid">';
      html += `<div><span class="config-label">Server</span><span class="config-value">${cfg.ssh_user}@${cfg.server}</span></div>`;
      html += `<div><span class="config-label">Registry</span><span class="config-value">${cfg.registry}</span></div>`;
      html += `<div><span class="config-label">Image</span><span class="config-value">${cfg.registry_username}/${cfg.app_name}</span></div>`;
      if (cfg.domain) {
        html += `<div><span class="config-label">Domain</span><span class="config-value">${cfg.domain}</span></div>`;
      }
      html += '</div>';
      if (summaryEl) summaryEl.innerHTML = html;
    } else {
      // Show empty form state with defaults for this app
      if (formEl) formEl.style.display = "block";
      if (configuredEl) configuredEl.style.display = "none";

      const appNameInput = document.getElementById("deploy-app-name");
      if (appNameInput) appNameInput.value = state.currentApp.name;
      const sshUserInput = document.getElementById("deploy-ssh-user");
      if (sshUserInput) sshUserInput.value = "root";
    }
  } catch (e) {
    console.error("Failed to load deploy config:", e);
    // Show empty form as fallback
    if (formEl) formEl.style.display = "block";
    if (configuredEl) configuredEl.style.display = "none";

    const appNameInput = document.getElementById("deploy-app-name");
    if (appNameInput) appNameInput.value = state.currentApp.name;
    const sshUserInput = document.getElementById("deploy-ssh-user");
    if (sshUserInput) sshUserInput.value = "root";
  }
}

async function saveDeployConfig() {
  if (!state.currentApp) return;

  const server = document.getElementById("deploy-server")?.value?.trim();
  const sshUser = document.getElementById("deploy-ssh-user")?.value?.trim() || "root";
  const registry = document.getElementById("deploy-registry")?.value || "Docker Hub";
  const appName = document.getElementById("deploy-app-name")?.value?.trim();
  const registryUsername = document.getElementById("deploy-registry-username")?.value?.trim();
  const registryPassword = document.getElementById("deploy-registry-password")?.value?.trim();
  const domain = document.getElementById("deploy-domain")?.value?.trim() || null;
  const masterKey = document.getElementById("deploy-master-key")?.value?.trim();

  if (!server) {
    showToast("Server IP or hostname is required");
    return;
  }
  if (!registryUsername) {
    showToast("Registry username is required");
    return;
  }
  if (!registryPassword) {
    showToast("Registry password is required");
    return;
  }
  if (!masterKey) {
    showToast("Rails Master Key is required");
    return;
  }

  const config = {
    server,
    ssh_user: sshUser,
    registry,
    app_name: appName || state.currentApp.name,
    registry_username: registryUsername,
    registry_password: registryPassword,
    domain: domain || null,
    rails_master_key: masterKey,
  };

  try {
    await invoke("save_deploy_config", { name: state.currentApp.name, config });
    showToast("Deploy configuration saved");
    loadDeployConfig();
  } catch (e) {
    showToast(`Error: ${e}`);
  }
}

async function runKamalCommand(cmd) {
  if (!state.currentApp) return;
  const outputEl = document.getElementById("deploy-output");
  if (outputEl) {
    outputEl.textContent = `Running: kamal ${cmd}\n\n`;
  }
  
  try {
    const result = await invoke("kamal_command", { name: state.currentApp.name, cmd });
    if (outputEl) {
      outputEl.textContent += result;
    }
  } catch (e) {
    if (outputEl) {
      outputEl.textContent += `Error: ${e}`;
    }
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

  const trimmed = cmd.trim().toLowerCase();
  
  // Detect if entering or leaving console mode
  if (trimmed === "c" || trimmed === "console" || trimmed.startsWith("rails c") || trimmed.startsWith("rails console")) {
    state.consoleMode = "console";
  } else if (trimmed === "exit") {
    state.consoleMode = "command";
  }

  const invokeCmd = state.consoleMode === "console" ? "rails_console" : "rails_command";

  state.consoleHistory.push(cmd);
  state.consoleHistoryIndex = state.consoleHistory.length;

  consoleLog(`>> ${cmd}`, "input");
  consoleInput.value = "";

  try {
    const result = await invoke(invokeCmd, { name: state.currentApp.name, command: cmd });
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
        message: `Remove ${name}? This deletes the folder from ~/StableCaddy/projects.`
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
      resetAppTabs();
      
      document.getElementById("run-app-name").textContent = app.name;
      const runAppUrlEl = document.getElementById("run-app-url");
      if (runAppUrlEl) {
        runAppUrlEl.textContent = app.url;
        runAppUrlEl.href = app.url;
      }
      
      const portEl = document.getElementById("run-port");
      if (portEl) portEl.textContent = app.port || 3000;

      // Refresh running state from server
      const apps = await invoke("list_apps");
      const updatedApp = apps.find((a) => a.name === name);
      const isRunning = updatedApp ? updatedApp.status === 'running' : false;

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
    await loadAppsWithRunningState();
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
  views.dependencies = document.querySelector("#dependencies-view");
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
      } else if (tab.dataset.tab === "logs") {
        loadAppLogs();
      }
    });
  });

  document.querySelector("#refresh-apps").addEventListener("click", loadApps);
  document.querySelector("#run-doctor")?.addEventListener("click", runDoctor);

  document.querySelector("#refresh-deps")?.addEventListener("click", loadDependencies);
  document.querySelector("#install-caddy")?.addEventListener("click", () => installDependency("caddy"));
  document.querySelector("#install-mkcert")?.addEventListener("click", () => installDependency("mkcert"));
  document.querySelector("#check-ruby")?.addEventListener("click", loadDependencies);
  document.querySelector("#add-app")?.addEventListener("click", openAddExistingModal);
  document.querySelector("#new-app")?.addEventListener("click", openNewAppModal);
  document.querySelector("#new-app-modal-close")?.addEventListener("click", closeNewAppModal);
  document.querySelector("#new-app-cancel")?.addEventListener("click", closeNewAppModal);
  document.querySelector("#new-app-submit")?.addEventListener("click", newApp);

  document.getElementById("new-app-name")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      newApp();
    }
  });

  // Close modal on overlay click
  document.getElementById("new-app-modal")?.addEventListener("click", (e) => {
    if (e.target.id === "new-app-modal") {
      closeNewAppModal();
    }
  });

  // Add Existing App Modal
  document.getElementById("modal-close")?.addEventListener("click", closeAddExistingModal);
  document.getElementById("modal-cancel")?.addEventListener("click", closeAddExistingModal);
  document.getElementById("modal-browse")?.addEventListener("click", modalBrowseFolder);
  document.getElementById("modal-add-app")?.addEventListener("click", modalAddApp);
  document.getElementById("add-existing-modal")?.addEventListener("click", (e) => {
    if (e.target.id === "add-existing-modal") {
      closeAddExistingModal();
    }
  });

  if (addAppSubmit) {
    addAppSubmit.addEventListener("click", addApp);
  }
  if (addAppBrowse) {
    addAppBrowse.addEventListener("click", browseFolder);
  }

  document.querySelector("#open-folder")?.addEventListener("click", async () => {
    try {
      const folder = await invoke("apps_folder");
      await invoke("open_folder", { path: folder });
    } catch (error) {
      showToast(String(error));
    }
  });

  document.querySelector("#start-all")?.addEventListener("click", async () => {
    setStatus("Starting all apps...");
    try {
      await invoke("start_all_apps");
      showToast("Starting all apps (10s boot time)...");
    } catch (error) {
      showToast(`Failed: ${error}`);
    }
    // Poll for status during the 10s boot
    let checks = 0;
    const checkInterval = setInterval(async () => {
      checks++;
      setStatus(`Waiting for apps to boot... (${checks * 2}s)`);
      await loadAppsWithRunningState();
      // Stop checking after 10 seconds (5 checks of 2s)
      if (checks >= 5) {
        clearInterval(checkInterval);
        setStatus("Ready");
      }
    }, 2000);
  });

  document.querySelector("#stop-all")?.addEventListener("click", async () => {
    setStatus("Stopping all apps...");
    try {
      await invoke("stop_all_apps");
      showToast("Stopping all apps...");
    } catch (error) {
      showToast(`Failed: ${error}`);
    }
    // Don't wait - the command runs in background
    setTimeout(loadAppsWithRunningState, 1000);
  });

  document.querySelector("#stop-all")?.addEventListener("click", async () => {
    setStatus("Stopping all apps...");
    try {
      await invoke("stop_all_apps");
      showToast("Stopped all apps");
    } catch (error) {
      showToast(`Failed: ${error}`);
    }
    await loadAppsWithRunningState();
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

  document.getElementById("add-env-var")?.addEventListener("click", addEnvVar);
  document.getElementById("save-env")?.addEventListener("click", saveEnvFile);

  document.getElementById("save-deploy-config")?.addEventListener("click", saveDeployConfig);
  document.getElementById("edit-deploy-config")?.addEventListener("click", async () => {
    document.getElementById("deploy-config-form").style.display = "block";
    document.getElementById("deploy-configured").style.display = "none";
    clearDeployForm();

    // Fetch and populate existing config
    if (!state.currentApp) return;
    try {
      const result = await invoke("get_deploy_config", { name: state.currentApp.name });
      if (result.configured && result.config) {
        const cfg = result.config;
        document.getElementById("deploy-server").value = cfg.server || "";
        document.getElementById("deploy-ssh-user").value = cfg.ssh_user || "root";
        document.getElementById("deploy-registry").value = cfg.registry || "Docker Hub";
        document.getElementById("deploy-app-name").value = cfg.app_name || "";
        document.getElementById("deploy-registry-username").value = cfg.registry_username || "";
        document.getElementById("deploy-registry-password").value = cfg.registry_password || "";
        document.getElementById("deploy-domain").value = cfg.domain || "";
        document.getElementById("deploy-master-key").value = cfg.rails_master_key || "";
      } else {
        // No config for this app — set defaults
        document.getElementById("deploy-app-name").value = state.currentApp.name;
        document.getElementById("deploy-ssh-user").value = "root";
      }
    } catch (e) {
      console.error("Failed to load deploy config for editing:", e);
      document.getElementById("deploy-app-name").value = state.currentApp.name;
      document.getElementById("deploy-ssh-user").value = "root";
    }
  });
  document.getElementById("kamal-setup")?.addEventListener("click", () => runKamalCommand("setup"));
  document.getElementById("kamal-deploy")?.addEventListener("click", () => runKamalCommand("deploy"));
  document.getElementById("kamal-logs")?.addEventListener("click", () => runKamalCommand("logs"));
  document.getElementById("kamal-remove")?.addEventListener("click", async () => {
    if (!state.currentApp) return;
    const confirmed = await invoke("confirm_dialog", {
      title: "Remove Deployment",
      message: `This will remove the Kamal deployment for ${state.currentApp.name} from the remote server. Are you sure?`
    });
    if (confirmed) {
      runKamalCommand("remove");
    }
  });

  document.getElementById("redis-scan")?.addEventListener("click", scanRedisKeys);

  async function loadAppLogs() {
    if (!state.currentApp) return;
    const logsEl = document.getElementById("logs-output");
    if (!logsEl) return;
    
    logsEl.innerHTML = '<p style="color: var(--ink-soft);">Loading logs...</p>';
    
    try {
      const logs = await invoke("get_app_logs", { name: state.currentApp.name, lines: 100 });
      if (logsEl) {
        if (logs && logs.length > 0) {
          logsEl.innerHTML = logs;
        } else {
          logsEl.innerHTML = "No logs found. The app may not have generated any logs yet.";
        }
      }
    } catch (e) {
      if (logsEl) {
        logsEl.innerHTML = `Error loading logs: ${e}`;
      }
    }
  }

  document.getElementById("refresh-logs")?.addEventListener("click", loadAppLogs);

  document.getElementById("clear-logs")?.addEventListener("click", () => {
    if (logsOutput) logsOutput.textContent = "No logs yet.";
  });

  document.getElementById("bundle-install")?.addEventListener("click", async () => {
    if (!state.currentApp) return;
    try {
      showToast("Running bundle install...");
      const result = await invoke("bundle_install", { name: state.currentApp.name });
      showToast("Bundle install complete");
    } catch (e) {
      showToast(`Bundle install failed: ${e}`);
    }
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

  document.getElementById("install-ruby-btn")?.addEventListener("click", async () => {
    const select = document.getElementById("ruby-version-select");
    const version = select?.value;
    if (!version) {
      showToast("Please select a Ruby version");
      return;
    }
    try {
      showToast(`Installing Ruby ${version}...`);
      const result = await invoke("install_ruby", { version });
      showToast(result);
      loadRubyVersions();
    } catch (e) {
      if (e.includes("brew install")) {
        showToast(`Install Ruby ${version} via Homebrew first: brew install ruby@${version}`);
      } else {
        showToast(`Failed to install Ruby: ${e}`);
      }
    }
  });

  loadRubyVersions();

  if (appsGrid) {
    appsGrid.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-action]");
      if (!button) return;
      handleAppAction(button.dataset.action, button.dataset.app);
    });
  }

  if (appsFolder) {
    appsFolder.textContent = "~/StableCaddy/projects";
  }
}

async function loadAppsFolder() {
  if (!appsFolder) appsFolder = document.querySelector("#apps-folder");
  try {
    const folder = await invoke("apps_folder");
    if (appsFolder) appsFolder.textContent = folder;
  } catch (error) {
    if (appsFolder) appsFolder.textContent = "~/StableCaddy/projects";
  }
}

async function loadRubyVersions() {
  const container = document.getElementById("ruby-versions-list");
  if (!container) return;
  
  try {
    const versions = await invoke("list_ruby_versions");
    if (versions.length === 0) {
      container.innerHTML = '<p class="loading">No Ruby versions installed yet.</p>';
      return;
    }
    
    container.innerHTML = versions.map(v => `
      <div class="ruby-version-item">
        <div class="ruby-version-info">
          <div class="ruby-version-icon">Rb</div>
          <div>
            <div class="ruby-version-name">Ruby ${v}</div>
            <div class="ruby-version-path">${v.includes('.') ? 'Local build' : 'Homebrew'}</div>
          </div>
        </div>
        <span class="ruby-version-status">Installed</span>
      </div>
    `).join("");
  } catch (e) {
    container.innerHTML = '<p class="loading">Failed to load Ruby versions</p>';
  }
}

window.deleteEnvVar = deleteEnvVar;
window.addEnvVar = addEnvVar;
window.saveEnvFile = saveEnvFile;
window.loadEnvFile = loadEnvFile;
window.loadDeployConfig = loadDeployConfig;
window.runKamalCommand = runKamalCommand;

window.addEventListener("DOMContentLoaded", () => {
  wireEvents();
  loadAppsWithRunningState();
  loadAppsFolder();

  setTimeout(() => {
    loadAppsWithRunningState();
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

  listen("show-about", () => {
    const modal = document.getElementById("about-modal");
    if (modal) modal.style.display = "flex";
  });

  document.getElementById("about-close")?.addEventListener("click", () => {
    const modal = document.getElementById("about-modal");
    if (modal) modal.style.display = "none";
  });

  document.getElementById("about-modal")?.addEventListener("click", (e) => {
    if (e.target.id === "about-modal") {
      const modal = document.getElementById("about-modal");
      if (modal) modal.style.display = "none";
    }
  });
});
