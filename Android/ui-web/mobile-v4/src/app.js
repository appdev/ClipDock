(() => {
  "use strict";

  const VERSION = 1;
  const WIDTH = 370;
  const HEIGHT = 824;
  const SCREENS = [
    "history",
    "devices",
    "files",
    "settings",
    "keep_alive",
    "floating_ball",
    "item_detail_text",
    "remote_asset_sheet",
    "delete_confirm",
  ];
  const ROOT_ROUTES = new Set(["history", "devices", "files", "settings"]);
  const ROUTE_TO_NAV = {
    history: "历史",
    devices: "设备",
    files: "文件",
    settings: "设置",
    keep_alive: "设置",
    floating_ball: "设置",
    item_detail_text: null,
    remote_asset_sheet: null,
    delete_confirm: null,
  };
  const FORBIDDEN_KEYS = new Set([
    "token",
    "deviceToken",
    "serverUrl",
    "url",
    "uri",
    "file",
    "path",
    "payload",
    "payloadBytes",
    "item",
    "items",
    "repository",
  ]);
  const SELECTED_ITEM_ACTIONS = new Set([
    "copyItem",
    "showDeleteConfirm",
    "removeLocalCache",
    "deleteSyncRecord",
    "downloadAndCopy",
    "downloadToCache",
    "copyThumbnail",
  ]);
  const DEFAULT_DETAIL_STABLE_ID = "qa-ready-text";
  const DEFAULT_REMOTE_STABLE_ID = "qa-remote-image";

  let manifest = null;
  let provenance = null;
  let hotzoneDocument = null;
  let currentRoute = null;
  let currentTheme = null;
  let currentSelectedStableId = null;
  let requestCounter = 0;
  let nativeState = {};
  const pendingBridgeReplies = new Map();

  function params() {
    return new URLSearchParams(window.location.search);
  }

  function requestedRoute() {
    const screen = params().get("screen_id") || params().get("route") || "history";
    return SCREENS.includes(screen) ? screen : "history";
  }

  function requestedTheme() {
    const explicit = params().get("theme");
    if (explicit === "dark" || explicit === "light") return explicit;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function requestedSelectedStableId() {
    const value = params().get("selected_stable_id");
    return value && value.length <= 96 ? value : null;
  }

  async function loadJson(path) {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) throw new Error(`${path} load failed: ${response.status}`);
    return response.json();
  }

  async function loadRuntimeAssets() {
    manifest = await loadJson("manifest.json");
    provenance = await loadJson("provenance.json");
    hotzoneDocument = await loadJson("hotzones.json");
    installBridgeReplyHandlers();
  }

  function installBridgeReplyHandlers() {
    const receive = (event) => {
      const data = event && "data" in event ? event.data : event;
      receiveBridgeResult(data);
    };
    if (window.clipdockBridge) {
      window.clipdockBridge.onmessage = receive;
    }
    window.addEventListener("message", receive);
    window.__clipdockReceiveBridgeResult = receiveBridgeResult;
  }

  function receiveBridgeResult(raw) {
    let result = raw;
    if (typeof raw === "string") {
      try {
        result = JSON.parse(raw);
      } catch (_) {
        return;
      }
    }
    if (!result || typeof result !== "object" || !result.requestId) return;
    const pending = pendingBridgeReplies.get(result.requestId);
    if (!pending) return;
    pendingBridgeReplies.delete(result.requestId);
    pending.resolve(result);
  }

  function zonesFor(route = currentRoute, theme = currentTheme) {
    return hotzoneDocument?.items?.[theme]?.[route] || [];
  }

  function visualSha(route = currentRoute, theme = currentTheme) {
    return provenance?.visualPngSha256?.[theme]?.[route] || null;
  }

  function render(route = currentRoute || requestedRoute(), theme = currentTheme || requestedTheme()) {
    currentRoute = SCREENS.includes(route) ? route : "history";
    currentTheme = theme === "dark" ? "dark" : "light";
    document.documentElement.dataset.theme = currentTheme;
    document.body.className = `mobile-v4-runtime theme-${currentTheme}`;
    const root = document.getElementById("clipdock-root");
    root.replaceChildren();
    root.style.width = `${WIDTH}px`;
    root.style.height = `${HEIGHT}px`;
    const image = document.createElement("img");
    image.className = "clipdock-visual-layer";
    image.alt = "";
    image.width = WIDTH;
    image.height = HEIGHT;
    image.draggable = false;
    image.src = `screens/${currentTheme}/${currentRoute}.png`;
    root.appendChild(image);
    for (const zone of effectiveZonesFor()) {
      root.appendChild(buttonFromZone(zone));
    }
  }

  function effectiveZonesFor(route = currentRoute, theme = currentTheme) {
    return zonesFor(route, theme).map((zone) => selectedZone(zone, route));
  }

  function selectedStableIdForRoute(route = currentRoute) {
    if (route === "remote_asset_sheet") return currentSelectedStableId || DEFAULT_REMOTE_STABLE_ID;
    if (route === "item_detail_text" || route === "delete_confirm") return currentSelectedStableId || DEFAULT_DETAIL_STABLE_ID;
    return null;
  }

  function selectedZone(zone, route = currentRoute) {
    const selectedStableId = selectedStableIdForRoute(route);
    if (!selectedStableId || !SELECTED_ITEM_ACTIONS.has(zone.action)) return zone;
    const bridge = { ...(zone.bridge || {}), stableId: selectedStableId };
    return {
      ...zone,
      stable_id: selectedStableId,
      action_id: `${zone.action}:${selectedStableId}`,
      label: selectedActionLabel(zone, selectedStableId),
      bridge,
    };
  }

  function selectedActionLabel(zone, selectedStableId) {
    const base = zone.label || zone.action_id || zone.action;
    return base.includes(selectedStableId) ? base : `${base} (${selectedStableId})`;
  }

  function buttonFromZone(zone) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "clipdock-hotzone";
    button.dataset.actionId = zone.action_id;
    button.dataset.bridgeAction = zone.action;
    button.dataset.stableZoneId = zone.stable_id;
    if (zone.bridge?.stableId) button.dataset.stableId = zone.bridge.stableId;
    if (zone.bridge?.route) button.dataset.route = zone.bridge.route;
    if (zone.bridge?.sheet) button.dataset.sheet = zone.bridge.sheet;
    if (zone.bridge?.setting) button.dataset.setting = zone.bridge.setting;
    if (zone.bridge && Object.prototype.hasOwnProperty.call(zone.bridge, "value")) {
      button.dataset.value = JSON.stringify(zone.bridge.value);
    }
    button.setAttribute("aria-label", zone.label || zone.action_id);
    button.style.left = `${zone.bounds.x}px`;
    button.style.top = `${zone.bounds.y}px`;
    button.style.width = `${zone.bounds.width}px`;
    button.style.height = `${zone.bounds.height}px`;
    button.style.zIndex = String(zone.z_order || 1);
    if (zone.enabled === false) {
      button.disabled = true;
      button.setAttribute("aria-disabled", "true");
    }
    return button;
  }

  function requestPayloadFromElement(element) {
    const payload = {
      version: VERSION,
      requestId: nextRequestId(),
      action: element.dataset.bridgeAction,
    };
    if (element.dataset.stableId) payload.stableId = element.dataset.stableId;
    if (element.dataset.route) payload.route = element.dataset.route;
    if (element.dataset.sheet) payload.sheet = element.dataset.sheet;
    if (element.dataset.setting) payload.setting = element.dataset.setting;
    if (element.dataset.value !== undefined) payload.value = JSON.parse(element.dataset.value);
    validateClientPayload(payload);
    return payload;
  }

  function nextRequestId() {
    requestCounter += 1;
    return `web-${Date.now().toString(36)}-${requestCounter.toString(36)}`;
  }

  function validateClientPayload(payload) {
    for (const key of Object.keys(payload)) {
      if (FORBIDDEN_KEYS.has(key)) throw new Error(`forbidden bridge key: ${key}`);
    }
  }

  function sendBridgeMessage(payload) {
    return new Promise((resolve) => {
      const timeout = window.setTimeout(() => {
        pendingBridgeReplies.delete(payload.requestId);
        resolve({ version: VERSION, requestId: payload.requestId, status: "error", errorCode: "bridge_timeout" });
      }, 3500);
      pendingBridgeReplies.set(payload.requestId, {
        resolve: (result) => {
          window.clearTimeout(timeout);
          resolve(result);
        },
      });
      if (window.clipdockBridge && typeof window.clipdockBridge.postMessage === "function") {
        window.clipdockBridge.postMessage(JSON.stringify(payload));
      } else {
        receiveBridgeResult({ version: VERSION, requestId: payload.requestId, status: "error", errorCode: "missing_native_bridge" });
      }
    });
  }

  function applyBridgeStatePatch(payload, result) {
    const patch = result && result.statePatch && typeof result.statePatch === "object" ? result.statePatch : {};
    if (typeof patch.selectedStableId === "string") {
      currentSelectedStableId = patch.selectedStableId || null;
    } else if (payload.stableId && (payload.action === "openItemDetail" || payload.action === "showRemoteRetrieval" || payload.action === "showDeleteConfirm")) {
      currentSelectedStableId = payload.stableId;
    } else if (payload.action === "closeDetail" || payload.action === "hideRemoteRetrieval") {
      currentSelectedStableId = null;
    }
  }

  function nextRouteForAcceptedPayload(payload, result) {
    const patch = result && result.statePatch && typeof result.statePatch === "object" ? result.statePatch : {};
    if (typeof patch.nextRoute === "string" && SCREENS.includes(patch.nextRoute)) return patch.nextRoute;
    if (payload.action === "selectDestination" && payload.route && ROOT_ROUTES.has(payload.route)) return payload.route;
    if (payload.action === "openItemDetail") return payload.stableId === "qa-remote-image" ? "remote_asset_sheet" : "item_detail_text";
    if (payload.action === "closeDetail") return "history";
    if (payload.action === "showRemoteRetrieval") return "remote_asset_sheet";
    if (payload.action === "hideRemoteRetrieval") return "history";
    if (payload.action === "showDeleteConfirm") return "delete_confirm";
    if (payload.action === "hideDeleteConfirm") return "item_detail_text";
    if (payload.action === "openSettingsDetail" && (payload.route === "keep_alive" || payload.route === "floating_ball")) return payload.route;
    if (payload.action === "closeSettingsDetail") return "settings";
    return currentRoute;
  }

  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-action-id]");
    if (!target || target.disabled) return;
    event.preventDefault();
    const beforeRoute = currentRoute;
    const beforeTheme = currentTheme;
    const payload = requestPayloadFromElement(target);
    sendBridgeMessage(payload).then((result) => {
      if (result && result.status === "ok") {
        applyBridgeStatePatch(payload, result);
        render(nextRouteForAcceptedPayload(payload, result), beforeTheme);
      } else {
        render(beforeRoute, beforeTheme);
      }
    });
  });

  window.__clipdockApplyNativeState = (state) => {
    nativeState = state && typeof state === "object" ? state : {};
    if (Object.prototype.hasOwnProperty.call(nativeState, "selectedStableId")) {
      if (typeof nativeState.selectedStableId === "string" && nativeState.selectedStableId) {
        currentSelectedStableId = nativeState.selectedStableId;
      } else if (ROOT_ROUTES.has(currentRoute)) {
        currentSelectedStableId = null;
      }
      if (currentRoute === "item_detail_text" || currentRoute === "remote_asset_sheet" || currentRoute === "delete_confirm") {
        render(currentRoute, currentTheme);
      }
    }
  };

  window.__clipdockBack = () => {
    const action =
      currentRoute === "remote_asset_sheet"
        ? "hideRemoteRetrieval"
        : currentRoute === "delete_confirm"
          ? "hideDeleteConfirm"
          : currentRoute === "item_detail_text"
            ? "closeDetail"
            : currentRoute === "keep_alive" || currentRoute === "floating_ball"
              ? "closeSettingsDetail"
              : null;
    if (!action) return false;
    const payload = { version: VERSION, requestId: nextRequestId(), action };
    sendBridgeMessage(payload).then((result) => {
      if (result && result.status === "ok") {
        applyBridgeStatePatch(payload, result);
        render(nextRouteForAcceptedPayload(payload, result), currentTheme);
      }
    });
    return true;
  };

  window.__clipdockQaRender = (route, theme, selectedStableId) => {
    if (!SCREENS.includes(route)) return false;
    if (selectedStableId !== undefined) currentSelectedStableId = selectedStableId || null;
    render(route, theme || currentTheme);
    return true;
  };

  window.__clipdockQaDumpRuntimeState = () => runtimeSemantics();
  window.__clipdockQaDumpSemantics = () => runtimeSemantics();

  function runtimeSemantics() {
    const zones = effectiveZonesFor();
    const hotzonesSha = provenance?.hotzonesSha256 || manifest?.hotzonesSha256 || null;
    return {
      version: VERSION,
      screen_id: currentRoute,
      theme: currentTheme,
      route: currentRoute,
      active_sheet: currentRoute === "remote_asset_sheet" ? "remote_retrieval" : currentRoute === "delete_confirm" ? "delete_confirm" : null,
      selected_nav: ROUTE_TO_NAV[currentRoute],
      selected_stable_id: selectedStableIdForRoute(),
      visible_texts: referenceSemantics()?.visible_texts || [],
      anchors: zones.map((zone) => ({ action_id: zone.action_id, stable_id: zone.stable_id, bounds: zone.bounds })),
      bridge_action_ids: [...new Set(zones.map((zone) => zone.action_id))],
      enabled_states: Object.fromEntries(zones.map((zone) => [zone.action_id, zone.enabled !== false])),
      focus_order: zones.map((zone) => zone.action_id),
      aria_labels: zones.map((zone) => zone.label),
      touch_targets_px: Object.fromEntries(zones.map((zone) => [zone.action_id, zone.bounds])),
      key_bounds_px: referenceSemantics()?.key_bounds_px || { screen: { x: 0, y: 0, width: WIDTH, height: HEIGHT } },
      computed: {
        screen: { bounds: bounds(document.getElementById("clipdock-root")) },
        viewport: { innerWidth: window.innerWidth, innerHeight: window.innerHeight },
      },
      sheet_order: zones.filter((zone) => zone.active_sheet).map((zone) => ({ action_id: zone.action_id, z_order: zone.z_order })),
      source_sha256: manifest?.sourceSha256 || provenance?.sourceTreeSha256 || null,
      runtime_asset_sha256: manifest?.runtimeAssetSha256 || provenance?.runtimeAssetSha256 || null,
      visual_png_sha256: visualSha(),
      hotzones_sha256: hotzonesSha,
      runtime_dom_source: "installed-production-webview",
      semantic_source: "dom-extracted-reference-and-production-hotzones",
      fallback: false,
      native_state: {
        itemCount: nativeState.itemCount,
        p2pEnabled: nativeState.p2pEnabled,
        wifiOnly: nativeState.wifiOnly,
        overlayEnabled: nativeState.overlayEnabled,
      },
    };
  }

  function referenceSemantics() {
    return provenance?.semantics?.[currentTheme]?.[currentRoute] || null;
  }

  function bounds(element) {
    const rect = element.getBoundingClientRect();
    return {
      x: Math.round(rect.left),
      y: Math.round(rect.top),
      width: Math.round(rect.width),
      height: Math.round(rect.height),
    };
  }

  document.addEventListener("DOMContentLoaded", async () => {
    const root = document.getElementById("clipdock-root");
    root.innerHTML = "<div class=\"clipdock-loading\">Loading ClipDock</div>";
    try {
      await loadRuntimeAssets();
      currentSelectedStableId = requestedSelectedStableId();
      render(requestedRoute(), requestedTheme());
    } catch (error) {
      root.innerHTML = `<div class="clipdock-error">${String(error && error.message ? error.message : error)}</div>`;
    }
  });
})();
