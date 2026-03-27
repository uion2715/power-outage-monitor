const REFRESH_MS = 60000;
const STATUS_URL = "./status.json";

const card = document.getElementById("status-card");
const badge = document.getElementById("badge");
const customersOut = document.getElementById("customers-out");
const threshold = document.getElementById("threshold");
const sourceUpdated = document.getElementById("source-updated");
const checkedAt = document.getElementById("checked-at");
const summary = document.getElementById("summary");
const sourceLink = document.getElementById("source-link");

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(value);
}

function formatDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "--";
  }
  return date.toLocaleString();
}

function setState(state, badgeText) {
  card.dataset.state = state;
  badge.textContent = badgeText;
}

function render(data) {
  const alerting = data.status === "alert" || data.customersOut >= data.threshold;
  setState(alerting ? "alert" : "normal", alerting ? "Alert Active" : "Normal");

  customersOut.textContent = formatNumber(data.customersOut);
  threshold.textContent = formatNumber(data.threshold);
  sourceUpdated.textContent = data.sourceUpdated || "--";
  checkedAt.textContent = formatDate(data.checkedAt);
  sourceLink.href = data.sourceUrl || sourceLink.href;

  summary.textContent = alerting
    ? `Washington is at or above the alert threshold. Last alert count: ${formatNumber(data.lastAlertCount || data.customersOut)}.`
    : "Washington is currently below the alert threshold.";
}

function renderError(message) {
  setState("error", "Unavailable");
  customersOut.textContent = "--";
  sourceUpdated.textContent = "--";
  checkedAt.textContent = "--";
  summary.textContent = message;
}

async function loadStatus() {
  try {
    setState("loading", "Refreshing");
    const response = await fetch(`${STATUS_URL}?t=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`status fetch failed with ${response.status}`);
    }
    const data = await response.json();
    render(data);
  } catch (error) {
    renderError("The app could not load the latest outage status file yet.");
  }
}

loadStatus();
window.setInterval(loadStatus, REFRESH_MS);
