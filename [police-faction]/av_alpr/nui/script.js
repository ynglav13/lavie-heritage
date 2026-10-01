let currentScale = localStorage.getItem('av_alpr_scale') ? parseFloat(localStorage.getItem('av_alpr_scale')) : 1.0;
let posX = localStorage.getItem('av_alpr_x') ? localStorage.getItem('av_alpr_x') : '20px';
let posY = localStorage.getItem('av_alpr_y') ? localStorage.getItem('av_alpr_y') : '20px';

const container = document.getElementById("container");
container.style.transform = `scale(${currentScale})`;
container.style.left = posX;
container.style.top = posY;

container.addEventListener('wheel', (e) => {
    if (e.deltaY < 0) {
        currentScale = Math.min(1.5, currentScale + 0.05);
    } else {
        currentScale = Math.max(0.5, currentScale - 0.05);
    }
    container.style.transform = `scale(${currentScale})`;
    localStorage.setItem('av_alpr_scale', currentScale);
});

let isDragging = false;
let dragOffsetX = 0;
let dragOffsetY = 0;
const header = document.getElementById("header-drag");

header.addEventListener('mousedown', (e) => {
    isDragging = true;
    const rect = container.getBoundingClientRect();
    dragOffsetX = e.clientX - rect.left;
    dragOffsetY = e.clientY - rect.top;
    header.style.cursor = 'grabbing';
});

window.addEventListener('mousemove', (e) => {
    if (isDragging) {
        let newLeft = e.clientX - dragOffsetX;
        let newTop = e.clientY - dragOffsetY;
        container.style.left = newLeft + 'px';
        container.style.top = newTop + 'px';
    }
});

window.addEventListener('mouseup', () => {
    if (isDragging) {
        isDragging = false;
        header.style.cursor = 'grab';
        localStorage.setItem('av_alpr_x', container.style.left);
        localStorage.setItem('av_alpr_y', container.style.top);
    }
});

const radarContainer = document.getElementById("radar-container");
let radarPosX = localStorage.getItem('av_radar_x') ? localStorage.getItem('av_radar_x') : '20px';
let radarPosY = localStorage.getItem('av_radar_y') ? localStorage.getItem('av_radar_y') : 'calc(100% - 200px)';
let radarScale = localStorage.getItem('av_radar_scale') ? parseFloat(localStorage.getItem('av_radar_scale')) : 1.0;
radarContainer.style.left = radarPosX;
radarContainer.style.top = radarPosY;
radarContainer.style.transform = `scale(${radarScale})`;

radarContainer.addEventListener('wheel', (e) => {
    if (e.deltaY < 0) {
        radarScale = Math.min(1.5, radarScale + 0.05);
    } else {
        radarScale = Math.max(0.5, radarScale - 0.05);
    }
    radarContainer.style.transform = `scale(${radarScale})`;
    localStorage.setItem('av_radar_scale', radarScale);
});

let isRadarDragging = false;
let radarDragOffsetX = 0;
let radarDragOffsetY = 0;
const radarDevice = document.querySelector(".radar-device");

radarDevice.addEventListener('mousedown', (e) => {
    if (e.target.closest('button')) return;
    isRadarDragging = true;
    const rect = radarContainer.getBoundingClientRect();
    radarDragOffsetX = e.clientX - rect.left;
    radarDragOffsetY = e.clientY - rect.top;
    radarDevice.style.cursor = 'grabbing';
});

window.addEventListener('mousemove', (e) => {
    if (isRadarDragging) {
        let newLeft = e.clientX - radarDragOffsetX;
        let newTop = e.clientY - radarDragOffsetY;
        radarContainer.style.left = newLeft + 'px';
        radarContainer.style.top = newTop + 'px';
    }
});

window.addEventListener('mouseup', () => {
    if (isRadarDragging) {
        isRadarDragging = false;
        radarDevice.style.cursor = 'grab';
        localStorage.setItem('av_radar_x', radarContainer.style.left);
        localStorage.setItem('av_radar_y', radarContainer.style.top);
    }
});

const remoteContainer = document.getElementById("remote-container");
let remotePosX = localStorage.getItem('av_remote_x') ? localStorage.getItem('av_remote_x') : '100px';
let remotePosY = localStorage.getItem('av_remote_y') ? localStorage.getItem('av_remote_y') : '30%';
let remoteScale = localStorage.getItem('av_remote_scale') ? parseFloat(localStorage.getItem('av_remote_scale')) : 1.0;
remoteContainer.style.left = remotePosX;
remoteContainer.style.top = remotePosY;
remoteContainer.style.transform = `translateY(-50%) scale(${remoteScale})`;

remoteContainer.addEventListener('wheel', (e) => {
    if (e.deltaY < 0) {
        remoteScale = Math.min(1.5, remoteScale + 0.05);
    } else {
        remoteScale = Math.max(0.5, remoteScale - 0.05);
    }
    remoteContainer.style.transform = `translateY(-50%) scale(${remoteScale})`;
    localStorage.setItem('av_remote_scale', remoteScale);
});

let isRemoteDragging = false;
let remoteDragOffsetX = 0;
let remoteDragOffsetY = 0;
const remoteDevice = document.querySelector(".remote-device");

remoteDevice.addEventListener('mousedown', (e) => {
    if (e.target.closest('button')) return;
    isRemoteDragging = true;
    const rect = remoteContainer.getBoundingClientRect();
    remoteDragOffsetX = e.clientX - rect.left;
    remoteDragOffsetY = e.clientY - rect.top;
    remoteDevice.style.cursor = 'grabbing';
});

window.addEventListener('mousemove', (e) => {
    if (isRemoteDragging) {
        let newLeft = e.clientX - remoteDragOffsetX;
        let newTop = e.clientY - remoteDragOffsetY;
        remoteContainer.style.left = newLeft + 'px';
        remoteContainer.style.top = newTop + 'px';
    }
});

window.addEventListener('mouseup', () => {
    if (isRemoteDragging) {
        isRemoteDragging = false;
        remoteDevice.style.cursor = 'grab';
        localStorage.setItem('av_remote_x', remoteContainer.style.left);
        localStorage.setItem('av_remote_y', remoteContainer.style.top);
    }
});

document.querySelectorAll(".remote-btn").forEach(btn => {
    btn.addEventListener('click', (e) => {
        const btnId = btn.id.replace('btn-rc-', '').replace(/-/g, '_');
        fetch(`https://${GetParentResourceName()}/remote_click`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
            },
            body: JSON.stringify({ button: btnId })
        });
    });
});

window.addEventListener('keyup', (e) => {
    if (e.key === "Escape") {
        if (document.getElementById("remote-container").style.display !== "none") {
            fetch(`https://${GetParentResourceName()}/remote_click`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json; charset=UTF-8',
                },
                body: JSON.stringify({ button: 'close' })
            });
        }
        if (document.getElementById("edit-controls").style.display !== "none") {
            document.getElementById("edit-controls").style.display = "none";
            fetch(`https://${GetParentResourceName()}/closeEditMode`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json; charset=UTF-8',
                },
                body: JSON.stringify({})
            });
        }
    }
});

document.getElementById("radar-pwr-btn").addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/remote_click`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify({ button: 'power' })
    });
});

document.getElementById("btn-scale-up").addEventListener('click', () => {
    currentScale += 0.05;
    container.style.transform = `scale(${currentScale})`;
    localStorage.setItem('av_alpr_scale', currentScale);
});

document.getElementById("btn-scale-down").addEventListener('click', () => {
    if (currentScale > 0.5) {
        currentScale -= 0.05;
        container.style.transform = `scale(${currentScale})`;
        localStorage.setItem('av_alpr_scale', currentScale);
    }
});

document.getElementById("btn-save").addEventListener('click', () => {
    document.getElementById("edit-controls").style.display = "none";
    fetch(`https://${GetParentResourceName()}/closeEditMode`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify({})
    });
});

let lastScannedData = null;
let selectedLogData = null;
const DEFAULT_PLATE_INDEX = 0;
const AVAILABLE_PLATE_INDICES = new Set([0, 1, 2, 3, 4, 5]);

window.addEventListener('message', function(event) {
    const item = event.data;

    if (item.type === "ui") {
        document.getElementById("container").style.display = item.display ? "flex" : "none";
        if (!item.display) {
            document.getElementById("edit-controls").style.display = "none";
            if (document.getElementById("remote-container").style.display === "none") {
                fetch(`https://${GetParentResourceName()}/closeEditMode`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json; charset=UTF-8',
                    },
                    body: JSON.stringify({})
                });
            }
        }
    }
    else if (item.type === "radar_ui") {
        document.getElementById("radar-container").style.display = item.display ? "flex" : "none";
    }
    else if (item.type === "remote_ui") {
        document.getElementById("remote-container").style.display = item.display ? "block" : "none";
    }
    else if (item.type === "radar_update") {
        updateRadarDisplay(item.data);
    }
    else if (item.type === "enterEditMode") {
        document.getElementById("edit-controls").style.display = "flex";
    }
    else if (item.type === "update") {
        lastScannedData = item.data;
        updateSelectedVehiclePanel(item.data);
        updateCameraPlateVisual(item.data);
    }
    else if (item.type === "updateOwner") {
        document.getElementById("selected-owner").innerText = item.owner;
        updateOwnerPhoto(item.photo);
        updateFlags(item.flags);
        if (lastScannedData && lastScannedData.plate === item.plate) {
            lastScannedData.owner = item.owner;
            lastScannedData.photo = item.photo;
            lastScannedData.flags = item.flags;
        }
        if (selectedLogData && selectedLogData.plate === item.plate) {
            selectedLogData.owner = item.owner;
            selectedLogData.photo = item.photo;
            selectedLogData.flags = item.flags;
        }
    }
    else if (item.type === "lock") {
        const panel = document.querySelector(".selected-vehicle-panel");
        if (panel) panel.classList.add("locked");
        
        if (lastScannedData) {
            addLog(lastScannedData);
            selectLogEntry(lastScannedData);
        }
    }
    else if (item.type === "unlock") {
        const panel = document.querySelector(".selected-vehicle-panel");
        if (panel) panel.classList.remove("locked");
    }
    else if (item.type === "clearLog") {
        document.getElementById("log-list").innerHTML = "";
        selectedLogData = null;
        updateSelectedVehiclePanel({});
        updateSelectedPlateVisual({});
    }
    else if (item.type === "resetPosition") {
        resetPositions();
    }
});

function resetPositions() {
    localStorage.removeItem('av_alpr_x');
    localStorage.removeItem('av_alpr_y');
    localStorage.removeItem('av_alpr_scale');

    localStorage.removeItem('av_radar_x');
    localStorage.removeItem('av_radar_y');
    localStorage.removeItem('av_radar_scale');

    localStorage.removeItem('av_remote_x');
    localStorage.removeItem('av_remote_y');
    localStorage.removeItem('av_remote_scale');

    currentScale = 1.0;
    posX = '20px';
    posY = '20px';
    container.style.left = '20px';
    container.style.top = '20px';
    container.style.transform = 'scale(1.0)';

    radarScale = 1.0;
    radarPosX = '20px';
    radarPosY = 'calc(100% - 200px)';
    radarContainer.style.left = '20px';
    radarContainer.style.top = 'calc(100% - 200px)';
    radarContainer.style.transform = 'scale(1.0)';

    remoteScale = 1.0;
    remotePosX = '100px';
    remotePosY = '30%';
    remoteContainer.style.left = '100px';
    remoteContainer.style.top = '30%';
    remoteContainer.style.transform = 'translateY(-50%) scale(1.0)';
}

function updateRadarDisplay(data) {
    const pwrBtn = document.getElementById("radar-pwr-btn");
    
    if (!data.power) {
        pwrBtn.classList.remove("active");
        
        document.querySelectorAll(".radar-led-display").forEach(el => el.classList.remove("active"));
        document.querySelectorAll(".indicator-label").forEach(el => el.classList.remove("active"));
        document.querySelectorAll(".indicator-arrow").forEach(el => el.classList.remove("active"));
        
        document.getElementById("front-target-val").innerText = "";
        document.getElementById("front-fast-val").innerText = "";
        document.getElementById("rear-target-val").innerText = "";
        document.getElementById("rear-fast-val").innerText = "";
        document.getElementById("patrol-speed-val").innerText = "";
        return;
    }
    
    pwrBtn.classList.add("active");
    
    document.querySelectorAll(".radar-led-display").forEach(el => el.classList.add("active"));
    
    document.getElementById("front-target-val").innerText = formatSpeed(data.frontTarget);
    let frontFastDisp = (data.frontFast !== -1) ? data.frontFast : data.frontLock;
    document.getElementById("rear-target-val").innerText = formatSpeed(data.rearTarget);
    let rearFastDisp = (data.rearFast !== -1) ? data.rearFast : data.rearLock;
    document.getElementById("front-fast-val").innerText = formatSpeed(frontFastDisp);
    document.getElementById("rear-fast-val").innerText = formatSpeed(rearFastDisp);
    document.getElementById("patrol-speed-val").innerText = formatSpeed(data.patrolSpeed);
    
    setIndicatorActive("ind-front-same", data.frontSame);
    setIndicatorActive("ind-front-opp", data.frontOpp);
    setIndicatorActive("ind-front-xmit", data.frontXmit);
    
    setIndicatorActive("ind-rear-same", data.rearSame);
    setIndicatorActive("ind-rear-opp", data.rearOpp);
    setIndicatorActive("ind-rear-xmit", data.rearXmit);
    
    const frontArrows = document.querySelectorAll(".front-row .indicator-arrow");
    const rearArrows = document.querySelectorAll(".rear-row .indicator-arrow");
    
    frontArrows[0].classList.toggle("active", data.frontDir === "approaching");
    frontArrows[1].classList.toggle("active", data.frontDir === "receding");
    
    rearArrows[0].classList.toggle("active", data.rearDir === "receding");
    rearArrows[1].classList.toggle("active", data.rearDir === "approaching");
}

function formatSpeed(speed) {
    if (speed === undefined || speed === null || speed === false || speed === -1) return "---";
    if (speed === 0) return " 0 ";
    let str = Math.round(speed).toString();
    while (str.length < 3) {
        str = " " + str;
    }
    return str;
}

function setIndicatorActive(id, active) {
    const el = document.getElementById(id);
    if (el) {
        el.classList.toggle("active", !!active);
    }
}

function updateSelectedVehiclePanel(data) {
    document.getElementById("selected-plate").innerText = data.plate || "N/A";
    document.getElementById("selected-color").innerText = data.color || "N/A";
    document.getElementById("selected-model").innerText = data.model || "N/A";
    document.getElementById("selected-owner").innerText = data.owner || "Scanning...";
    updateOwnerPhoto(data.photo);
    updateFlags(data.flags);
}

function updateOwnerPhoto(photoUrl) {
    const photo = document.getElementById("selected-owner-photo");
    const validUrl = typeof photoUrl === "string" && /^https?:\/\//i.test(photoUrl);
    photo.hidden = !validUrl;
    photo.src = validUrl ? photoUrl : "";
}

function updateFlags(flags) {
    const element = document.getElementById("selected-flags");
    const values = Array.isArray(flags) ? flags.filter(Boolean) : [];
    element.innerText = values.length ? values.join(" | ") : "None";
    element.classList.toggle("has-flags", values.length > 0);
}

function updateCameraPlateVisual(data) {
    const visualText = document.getElementById("camera-visual-text");
    visualText.innerText = data.plate || "";

    const idx = normalizePlateIndex(data.plateIndex);
    const visualContainer = document.getElementById("camera-plate-display").querySelector(".plate-visual");
    setPlateBackground(visualContainer, idx);

    applyPlateTextColor(visualText, idx);
}

function updateSelectedPlateVisual(data) {
    const visualText = document.getElementById("selected-visual-text");
    visualText.innerText = data.plate || "";
    
    const idx = normalizePlateIndex(data.plateIndex);
    const visualContainer = document.getElementById("selected-plate-display").querySelector(".plate-visual");
    setPlateBackground(visualContainer, idx);

    applyPlateTextColor(visualText, idx);
}

function normalizePlateIndex(value) {
    const index = Number(value);
    return Number.isInteger(index) && AVAILABLE_PLATE_INDICES.has(index) ? index : DEFAULT_PLATE_INDEX;
}

function setPlateBackground(container, index) {
    const resolvedIndex = normalizePlateIndex(index);
    const requestToken = `${resolvedIndex}:${Date.now()}:${Math.random()}`;
    const requestedUrl = `plates/${resolvedIndex}.png`;

    container.dataset.plateRequest = requestToken;

    const probe = new Image();
    probe.onload = () => {
        if (container.dataset.plateRequest === requestToken) {
            container.style.backgroundImage = `url('${requestedUrl}')`;
        }
    };
    probe.onerror = () => {
        if (container.dataset.plateRequest === requestToken) {
            container.style.backgroundImage = `url('plates/${DEFAULT_PLATE_INDEX}.png')`;
        }
    };
    probe.src = requestedUrl;
}

function applyPlateTextColor(element, idx) {
    element.className = "plate-text";
    switch(idx) {
        case 0:
            element.classList.add("plate-text-default-blue");
            break;
        case 1:
            element.classList.add("plate-text-orange");
            break;
        case 2:
            element.classList.add("plate-text-yellow");
            break;
        case 3:
            element.classList.add("plate-text-default-blue");
            break;
        case 4:
            element.classList.add("plate-text-default-blue");
            break;
        case 5:
            element.classList.add("plate-text-default-blue");
            break;
        default:
            element.classList.add("plate-text-default-blue");
    }
}

function addLog(data) {
    const list = document.getElementById("log-list");
    const div = document.createElement("div");
    div.className = "log-item";
    
    const timeStr = new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit', second:'2-digit'});

    div.innerHTML = `
        <span style="width: 35%">${data.plate || "N/A"}</span>
        <span style="width: 30%">${data.color || "Unknown"}</span>
        <span style="width: 35%">${timeStr}</span>
    `;

    div.dataset.logData = JSON.stringify(data);

    div.addEventListener('click', function() {
        selectLogEntry(JSON.parse(this.dataset.logData));
    });

    list.prepend(div);
    
    if(list.children.length > 20) {
        list.removeChild(list.lastChild);
    }
}

function selectLogEntry(data) {
    selectedLogData = data;
    updateSelectedVehiclePanel(data);
    updateSelectedPlateVisual(data);
}
