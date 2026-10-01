let currentCoords = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 };
let currentBones = [];
let selectedWeaponForSetup = null;
let positionStep = 0.001;
let rotationStep = 1;
let editorOpen = false;
let saving = false;
let updateFrame = null;
let history = [];
let historyIndex = -1;
let historyLimit = 30;
let dragHistoryStart = null;

const editorConfig = {
    positionSliderMin: -0.75,
    positionSliderMax: 0.75,
    positionHardLimit: 2.0,
    positionSteps: [0.001, 0.005, 0.020],
    rotationMin: -180,
    rotationMax: 180,
    rotationSteps: [1, 5, 15],
    historyLimit: 30
};

const axes = ['x', 'y', 'z', 'rx', 'ry', 'rz'];
const app = document.getElementById('app');
const dashboardView = document.getElementById('dashboard-view');
const editorView = document.getElementById('editor-view');
const boneSelect = document.getElementById('bone-select');
const weaponTitle = document.getElementById('weapon-title');
const inventoryWeapons = document.getElementById('inventory-weapons');
const configuredWeapons = document.getElementById('configured-weapons');
const setupSection = document.getElementById('setup-section');
const setupWeaponName = document.getElementById('setup-weapon-name');
const setupBoneSelect = document.getElementById('setup-bone-select');
const charRotSlider = document.getElementById('slider-char-rot');
const charRotDisplay = document.getElementById('val-char-rot');
const saveButton = document.getElementById('btn-save');
const cancelButton = document.getElementById('btn-cancel');
const undoButton = document.getElementById('btn-undo');
const redoButton = document.getElementById('btn-redo');
const sliders = {};
const numberInputs = {};

function postNui(route, payload = {}) {
    return fetch(`https://${GetParentResourceName()}/${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });
}

function finiteNumber(value, fallback = 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

function clampAxis(axis, value) {
    const parsed = finiteNumber(value, currentCoords[axis] || 0);
    if (axis.startsWith('r')) {
        return Math.max(editorConfig.rotationMin, Math.min(editorConfig.rotationMax, parsed));
    }
    return Math.max(-editorConfig.positionHardLimit, Math.min(editorConfig.positionHardLimit, parsed));
}

function sameCoords(a, b) {
    return axes.every(axis => Math.abs(a[axis] - b[axis]) < 0.000001);
}

function configureAxisInputs() {
    axes.forEach(axis => {
        const rotation = axis.startsWith('r');
        const minimum = rotation ? editorConfig.rotationMin : -editorConfig.positionHardLimit;
        const maximum = rotation ? editorConfig.rotationMax : editorConfig.positionHardLimit;
        sliders[axis].min = rotation ? minimum : Math.min(editorConfig.positionSliderMin, currentCoords[axis]);
        sliders[axis].max = rotation ? maximum : Math.max(editorConfig.positionSliderMax, currentCoords[axis]);
        sliders[axis].step = rotation ? 1 : 0.001;
        numberInputs[axis].min = minimum;
        numberInputs[axis].max = maximum;
        numberInputs[axis].step = rotation ? 1 : 0.001;
    });
}

function updateDisplays() {
    configureAxisInputs();
    axes.forEach(axis => {
        sliders[axis].value = currentCoords[axis];
        numberInputs[axis].value = axis.startsWith('r') ? currentCoords[axis].toFixed(0) : currentCoords[axis].toFixed(3);
    });
    undoButton.disabled = saving || historyIndex <= 0;
    redoButton.disabled = saving || historyIndex < 0 || historyIndex >= history.length - 1;
}

function queueCoordsUpdate() {
    if (updateFrame !== null || saving) return;
    updateFrame = requestAnimationFrame(() => {
        updateFrame = null;
        postNui('updateCoords', currentCoords);
    });
}

function recordHistory() {
    const snapshot = { ...currentCoords };
    if (historyIndex >= 0 && sameCoords(history[historyIndex], snapshot)) return;
    history = history.slice(0, historyIndex + 1);
    history.push(snapshot);
    if (history.length > historyLimit) history.shift();
    historyIndex = history.length - 1;
    updateDisplays();
}

function restoreHistory(index) {
    if (saving || index < 0 || index >= history.length) return;
    historyIndex = index;
    currentCoords = { ...history[historyIndex] };
    updateDisplays();
    queueCoordsUpdate();
}

function setSaving(value) {
    saving = Boolean(value);
    saveButton.disabled = saving;
    cancelButton.disabled = saving;
    saveButton.textContent = saving ? 'Đang lưu…' : 'Lưu Vị Trí';
    document.querySelectorAll('#editor-view button, #editor-view input, #editor-view select').forEach(element => {
        if (element !== saveButton && element !== cancelButton) element.disabled = saving;
    });
    updateDisplays();
}

function renderStepButtons(containerId, values, kind) {
    const container = document.getElementById(containerId);
    container.innerHTML = '';
    values.forEach((value, index) => {
        const button = document.createElement('button');
        button.className = `sens-btn${index === 0 ? ' active' : ''}`;
        button.type = 'button';
        button.textContent = kind === 'position' ? Number(value).toFixed(3) : `${value}°`;
        button.addEventListener('click', () => {
            container.querySelectorAll('.sens-btn').forEach(item => item.classList.remove('active'));
            button.classList.add('active');
            if (kind === 'position') positionStep = Number(value);
            else rotationStep = Number(value);
        });
        container.appendChild(button);
    });
    if (kind === 'position') positionStep = Number(values[0]);
    else rotationStep = Number(values[0]);
}

axes.forEach(axis => {
    sliders[axis] = document.getElementById(`slider-${axis}`);
    numberInputs[axis] = document.getElementById(`input-${axis}`);
    sliders[axis].addEventListener('input', event => {
        if (saving) return;
        currentCoords[axis] = clampAxis(axis, event.target.value);
        updateDisplays();
        queueCoordsUpdate();
    });
    sliders[axis].addEventListener('change', recordHistory);
    numberInputs[axis].addEventListener('change', event => {
        if (saving) return;
        currentCoords[axis] = clampAxis(axis, event.target.value);
        updateDisplays();
        queueCoordsUpdate();
        recordHistory();
    });
    numberInputs[axis].addEventListener('input', event => {
        if (saving || event.target.value === '' || event.target.value === '-') return;
        currentCoords[axis] = clampAxis(axis, event.target.value);
        updateDisplays();
        queueCoordsUpdate();
    });
});

document.querySelectorAll('.adjust-btn').forEach(button => {
    button.addEventListener('click', () => {
        if (saving) return;
        const axis = button.dataset.axis;
        const direction = button.dataset.dir === '+' ? 1 : -1;
        const step = axis.startsWith('r') ? rotationStep : positionStep;
        currentCoords[axis] = clampAxis(axis, currentCoords[axis] + direction * step);
        updateDisplays();
        queueCoordsUpdate();
        recordHistory();
    });
});

document.querySelectorAll('.axis-reset').forEach(button => {
    button.addEventListener('click', () => {
        if (saving) return;
        currentCoords[button.dataset.resetAxis] = 0;
        updateDisplays();
        queueCoordsUpdate();
        recordHistory();
    });
});

document.getElementById('btn-reset-all').addEventListener('click', () => {
    if (saving) return;
    currentCoords = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 };
    updateDisplays();
    queueCoordsUpdate();
    recordHistory();
});
undoButton.addEventListener('click', () => restoreHistory(historyIndex - 1));
redoButton.addEventListener('click', () => restoreHistory(historyIndex + 1));

charRotSlider.addEventListener('input', event => {
    const value = parseInt(event.target.value, 10) || 0;
    charRotDisplay.textContent = `${value}°`;
    postNui('rotatePlayer', { heading: value });
});

boneSelect.addEventListener('change', event => {
    const selectedBone = currentBones.find(bone => bone.name === event.target.value);
    if (!selectedBone) return;
    postNui('changeBone', { boneName: selectedBone.label, boneValue: selectedBone.value, boneKey: selectedBone.name });
    weaponTitle.textContent = `${weaponTitle.textContent.split(' - ')[0]} - ${selectedBone.label}`;
});

let isDragging = false;
let dragButton = -1;
let lastX = 0;
let lastY = 0;

window.addEventListener('mousedown', event => {
    if (!editorOpen || saving || event.target.closest('.control-panel') || event.target.closest('.nui-container')) return;
    isDragging = true;
    dragButton = event.button;
    lastX = event.clientX;
    lastY = event.clientY;
    dragHistoryStart = { ...currentCoords };
});
window.addEventListener('mousemove', event => {
    if (!isDragging) return;
    const dx = event.clientX - lastX;
    const dy = event.clientY - lastY;
    lastX = event.clientX;
    lastY = event.clientY;
    postNui('mouseDrag', { dx, dy, button: dragButton });
});
window.addEventListener('mouseup', () => {
    if (isDragging && dragHistoryStart && !sameCoords(dragHistoryStart, currentCoords)) recordHistory();
    isDragging = false;
    dragButton = -1;
    dragHistoryStart = null;
});
window.addEventListener('contextmenu', event => event.preventDefault());

function renderDashboard(inventory, configs, bones) {
    inventoryWeapons.innerHTML = '';
    if (inventory.length === 0) {
        inventoryWeapons.innerHTML = '<div class="empty-state">Không tìm thấy súng trong túi đồ</div>';
    } else {
        inventory.forEach(item => {
            const div = document.createElement('div');
            div.className = 'weapon-item';
            div.innerHTML = `<i class="fa-solid fa-gun"></i><span>${item.label}</span>`;
            div.addEventListener('click', () => {
                selectedWeaponForSetup = item;
                setupWeaponName.textContent = `Súng: ${item.label}`;
                setupSection.style.display = 'block';
            });
            inventoryWeapons.appendChild(div);
        });
    }

    configuredWeapons.innerHTML = '';
    const configKeys = Object.keys(configs).sort();
    if (configKeys.length === 0) {
        configuredWeapons.innerHTML = '<div class="empty-state">Chưa có vị trí súng nào</div>';
    } else {
        configKeys.forEach(key => {
            const info = JSON.parse(configs[key].info);
            const div = document.createElement('div');
            div.className = 'config-item';
            div.innerHTML = `<div class="config-info"><h4>${info.label}</h4><p>Vị trí: ${info.boneName}</p></div><div class="config-actions"><button class="action-icon-btn" title="Chỉnh"><i class="fa-solid fa-pen-to-square"></i></button><button class="action-icon-btn danger" title="Xóa"><i class="fa-solid fa-trash"></i></button></div>`;
            const buttons = div.querySelectorAll('.action-icon-btn');
            buttons[0].addEventListener('click', () => postNui('readjustConfig', { weapon: key }));
            buttons[1].addEventListener('click', () => postNui('deleteConfig', { weapon: key }));
            configuredWeapons.appendChild(div);
        });
    }

    currentBones = bones;
    setupBoneSelect.innerHTML = '';
    bones.forEach(bone => {
        const option = document.createElement('option');
        option.value = bone.name;
        option.textContent = bone.label;
        setupBoneSelect.appendChild(option);
    });
}

document.getElementById('btn-close-dashboard').addEventListener('click', () => postNui('closeDashboard'));
document.getElementById('btn-setup-cancel').addEventListener('click', () => {
    setupSection.style.display = 'none';
    selectedWeaponForSetup = null;
});
document.getElementById('btn-setup-start').addEventListener('click', () => {
    if (!selectedWeaponForSetup) return;
    const selectedBone = currentBones.find(bone => bone.name === setupBoneSelect.value);
    if (!selectedBone) return;
    postNui('startSetup', {
        weaponItem: selectedWeaponForSetup.name,
        weaponLabel: selectedWeaponForSetup.label,
        boneName: selectedBone.label,
        boneValue: selectedBone.value,
        boneKey: selectedBone.name
    });
    setupSection.style.display = 'none';
    selectedWeaponForSetup = null;
});

window.addEventListener('message', event => {
    const data = event.data;
    if (data.action === 'showDashboard') {
        editorOpen = false;
        setSaving(false);
        renderDashboard(data.inventory || [], data.configs || {}, data.bones || []);
        dashboardView.style.display = 'flex';
        editorView.style.display = 'none';
        app.style.display = 'block';
    } else if (data.action === 'showEditor') {
        Object.assign(editorConfig, data.editorConfig || {});
        historyLimit = editorConfig.historyLimit || 30;
        currentCoords = Object.fromEntries(axes.map(axis => [axis, finiteNumber(data.coords[axis], 0)]));
        history = [{ ...currentCoords }];
        historyIndex = 0;
        currentBones = data.bones || [];
        boneSelect.innerHTML = '';
        currentBones.forEach(bone => {
            const option = document.createElement('option');
            option.value = bone.name;
            option.textContent = bone.label;
            option.selected = bone.label === data.boneLabel;
            boneSelect.appendChild(option);
        });
        renderStepButtons('position-steps', editorConfig.positionSteps, 'position');
        renderStepButtons('rotation-steps', editorConfig.rotationSteps, 'rotation');
        weaponTitle.textContent = `${data.weaponLabel} - ${data.boneLabel}`;
        charRotSlider.value = 0;
        charRotDisplay.textContent = '0°';
        editorOpen = true;
        setSaving(false);
        dashboardView.style.display = 'none';
        editorView.style.display = 'flex';
        app.style.display = 'block';
    } else if (data.action === 'updateValues') {
        currentCoords = Object.fromEntries(axes.map(axis => [axis, clampAxis(axis, data.coords[axis])]));
        updateDisplays();
    } else if (data.action === 'saveState') {
        setSaving(data.saving);
    } else if (data.action === 'hideEditor') {
        editorOpen = false;
        app.style.display = 'none';
    }
});

saveButton.addEventListener('click', () => {
    if (!saving) postNui('saveConfig', currentCoords);
});
cancelButton.addEventListener('click', () => {
    if (!saving) postNui('cancelConfig');
});
window.addEventListener('keydown', event => {
    if (!editorOpen || saving) return;
    if (event.ctrlKey && event.key.toLowerCase() === 'z') {
        event.preventDefault();
        restoreHistory(historyIndex - 1);
    } else if (event.ctrlKey && event.key.toLowerCase() === 'y') {
        event.preventDefault();
        restoreHistory(historyIndex + 1);
    } else if (event.key === 'Enter') {
        event.preventDefault();
        if (event.target.classList.contains('axis-number')) {
            const axis = event.target.id.replace('input-', '');
            currentCoords[axis] = clampAxis(axis, event.target.value);
            updateDisplays();
            recordHistory();
        }
        postNui('saveConfig', currentCoords);
    } else if (event.key === 'Escape') {
        event.preventDefault();
        postNui('cancelConfig');
    }
});
