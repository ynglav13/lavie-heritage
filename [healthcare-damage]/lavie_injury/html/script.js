const selector = document.getElementById('seat-selector');
const targetLabel = document.getElementById('seat-target');
const seatsContainer = document.getElementById('passenger-seats');
const emptyLabel = document.getElementById('seat-empty');
const closeButton = document.getElementById('seat-close');

let activeVehicleNetworkId = null;
let activeTargetId = null;
let activeIsDragging = false;

const getResourceName = () => {
    try {
        if (typeof GetParentResourceName === 'function') {
            return GetParentResourceName();
        }
    } catch (_) {}
    return 'lavie_injury';
};

const postNui = async (endpoint, payload = {}) => {
    try {
        await fetch(`https://${getResourceName()}/${endpoint}`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: JSON.stringify(payload)
        });
    } catch (_) {
    }
};

const hideSelector = () => {
    selector.style.display = 'none';
    selector.classList.add('hidden');
    selector.setAttribute('aria-hidden', 'true');
    seatsContainer.replaceChildren();
    activeVehicleNetworkId = null;
    activeTargetId = null;
    activeIsDragging = false;
};

const closeSelector = () => {
    if (selector.classList.contains('hidden') || selector.style.display === 'none') {
        return;
    }

    hideSelector();
    postNui('closeUI');
};

const isSeatFreeValue = (val) => {
    if (val === true || val === 1 || val === 'true') return true;
    if (val === false || val === 0 || val === 'false') return false;
    return true;
};

const buildSeat = (seatIndex, isFree) => {
    const button = document.createElement('button');
    const free = isSeatFreeValue(isFree);

    button.type = 'button';
    button.className = 'seat';
    button.dataset.seat = String(seatIndex);
    button.textContent = seatIndex === 0 ? 'Ghế Phụ' : `Ghế ${seatIndex}`;

    if (!free) {
        button.disabled = true;
        button.classList.add(isFree === false || isFree === 0 || isFree === 'false' ? 'occupied' : 'disabled');
    }

    return button;
};

const showSelector = (data) => {
    activeVehicleNetworkId = Number(data.vehNet);
    activeTargetId = Number(data.targetId);
    activeIsDragging = data.isDragging === true;
    targetLabel.textContent = `Nạn nhân ID: ${activeTargetId}`;
    seatsContainer.replaceChildren();

    const maximumPassengers = Math.max(0, Number(data.maxPassengers) || 0);
    const seats = data.seats && typeof data.seats === 'object' ? data.seats : {};

    for (let seat = 0; seat < maximumPassengers; seat += 1) {
        const rawFree = seats[String(seat)] !== undefined ? seats[String(seat)] : seats[seat];
        seatsContainer.appendChild(buildSeat(seat, rawFree));
    }

    emptyLabel.classList.toggle('hidden', maximumPassengers > 0);

    selector.style.display = 'grid';
    selector.classList.remove('hidden');
    selector.setAttribute('aria-hidden', 'false');
    closeButton.focus();
};

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'openSeatSelection') {
        showSelector(data);
    } else if (data.action === 'closeSeatSelection') {
        hideSelector();
    }
});

seatsContainer.addEventListener('click', (event) => {
    const seat = event.target.closest('.seat');

    if (!seat || seat.disabled || activeTargetId === null || activeVehicleNetworkId === null || isNaN(activeTargetId) || isNaN(activeVehicleNetworkId)) {
        return;
    }

    const payload = {
        targetId: activeTargetId,
        vehNet: activeVehicleNetworkId,
        seatIndex: Number(seat.dataset.seat),
        isDragging: activeIsDragging
    };

    hideSelector();
    postNui('selectSeat', payload);
});

closeButton.addEventListener('click', closeSelector);

document.addEventListener('keyup', (event) => {
    if (event.key === 'Escape') {
        closeSelector();
    }
});

hideSelector();