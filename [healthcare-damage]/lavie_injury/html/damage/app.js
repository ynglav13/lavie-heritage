const reportState =
{
    open: false
};

function getDamageResourceName()
{
    try
    {
        if(typeof GetParentResourceName === "function")
        {
            return GetParentResourceName();
        }
    }
    catch(_)
    {
    }

    return "lavie_injury";
}

function postDamageNui(endpoint, payload)
{
    return fetch(`https://${getDamageResourceName()}/${endpoint}`,
    {
        method: "POST",
        headers:
        {
            "Content-Type": "application/json; charset=UTF-8"
        },
        body: JSON.stringify(payload || {})
    }).catch(function () {});
}

const elements = {};
const severityRank =
{
    low: 1,
    med: 2,
    high: 3
};

document.addEventListener("DOMContentLoaded", function ()
{
    elements.container = document.querySelector(".container");
    elements.sheet = document.querySelector(".report-sheet");
    elements.damageList = document.querySelector("#damage-list");
    elements.totalInjuries = document.querySelector("#total-injuries");
    elements.patientStatus = document.querySelector("#patient-status");
    elements.highestSeverity = document.querySelector("#highest-severity");
    elements.findingsSummary = document.querySelector("#findings-summary");
    elements.targetName = document.querySelector("#target-name");
    elements.examTime = document.querySelector("#exam-time");
    elements.zoneTags = document.querySelector("#zone-tags");
    elements.bodyZones = Array.from(document.querySelectorAll(".zone-marker"));
    elements.container.style.display = "none";

    resetReport();
});

window.addEventListener("message", function (event)
{
    const data = event.data || {};

    if(data.clear === true)
    {
        resetReport();
    }

    if(data.display === true)
    {
        openReport(data);
    }

    if(data.display === false)
    {
        closeUI();
    }
});

function openReport(data)
{
    reportState.open = true;
    elements.container.style.display = "flex";
    elements.sheet.classList.remove("animate-out");
    elements.sheet.classList.add("animate-in");

    const targetName = data.targetName || "Không Xác Định";
    const damages = Array.isArray(data.damages) ? data.damages : [];
    const now = Number(data.timestamp) || Math.floor(Date.now() / 1000);
    const injuryStatus = normalizeInjuryStatus(data.injuryStatus);

    elements.targetName.textContent = targetName;
    elements.examTime.textContent = formatClock(now);

    renderDamages(damages, now, injuryStatus);
}

function renderDamages(damages, now, injuryStatus)
{
    const affectedZones = {};

    let highestSeverity = getSeverity(0, false);
    let highestDamage = 0;

    elements.damageList.replaceChildren();
    elements.zoneTags.replaceChildren();

    clearBodyMap();

    if(!damages.length)
    {
        elements.totalInjuries.textContent = "0";
        elements.highestSeverity.textContent = "Không Có";
        elements.patientStatus.textContent = getInjuryStatusLabel(injuryStatus);
        elements.findingsSummary.textContent = "Không Có Dữ Liệu";
        elements.sheet.classList.remove("is-critical");
        elements.damageList.append(createEmptyState());
        elements.zoneTags.append(createZoneTag("Không Có Vùng Bị Thương", "low"));
        return;
    }

    damages.forEach(function (value, index)
    {
        const damage = parseFloat(value.damage) || 0;
        const severity = getSeverity(damage, value.warning);
        const bone = value.bone || "Không xác định";
        const caused = value.caused || "Không xác định";
        const timeText = value.timestamp ? formatRelativeTime(now - Number(value.timestamp)) : "--";
        const zone = getBodyZone(bone);

        if(damage > highestDamage || severityRank[severity.key] > severityRank[highestSeverity.key])
        {
            highestDamage = damage;
            highestSeverity = severity;
        }

        markBodyZone(zone.selector, severity.key);

        rememberZone(affectedZones, zone.label, severity);

        elements.damageList.append(createDamageRow(
        {
            index,
            bone,
            caused,
            damage,
            severity,
            timeText
        }));
    });

    renderZoneTags(affectedZones);

    elements.totalInjuries.textContent = String(damages.length);
    elements.highestSeverity.textContent = `${highestSeverity.label} ${highestDamage.toFixed(0)}%`;
    elements.patientStatus.textContent = getInjuryStatusLabel(injuryStatus);
    elements.findingsSummary.textContent = `${damages.length} vết thương nặng nhất ${highestDamage.toFixed(0)}%`;
    elements.sheet.classList.toggle("is-critical", injuryStatus === 3);
}

function createDamageRow(data)
{
    const row = document.createElement("div");

    row.className = `list-item ${data.severity.className}`;
    row.style.animationDelay = `${data.index * 0.025}s`;

    const id = document.createElement("div");

    id.className = "item-id";
    id.textContent = String(data.index + 1).padStart(2, "0");

    const bone = document.createElement("div");

    bone.className = "item-bone";
    bone.title = data.bone;
    bone.textContent = data.bone;

    const cause = document.createElement("div");

    cause.className = "item-cause";
    cause.title = data.caused;
    cause.textContent = data.caused;

    const damage = document.createElement("div");

    damage.className = "item-damage";

    const pill = document.createElement("span");

    pill.className = `severity-pill ${data.severity.className}`;
    pill.textContent = `${data.severity.label} ${data.damage.toFixed(0)}%`;

    damage.append(pill);

    const time = document.createElement("div");

    time.className = "item-time";
    time.title = data.timeText;
    time.textContent = data.timeText;

    row.append(id, bone, cause, damage, time);
    return row;
}

function createEmptyState()
{
    const empty = document.createElement("div");

    empty.className = "empty-state";
    empty.textContent = "Không Có Vết Thương Nào Được Ghi Nhận";
    return empty;
}

function getSeverity(damage, warning)
{
    if(warning || damage >= 50)
    {
        return {
            key: "high",
            className: "damage-high",
            label: "Nặng"
        };
    }

    if(damage >= 20)
    {
        return {
            key: "med",
            className: "damage-med",
            label: "Vừa"
        };
    }
    return {
        key: "low",
        className: "damage-low",
        label: "Nhẹ"
    };
}

function normalizeInjuryStatus(value)
{
    if(value === null || value === undefined || value === "")
    {
        return null;
    }

    const status = Number(value);

    if(!Number.isInteger(status) || status < 0 || status > 3)
    {
        return null;
    }

    return status;
}

function getInjuryStatusLabel(status)
{
    if(status === 3)
    {
        return "Đã Chết";
    }

    if(status === 2)
    {
        return "Bị Thương";
    }

    if(status === 1)
    {
        return "Bị Thương Nhẹ";
    }

    if(status === 0)
    {
        return "Ổn";
    }

    return "Không Xác Định";
}

function clearBodyMap()
{
    elements.bodyZones.forEach(function (zone)
    {
        zone.classList.remove("active-low", "active-med", "active-high");
    });
}

function getBodyZone(bone)
{
    const normalized = normalizeText(bone);

    if(hasAny(normalized, ["dau", "mat", "head", "face", "eye", "moi", "ham", "cam"]))
    {
        return {
            selector: "#zone-head",
            label: "Đầu"
        };
    }

    if(hasAny(normalized, ["co", "gai", "neck"]))
    {
        return {
            selector: "#zone-neck",
            label: "Cổ"
        };
    }

    if(hasAny(normalized, ["tay trai", "vai trai", "khuu tay trai", "canh tay trai", "left arm", "left hand"]))
    {
        return {
            selector: "#zone-left-arm",
            label: "Tay Trái"
        };
    }

    if(hasAny(normalized, ["tay phai", "vai phai", "khuu tay phai", "canh tay phai", "right arm", "right hand"]))
    {
        return {
            selector: "#zone-right-arm",
            label: "Tay Phải"
        };
    }

    if(hasAny(normalized, ["chan trai", "goi trai", "dui trai", "left leg", "left foot"]))
    {
        return {
            selector: "#zone-left-leg",
            label: "Chân Trái"
        };
    }

    if(hasAny(normalized, ["chan phai", "goi phai", "dui phai", "right leg", "right foot"]))
    {
        return {
            selector: "#zone-right-leg",
            label: "Chân Phải"
        };
    }
    return {
        selector: "#zone-torso",
        label: "Thân"
    };
}

function markBodyZone(selector, severity)
{
    const zone = document.querySelector(selector);

    if(!zone)
    {
        return;
    }

    if(zone.classList.contains("active-high"))
    {
        return;
    }

    if(zone.classList.contains("active-med") && severity === "low")
    {
        return;
    }

    zone.classList.remove("active-low", "active-med", "active-high");
    zone.classList.add(`active-${severity}`);
}

function rememberZone(zones, label, severity)
{
    if(!zones[label] || severityRank[severity.key] > severityRank[zones[label].key])
    {
        zones[label] = severity;
    }
}

function renderZoneTags(zones)
{
    Object.keys(zones).forEach(function (label)
    {
        elements.zoneTags.append(createZoneTag(label, zones[label].key));
    });
}

function createZoneTag(label, severity)
{
    const tag = document.createElement("span");

    tag.className = `zone-tag ${getSeverityClass(severity)}`;
    tag.textContent = label;
    return tag;
}

function getSeverityClass(severity)
{
    if(severity === "high")
    {
        return "damage-high";
    }

    if(severity === "med")
    {
        return "damage-med";
    }
    return "damage-low";
}

function hasAny(value, needles)
{
    return needles.some(function (needle)
    {
        return value.includes(needle);
    });
}

function formatRelativeTime(seconds)
{
    if(!Number.isFinite(seconds) || seconds < 0)
    {
        return "--";
    }

    if(seconds < 60)
    {
        return "vừa xong";
    }

    const minutes = Math.floor(seconds / 60);

    if(minutes < 60)
    {
        return `${minutes} phút trước`;
    }

    const hours = Math.floor(minutes / 60);

    if(hours < 24)
    {
        return `${hours} giờ trước`;
    }

    const days = Math.floor(hours / 24);
    return `${days} ngày trước`;
}

function formatClock(timestamp)
{
    const date = new Date(timestamp * 1000);
    return date.toLocaleTimeString("vi-VN",
    {
        hour: "2-digit",
        minute: "2-digit"
    });
}

function normalizeText(value)
{
    return String(value || "")
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/đ/g, "d");
}

function resetReport() {
    if(!elements.damageList)
    {
        return;
    }

    elements.damageList.replaceChildren();
    elements.zoneTags.replaceChildren();
    elements.totalInjuries.textContent = "0";
    elements.highestSeverity.textContent = "Không Có";
    elements.patientStatus.textContent = "Ổn";
    elements.findingsSummary.textContent = "Không Có Dữ Liệu";
    elements.targetName.textContent = "Không Xác Định";
    elements.examTime.textContent = "--:--";
    elements.sheet.classList.remove("is-critical");

    clearBodyMap();
}

function closeUI()
{
    if(!reportState.open)
    {
        return;
    }

    reportState.open = false;

    elements.sheet.classList.remove("animate-in");
    elements.sheet.classList.add("animate-out");

    setTimeout(function ()
    {
        elements.container.style.display = "none";
    }, 120);
}

document.addEventListener("keyup", function (event)
{
    if(event.key === "Escape" && reportState.open)
    {
        postDamageNui("finish-check");

        closeUI();
    }
});
