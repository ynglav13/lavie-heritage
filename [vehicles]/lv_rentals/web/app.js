const resource = GetParentResourceName();
const app = document.getElementById('app');
const shell = document.querySelector('.shell');
const rentalView = document.getElementById('rentalView');
const adminView = document.getElementById('adminView');
const title = document.getElementById('title');
const hoursInput = document.getElementById('hours');

let currentStation = null;
let adminData = null;
const carColors =
[
    '#2f80ed',
    '#d9dde4',
    '#f04f4f',
    '#101623',
    '#14b889',
    '#6d4b35'
];

const post = (event, data = {}) => fetch(`https://${resource}/${event}`,
{
    method: 'POST',
    headers:
    {
        'Content-Type': 'application/json; charset=UTF-8'
    },
    body: JSON.stringify(data)
}).then((response) => response.json()).catch((error) => (
{
    ok: false,
    message: `Không thể gửi yêu cầu ${event}: ${error.message}`
}));

const money = (value) => `$${Number(value || 0).toLocaleString('en-US')}`;

function flash(message, type = 'success')
{
    post('notify', { message, type }).catch(() => {});
}

const coordsFromRow = (row) =>
{
    if(!row)
    {
        return { x: 0, y: 0, z: 0, w: 0 };
    }

    const raw = row.coords || row;
    
    if(typeof raw === 'string')
    {
        try
        {
            const parsed = JSON.parse(raw);
            
            if(parsed.w === undefined)
            {
                parsed.w = row.heading || 0;
            }
            return parsed;
        }
        catch
        {
            return { x: 0, y: 0, z: 0, w: row.heading || 0 };
        }
    }

    if(raw.w === undefined)
    {
        raw.w = row.heading || 0;
    }
    return raw;
};

const isChecked = (value) => value === true || value === 1 || value === '1' || value === 'true';
const numericStep = (name) =>
{
    if(['x', 'y', 'z', 'w', 'heading'].includes(name))
    {
        return '0.01';
    }

    if(['deposit', 'pricePerHour'].includes(name))
    {
        return '1';
    }
    return '1';
};

const input = (label, name, value = '', type = 'text') => `
    <label class="field">
        <span>${label}</span>
        <input name="${name}" type="${type}" ${type === 'number' ? `step="${numericStep(name)}"` : ''} value="${value ?? ''}">
    </label>
`;

const check = (label, name, value) => `
    <label class="check">
        <input name="${name}" type="checkbox" ${value ? 'checked' : ''}>
        <span>${label}</span>
    </label>
`;

function show(mode)
{
    app.classList.remove('hidden');
    app.classList.add('is-open');
    
    shell.classList.toggle('admin-mode', mode === 'admin');
    shell.classList.toggle('rental-mode', mode === 'rental');
    
    rentalView.classList.toggle('hidden', mode !== 'rental');
    
    adminView.classList.toggle('hidden', mode !== 'admin');
}

function close()
{
    app.classList.remove('is-open');
    app.classList.add('hidden');
    
    shell.classList.remove('admin-mode', 'rental-mode');
    
    post('close').catch(() => {});
}

function renderRental(station)
{
    currentStation = station;
    
    title.textContent = 'Thuê Phương Tiện';
    document.getElementById('stationCode').textContent = station.code;
    document.getElementById('stationName').value = station.label;
    document.getElementById('stationTitle').textContent = 'Phương Tiện Có Thể Thuê';
    document.getElementById('stationDeposit').value = money(station.deposit || 0);
    
    hoursInput.max = station.maxHours;
    hoursInput.value = 1;

    const grid = document.getElementById('vehicleGrid');

    grid.innerHTML = '';

    station.vehicles.forEach((vehicle, index) =>
    {
        const color = carColors[index % carColors.length];
        const totalDeposit = (station.deposit || 0) + (vehicle.deposit || 0);
        const card = document.createElement('article');
        
        card.className = 'vehicle-card';
        card.innerHTML = `
            <div class="vehicle-media">
                ${vehicle.image ? `<img src="${vehicle.image}" alt="">` : `<div class="car-silhouette" style="--car:${color}"><span>${vehicle.model}</span></div>`}
            </div>
            <button class="heart-btn" type="button" tabindex="-1">♥</button>
            <div class="vehicle-body">
                <div>
                    <p>Dòng Phương Tiện: ${vehicle.model}<span>Hộp Số: Tự Động</span><span>Màu: ${index % 2 === 0 ? 'Xanh' : 'Lục'}</span></p>
                    <h3>${vehicle.label}</h3>
                </div>
                <div class="vehicle-price">
                    <strong>${money(vehicle.pricePerHour)}</strong><span>/ giờ</span>
                </div>
                <div class="vehicle-meta">
                    <span>Phí Cọc ${money(totalDeposit)}</span>
                    <button class="rent-btn" type="button">Thuê Ngay</button>
                </div>
            </div>
        `;
        card.querySelector('.rent-btn').addEventListener('click', async (event) =>
        {
            const button = event.currentTarget;
            
            button.disabled = true;
            button.textContent = 'Đang thuê...';

            let hoursVal = Number(hoursInput.value);
            if (isNaN(hoursVal) || hoursVal < 1 || hoursVal !== Math.floor(hoursVal)) {
                flash('Số giờ thuê phải là số nguyên dương (ví dụ: 1, 2, 3...)', 'error');
                button.disabled = false;
                button.textContent = 'Thuê Ngay';
                return;
            }

            const response = await post('rentVehicle',
            {
                stationId: station.id,
                vehicleId: vehicle.id,
                hours: hoursVal
            });

            if(!response.ok)
            {
                const detail = response.debug ? ` (${JSON.stringify(response.debug)})` : '';
                
                flash(`${response.message || 'Thuê xe thất bại.'}${detail}`, 'error');
                
                button.disabled = false;
                button.textContent = 'Thuê Ngay';
            }
        });

        grid.appendChild(card);
    });

    show('rental');
}

function stationOptions(selected)
{
    return (adminData?.stations || []).map((station) => (
        `<option value="${station.id}" ${Number(selected) === Number(station.id) ? 'selected' : ''}>${station.label}</option>`
    )).join('');
}

function rowForm(className, inner, saveText = 'Lưu')
{
    const kind = className.replace('-form', '');
    return `<form class="${className} glass-row" data-kind="${kind}">${inner}<div class="actions"><button type="submit">${saveText}</button></div></form>`;
}

function bindForms()
{
    document.querySelectorAll('form[data-kind]').forEach((form) =>
    {
        form.addEventListener('submit', async (event) =>
        {
            event.preventDefault();
            
            const kind = form.dataset.kind;
            const data = Object.fromEntries(new FormData(form).entries());
            
            form.querySelectorAll('input[type="checkbox"]').forEach((item) => { data[item.name] = item.checked; });

            ['id', 'stationId', 'maxHours', 'deposit', 'pricePerHour'].forEach((key) =>
            {
                if(data[key] !== undefined && data[key] !== '')
                {
                    data[key] = Number(data[key]);
                }
            });

            if(kind === 'station' || kind === 'spawn')
            {
                data.coords =
                {
                    x: Number(data.x || 0),
                    y: Number(data.y || 0),
                    z: Number(data.z || 0),
                    w: Number(data.w || data.heading || 0)
                };
            }

            const response = await post(kind === 'station' ? 'saveStation' : kind === 'spawn' ? 'saveSpawn' : 'saveVehicle', data);
            
            if(response.ok)
            {
                flash(response.message || `${kind[0].toUpperCase()}${kind.slice(1)} saved.`);
                
                await refreshAdmin();
            }
            else
            {
                flash(response.message || 'Lưu thất bại', 'error');
            }
        });
    });

    document.querySelectorAll('[data-delete]').forEach((button) =>
    {
        button.addEventListener('click', async () =>
        {
            const response = await post(button.dataset.delete,
            {
                id: Number(button.dataset.id)
            });
            
            if(response.ok)
            {
                flash(response.message || 'Đã xóa');
                
                await refreshAdmin();
            }
            else
            {
                flash(response.message || 'Xóa thất bại', 'error');
            }
        });
    });

    document.querySelectorAll('[data-fill-coords]').forEach((button) =>
    {
        button.addEventListener('click', async () =>
        {
            const coords = await post('usePlayerCoords');
            const form = button.closest('form');

            ['x', 'y', 'z', 'w'].forEach((key) =>
            {
                const element = form.querySelector(`[name="${key}"]`);

                if(element)
                {
                    element.value = coords[key] ?? 0;
                }
            });
        });
    });
}

function renderStations()
{
    const rows = (adminData.stations || []).map((station) =>
    {
        const coords = coordsFromRow(station);
        return rowForm('station-form', `
            <input type="hidden" name="id" value="${station.id}">
            ${input('Index', 'code', station.code)}
            ${input('Tên', 'label', station.label)}
            ${input('X', 'x', coords.x, 'number')}
            ${input('Y', 'y', coords.y, 'number')}
            ${input('Z', 'z', coords.z, 'number')}
            ${input('W / Heading', 'w', coords.w ?? station.heading, 'number')}
            ${input('Giờ Thuê Tối Đa', 'maxHours', station.max_hours, 'number')}
            ${input('Tiền Cọc', 'deposit', station.deposit, 'number')}
            ${check('Bật', 'enabled', isChecked(station.enabled))}
            ${check('Blip', 'blip', isChecked(station.blip))}
            <button type="button" class="ghost" data-fill-coords>Tọa Độ Hiện Tại</button>
            <button type="button" class="danger" data-delete="deleteStation" data-id="${station.id}">Xóa</button>
        `);
    }).join('');

    document.getElementById('stationsTab').innerHTML = `
        ${rowForm('station-form', `
            <input type="hidden" name="id" value="">
            ${input('Index', 'code')}
            ${input('Tên', 'label')}
            ${input('X', 'x', 0, 'number')}
            ${input('Y', 'y', 0, 'number')}
            ${input('Z', 'z', 0, 'number')}
            ${input('W / Heading', 'w', 0, 'number')}
            ${input('Giờ Thuê Tối Đa', 'maxHours', 6, 'number')}
            ${input('Tiền Cọc', 'deposit', 0, 'number')}
            ${check('Bật', 'enabled', true)}
            ${check('Blip', 'blip', true)}
            <button type="button" class="ghost" data-fill-coords>Tọa Độ Hiện Tại</button>
        `, 'Create')}
        ${rows}
    `;
}

function renderSpawns()
{
    const rows = (adminData.spawns || []).map((spawn) =>
    {
        const coords = coordsFromRow(spawn);
        return rowForm('spawn-form', `
            <input type="hidden" name="id" value="${spawn.id}">
            <label class="field"><span>Station</span><select name="stationId">${stationOptions(spawn.station_id)}</select></label>
            ${input('X', 'x', coords.x, 'number')}
            ${input('Y', 'y', coords.y, 'number')}
            ${input('Z', 'z', coords.z, 'number')}
            ${input('Heading', 'w', coords.w || spawn.heading, 'number')}
            <button type="button" class="ghost" data-fill-coords>Tọa Độ Hiện Tại</button>
            <button type="button" class="danger" data-delete="deleteSpawn" data-id="${spawn.id}">Xóa</button>
        `);
    }).join('');

    document.getElementById('spawnsTab').innerHTML = `
        ${rowForm('spawn-form', `
            <label class="field"><span>Station</span><select name="stationId">${stationOptions()}</select></label>
            ${input('X', 'x', 0, 'number')}
            ${input('Y', 'y', 0, 'number')}
            ${input('Z', 'z', 0, 'number')}
            ${input('Heading', 'w', 0, 'number')}
            <button type="button" class="ghost" data-fill-coords>Tọa Độ Hiện Tại</button>
        `, 'Create')}
        ${rows}
    `;
}

function renderVehicles()
{
    const rows = (adminData.vehicles || []).map((vehicle) => rowForm('vehicle-form', `
        <input type="hidden" name="id" value="${vehicle.id}">
        <label class="field"><span>Station</span><select name="stationId">${stationOptions(vehicle.station_id)}</select></label>
        ${input('Model', 'model', vehicle.model)}
        ${input('Name', 'label', vehicle.label)}
        ${input('Price/hour', 'pricePerHour', vehicle.price_per_hour, 'number')}
        ${input('Extra deposit', 'deposit', vehicle.deposit, 'number')}
        ${input('Image URL', 'image', vehicle.image || '')}
        ${check('Enabled', 'enabled', isChecked(vehicle.enabled))}
        <button type="button" class="danger" data-delete="deleteVehicle" data-id="${vehicle.id}">Xóa</button>
    `)).join('');

    document.getElementById('vehiclesTab').innerHTML = `
        ${rowForm('vehicle-form', `
            <label class="field"><span>Station</span><select name="stationId">${stationOptions()}</select></label>
            ${input('Model', 'model')}
            ${input('Name', 'label')}
            ${input('Price/hour', 'pricePerHour', 0, 'number')}
            ${input('Extra deposit', 'deposit', 0, 'number')}
            ${input('Image URL', 'image')}
            ${check('Enabled', 'enabled', true)}
        `, 'Create')}
        ${rows}
    `;
}

function renderTables()
{
    document.getElementById('activeTab').innerHTML = `<div class="table">${(adminData.active || []).map((row) => `
        <div><b>${row.plate}</b><span>${row.player_name}</span><span>${row.model}</span><span>${new Date(row.expires_at * 1000).toLocaleString()}</span></div>
    `).join('') || '<p class="empty">Không có phương tiện nào đang được thuê</p>'}</div>`;
}

async function refreshAdmin()
{
    adminData = await post('getAdminData');

    if(adminData.ok)
    {
        renderAdmin(adminData);
    }
}

function renderAdmin(data)
{
    adminData = data || {};
    
    if(!adminData.ok)
    {
        return;
    }
    
    title.textContent = 'Rental Admin';
    
    document.getElementById('statStations').textContent = adminData.stations?.length || 0;
    document.getElementById('statVehicles').textContent = adminData.vehicles?.length || 0;
    document.getElementById('statActive').textContent = adminData.active?.length || 0;
    document.getElementById('statHours').textContent = adminData.hardMaxHours || 0;
    
    renderStations();
    renderSpawns();
    renderVehicles();
    renderTables();
    
    bindForms();
    
    show('admin');
}

document.getElementById('closeBtn').addEventListener('click', close);
document.addEventListener('keydown', (event) =>
{
    if(event.key === 'Escape')
    {
        close();
    }
});

document.querySelectorAll('.tab').forEach((tab) =>
{
    tab.addEventListener('click', () =>
    {
        document.querySelectorAll('.tab').forEach((item) => item.classList.remove('active'));
        document.querySelectorAll('.tab-panel').forEach((panel) => panel.classList.add('hidden'));
        tab.classList.add('active');
        document.getElementById(`${tab.dataset.tab}Tab`).classList.remove('hidden');
    });
});

window.addEventListener('message', (event) =>
{
    const data = event.data || {};
    
    if(data.action === 'openRental')
    {
        renderRental(data.station);
    }

    if(data.action === 'openAdmin')
    {
        show('admin');
    }

    if(data.action === 'adminData')
    {
        renderAdmin(data.data);
    }

    if(data.action === 'close')
    {
        app.classList.remove('is-open');
        app.classList.add('hidden');

        shell.classList.remove('admin-mode', 'rental-mode');
    }
});