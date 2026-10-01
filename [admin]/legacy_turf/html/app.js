const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'legacy_turf';
const $ = (id) => document.getElementById(id);

const els = {
  admin: $('admin'), close: $('close'), refresh: $('refresh'), zoneList: $('zone-list'), zoneCount: $('zone-count'),
  activeName: $('active-name'), activeState: $('active-state'), lock: $('lock'), unlock: $('unlock'), stop: $('stop'), monitor: $('monitor'),
  emptyEditor: $('empty-editor'), form: $('zone-form'), formTitle: $('form-title'), shapeBadge: $('shape-badge'),
  name: $('zone-name'), radius: $('zone-radius'), radiusField: $('radius-field'), recenterField: $('recenter-field'), recenter: $('zone-recenter'),
  color: $('zone-color'), vehicles: $('zone-vehicles'), startVehicles: $('start-vehicles'), eventOverride: $('event-override'),
  save: $('save'), redraw: $('redraw'), start: $('start'), delete: $('delete'), error: $('form-error'),
  newCircle: $('new-circle'), newPoly: $('new-poly'), overlaySide: $('overlay-side'), overlayScale: $('overlay-scale'), overlayScaleValue: $('overlay-scale-value'),
  observer: $('observer'), observerZone: $('observer-zone'), observerState: $('observer-state'), observerCount: $('observer-count'), observerList: $('observer-list'),
  notices: $('notices'), member: $('member'), memberZone: $('member-zone'), memberState: $('member-state'), memberKicker: $('member-kicker'),
  countdown: $('countdown'), countdownValue: $('countdown-value'), polyEditor: $('poly-editor'), polyPoints: $('poly-points'),
};

let zones = [];
let active = null;
let selectedId = null;
let formMode = null;
let formShape = null;
let manualMonitor = false;
let deleteArmed = false;
let countdownTimer = null;
let countdownDeadline = 0;

function post(name, data = {}) {
  return fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).then((response) => response.json()).catch(() => ({ ok: false }));
}

function escapeText(value) {
  return String(value ?? '');
}

function selectedZone() {
  return zones.find((zone) => Number(zone.id) === Number(selectedId)) || null;
}

function colorValue(id) {
  const colors = { 1: '#ef4444', 2: '#22c55e', 3: '#3b82f6', 5: '#eab308', 27: '#a855f7', 47: '#f97316' };
  return colors[Number(id)] || colors[3];
}

function renderZones() {
  els.zoneList.replaceChildren();
  els.zoneCount.textContent = `${zones.length} zone`;

  zones.forEach((zone) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `zone-item${Number(zone.id) === Number(selectedId) ? ' selected' : ''}`;

    const text = document.createElement('div');
    const name = document.createElement('strong');
    name.textContent = zone.name;
    const detail = document.createElement('small');
    detail.textContent = zone.shape === 'circle' ? `Circle · ${Math.round(zone.radius)}m` : `Poly · ${(zone.points || []).length} điểm`;
    text.append(name, detail);

    const dot = document.createElement('span');
    dot.className = 'color-dot';
    dot.style.background = colorValue(zone.color);
    button.append(text, dot);
    button.addEventListener('click', () => selectZone(zone.id));
    els.zoneList.appendChild(button);
  });
}

function renderActive() {
  const running = Boolean(active && active.zone);
  els.activeName.textContent = running ? active.zone.name : 'Chưa có event';
  els.activeState.textContent = running ? active.state.toUpperCase() : 'STOPPED';
  els.activeState.style.color = running && active.state === 'locked' ? '#fb7185' : running ? '#34d399' : '';
  els.lock.disabled = !running || active.state !== 'open';
  els.unlock.disabled = !running || active.state !== 'locked';
  els.stop.disabled = !running;
  els.monitor.disabled = !running;
  els.monitor.textContent = `Monitor: ${manualMonitor ? 'ON' : 'OFF'}`;
  els.start.disabled = running || !selectedZone();
  const activeSelected = running && Number(active.zone.id) === Number(selectedId);
  els.delete.disabled = activeSelected;
  els.save.disabled = activeSelected;
  els.redraw.disabled = activeSelected;
}

function setFormVisible(visible) {
  els.form.classList.toggle('hidden', !visible);
  els.emptyEditor.classList.toggle('hidden', visible);
}

function fillForm(zone, mode, shape) {
  formMode = mode;
  formShape = shape;
  deleteArmed = false;
  els.delete.textContent = 'Xóa';
  els.error.textContent = '';
  setFormVisible(true);

  els.formTitle.textContent = mode === 'create' ? `Tạo ${shape === 'circle' ? 'Circle' : 'PolyZone'}` : zone.name;
  els.shapeBadge.textContent = shape.toUpperCase();
  els.name.value = zone.name || '';
  els.color.value = String(zone.color || 3);
  els.vehicles.checked = zone.allowVehicles !== false;
  els.startVehicles.checked = zone.allowVehicles !== false;
  els.radius.value = zone.radius || 100;
  els.recenter.checked = false;

  els.radiusField.classList.toggle('hidden', shape !== 'circle');
  els.recenterField.classList.toggle('hidden', !(shape === 'circle' && mode === 'edit'));
  els.redraw.classList.toggle('hidden', !(shape === 'poly' && mode === 'edit'));
  els.start.classList.toggle('hidden', mode !== 'edit');
  els.delete.classList.toggle('hidden', mode !== 'edit');
  els.eventOverride.classList.toggle('hidden', mode !== 'edit');
  els.save.textContent = shape === 'poly' && mode === 'create' ? 'Bắt đầu vẽ' : 'Lưu';
  renderActive();
}

function selectZone(id) {
  selectedId = Number(id);
  const zone = selectedZone();
  if (zone) fillForm(zone, 'edit', zone.shape);
  renderZones();
}

function currentPayload() {
  return {
    id: formMode === 'edit' ? selectedId : null,
    name: els.name.value.trim(),
    shape: formShape,
    radius: Number(els.radius.value),
    color: Number(els.color.value),
    allowVehicles: els.vehicles.checked,
    recenter: els.recenter.checked,
    center: formMode === 'edit' && selectedZone() ? selectedZone().center : null,
  };
}

function validateForm() {
  els.error.textContent = '';
  if (!els.name.value.trim()) {
    els.error.textContent = 'Vui lòng nhập tên zone.';
    return false;
  }
  if (formShape === 'circle' && (Number(els.radius.value) < 5 || Number(els.radius.value) > 1000)) {
    els.error.textContent = 'Bán kính phải từ 5 đến 1000 mét.';
    return false;
  }
  return true;
}

function renderAdminData(data) {
  zones = Array.isArray(data?.zones) ? data.zones : [];
  active = data?.active || null;
  if (selectedId && !zones.some((zone) => Number(zone.id) === Number(selectedId))) {
    selectedId = null;
    formMode = null;
    formShape = null;
    setFormVisible(false);
  }
  renderZones();
  renderActive();
  if (formMode === 'edit' && selectedId) {
    const zone = selectedZone();
    if (zone) fillForm(zone, 'edit', zone.shape);
  }
}

function applyOverlaySettings(settings = {}) {
  const side = settings.side === 'left' ? 'left' : 'right';
  const scale = Math.min(1.35, Math.max(.7, Number(settings.scale) || 1));
  els.overlaySide.value = side;
  els.overlayScale.value = String(Math.round(scale * 100));
  els.overlayScaleValue.textContent = `${Math.round(scale * 100)}%`;
  els.observer.classList.toggle('left', side === 'left');
  els.notices.classList.toggle('left', side === 'left');
  els.observer.style.setProperty('--observer-scale', scale);
}

function saveOverlaySettings() {
  const data = { side: els.overlaySide.value, scale: Number(els.overlayScale.value) / 100 };
  applyOverlaySettings(data);
  post('saveOverlaySettings', data);
}

function renderObserver(data) {
  if (!data?.zone) return;
  els.observer.classList.remove('hidden');
  els.observerZone.textContent = data.zone;
  els.observerState.textContent = String(data.state || 'open').toUpperCase();
  els.observerState.classList.toggle('locked', data.state === 'locked');
  els.observerCount.textContent = String(data.count ?? 0);
  els.observerList.replaceChildren();

  (data.players || []).forEach((player) => {
    const item = document.createElement('li');
    item.className = player.status || 'inside';
    const dot = document.createElement('span');
    dot.className = 'status-dot';
    const name = document.createElement('span');
    name.textContent = `[${player.id}] ${player.name}`;
    const status = document.createElement('small');
    status.textContent = player.status === 'outside' ? `OUT ${player.remaining ?? 0}s` : player.status === 'eliminated' ? 'ELIM' : 'IN';
    item.append(dot, name, status);
    els.observerList.appendChild(item);
  });
}

function formatNotice(message) {
  const fragment = document.createDocumentFragment();
  const classes = { '~r~': 'token-red', '~g~': 'token-green', '~o~': 'token-orange', '~w~': 'token-white', '~s~': 'token-white' };
  let activeClass = 'token-white';
  String(message || '').split(/(~[rgows]~)/g).forEach((part) => {
    if (classes[part]) activeClass = classes[part];
    else if (part) {
      const span = document.createElement('span');
      span.className = activeClass;
      span.textContent = part;
      fragment.appendChild(span);
    }
  });
  return fragment;
}

function pushNotice(message, kind) {
  const item = document.createElement('div');
  item.className = `notice ${kind || 'info'}`;
  item.appendChild(formatNotice(message));
  els.notices.appendChild(item);
  window.setTimeout(() => item.remove(), 3300);
}

function stopCountdown() {
  if (countdownTimer) window.clearInterval(countdownTimer);
  countdownTimer = null;
  countdownDeadline = 0;
  els.countdown.classList.add('hidden');
}

function startCountdown(seconds) {
  stopCountdown();
  countdownDeadline = Date.now() + Number(seconds || 10) * 1000;
  els.countdown.classList.remove('hidden');
  const update = () => {
    const remaining = Math.max(0, Math.ceil((countdownDeadline - Date.now()) / 1000));
    els.countdownValue.textContent = String(remaining);
    if (remaining <= 0) stopCountdown();
  };
  update();
  countdownTimer = window.setInterval(update, 100);
}

els.close.addEventListener('click', () => post('close'));
els.refresh.addEventListener('click', () => post('refresh'));
els.newCircle.addEventListener('click', () => { selectedId = null; renderZones(); fillForm({ color: 3, allowVehicles: true, radius: 100 }, 'create', 'circle'); });
els.newPoly.addEventListener('click', () => { selectedId = null; renderZones(); fillForm({ color: 3, allowVehicles: true }, 'create', 'poly'); });

els.form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!validateForm()) return;
  const payload = currentPayload();
  if (formShape === 'poly' && formMode === 'create') {
    const result = await post('beginPoly', payload);
    if (result?.ok === false) els.error.textContent = result.message || 'Không thể mở Poly editor.';
  } else if (formShape === 'poly') {
    await post('saveMetadata', payload);
  } else {
    await post('saveCircle', payload);
  }
});

els.redraw.addEventListener('click', async () => {
  if (!validateForm()) return;
  await post('beginPoly', currentPayload());
});

els.start.addEventListener('click', () => {
  if (!selectedId) return;
  post('start', { id: selectedId, allowVehicles: els.startVehicles.checked });
});
els.lock.addEventListener('click', () => post('lock'));
els.unlock.addEventListener('click', () => post('unlock'));
els.stop.addEventListener('click', () => post('stop'));
els.monitor.addEventListener('click', () => {
  manualMonitor = !manualMonitor;
  post('monitor', { enabled: manualMonitor });
  renderActive();
});

els.delete.addEventListener('click', () => {
  if (!selectedId) return;
  if (!deleteArmed) {
    deleteArmed = true;
    els.delete.textContent = 'Bấm lại để xác nhận';
    window.setTimeout(() => { deleteArmed = false; els.delete.textContent = 'Xóa'; }, 3000);
    return;
  }
  deleteArmed = false;
  post('deleteZone', { id: selectedId });
});

els.overlaySide.addEventListener('change', saveOverlaySettings);
els.overlayScale.addEventListener('input', saveOverlaySettings);

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !els.admin.classList.contains('hidden')) post('close');
});

window.addEventListener('message', (event) => {
  const message = event.data || {};
  if (message.action === 'openAdmin') els.admin.classList.remove('hidden');
  else if (message.action === 'closeAdmin') els.admin.classList.add('hidden');
  else if (message.action === 'adminData') renderAdminData(message.data);
  else if (message.action === 'observerSnapshot') renderObserver(message.data);
  else if (message.action === 'observerNotice') pushNotice(message.message, message.kind);
  else if (message.action === 'hideObserver') els.observer.classList.add('hidden');
  else if (message.action === 'overlaySettings') applyOverlaySettings(message.data);
  else if (message.action === 'member') {
    els.member.classList.toggle('hidden', !message.visible);
    if (message.visible) {
      els.memberZone.textContent = escapeText(message.zone);
      els.memberState.textContent = String(message.state || '').toUpperCase();
      els.memberKicker.textContent = message.status === 'eliminated' ? 'BẠN ĐÃ BỊ LOẠI KHỎI' : message.status === 'outside' ? 'BẠN ĐANG NGOÀI' : 'BẠN ĐANG TRONG';
    }
  } else if (message.action === 'countdownStart') startCountdown(message.seconds);
  else if (message.action === 'countdownCancel') stopCountdown();
  else if (message.action === 'polyEditor') {
    els.polyEditor.classList.toggle('hidden', !message.visible);
    els.polyPoints.textContent = String(message.points || 0);
  }
});

applyOverlaySettings({ side: 'right', scale: 1 });
