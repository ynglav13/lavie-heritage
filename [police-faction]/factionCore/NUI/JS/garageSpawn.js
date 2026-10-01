
document.addEventListener('DOMContentLoaded', function () {
    $(".container").hide();

    $("#search").on("keyup", function() {
        var searchTerm = $(this).val().toLowerCase();
        $(".garage-item").each(function() {
            var searchable = String($(this).data("search") || '').toLowerCase();
            if (searchable.includes(searchTerm)) {
                $(this).show();
            } else {
                $(this).hide();
            }
        });
        updateVisibleCount();
    });

    $(document).on('click', '.garage-item', function() {
        selectVehicleCard($(this));
    });
});

let currentType = ''
let vehicleCount = 0;

function firstUpper(string) {
    string = String(string || 'Không xác định');
    return string.charAt(0).toUpperCase() + string.slice(1);
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, function(character) {
        return ({'&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'})[character];
    });
}

function updateVisibleCount() {
    let visible = $(".garage-item:visible").length;
    $(".garage-result-count").text(`${visible} phương tiện`);
}

function selectVehicleCard(card) {
    $(".garage-item").removeClass("selected");
    card.addClass("selected");

    let garageId = Number(card.attr('data-garage'));
    let plate = String(card.attr('data-plate'));
    let model = String(card.attr('data-model'));
    let status = Number(card.attr('data-status'));
    
    let textStatus = 'Lấy xe';
    let buttonStatus = 'buttonGreen';
    if (status == 1) {
        textStatus = 'Cất xe';
        buttonStatus = 'buttonSeconds';
    }

    $(".footer").empty().append(`
        <div class="garage-selection-copy">
            <span>Đã chọn</span>
            <strong>${escapeHtml(firstUpper(model))} · ${escapeHtml(plate)}</strong>
        </div>
        <div class="garage-footer-actions">
            <button class="button buttonClosed" onclick="CloseMenu()"><i class="fa-solid fa-xmark"></i> Đóng</button>
            <button class="button ${buttonStatus}" id="garage-primary-action"><i class="fa-solid ${status === 1 ? 'fa-square-parking' : 'fa-key'}"></i> ${textStatus}</button>
        </div>
    `);

    $("#garage-primary-action").one('click', function() {
        Clicked(plate, model, status, garageId);
    });
}

function Clicked(plate, model, status, garageId) {
    $.post('https://factionCore/Clicked', JSON.stringify({plate: plate, model: model, status: String(status), garageId: garageId, type: currentType}));
}

function SelectVehicleMenu(type, garageId) {
    $.post('https://factionCore/SelectVehicleMenu', JSON.stringify({type: type, garageId: garageId}));
}

window.addEventListener('message', function (event) {
    var data = event.data;

    if (data.display == true && data.edit === 'garageSpawn') {
        if (data.reset == true) {
            vehicleCount = 0;
            $("#search").val('');
            $(".content").empty();
            $(".footer").empty().append(`
                <div class="garage-selection-copy">
                    <span>Chưa chọn phương tiện</span>
                    <strong>Chọn một xe để tiếp tục</strong>
                </div>
                <div class="garage-footer-actions">
                    <button class="button buttonClosed" onclick="CloseMenu()"><i class="fa-solid fa-xmark"></i> Đóng</button>
                </div>
            `);
        }

        currentType = data.type;

        let menu = {
            despawn: `<a href="#" class="unactive" onclick="SelectVehicleMenu(0, ${data.garageId})"><i class="fa-solid fa-square-parking"></i><span>Trong garage<small>Sẵn sàng sử dụng</small></span></a>`,
            spawn: `<a href="#" class="unactive" onclick="SelectVehicleMenu(1, ${data.garageId})"><i class="fa-solid fa-route"></i><span>Đang sử dụng<small>Phương tiện bên ngoài</small></span></a>`
        }
        if (data.type == 0) { menu.despawn = `<a href="#" class="active"><i class="fa-solid fa-square-parking"></i><span>Trong garage<small>Sẵn sàng sử dụng</small></span></a>`; }
        if (data.type == 1) { menu.spawn = `<a href="#" class="active"><i class="fa-solid fa-route"></i><span>Đang sử dụng<small>Phương tiện bên ngoài</small></span></a>`; }

        $(".listmenu").empty().append(`
            <div class="garage-location-card">
                <span>GARAGE HIỆN TẠI</span>
                <strong><i class="fa-solid fa-location-dot"></i> Garage ${data.garageId}</strong>
            </div>
            <div class="garage-nav-label">DANH SÁCH XE</div>
            ${menu.despawn}${menu.spawn}
        `);

        if (data.results == true) {
            let modelName = firstUpper(data.model);
            let safeModel = escapeHtml(data.model);
            let safeModelName = escapeHtml(modelName);
            let safePlate = escapeHtml(data.plate);
            let safeDriver = escapeHtml(data.lastDriver || 'Chưa có thông tin');
            let statusText = Number(data.status) === 1 ? 'Đang sử dụng' : 'Trong garage';
            let statusClass = Number(data.status) === 1 ? 'is-out' : 'is-ready';
            vehicleCount += 1;
            $(".content").append(`
                <div class="garage-item" data-search="${safeModel} ${safePlate}" data-garage="${data.garageId}" data-plate="${safePlate}" data-model="${safeModel}" data-status="${data.status}">
                    <div class="item-icon"><i class="fa-solid fa-car-side"></i></div>
                    <div class="item-details">
                        <div class="item-heading">
                            <p class="item-name">${safeModelName}</p>
                            <span class="vehicle-status ${statusClass}"><i class="fa-solid fa-circle"></i>${statusText}</span>
                        </div>
                        <div class="vehicle-metadata">
                            <div><span>Biển số</span><strong class="plate-number">${safePlate}</strong></div>
                            <div><span>Model</span><strong>${safeModel}</strong></div>
                            <div><span>Người dùng cuối</span><strong>${safeDriver}</strong></div>
                        </div>
                    </div>
                    <i class="fa-solid fa-chevron-right item-chevron"></i>
                </div>
            `);
            $(".garage-result-count").text(`${vehicleCount} phương tiện`);
        }

        let nomore = 'N/A';
        if (data.type == 1) { nomore = `đang sử dụng`; }
        if (data.type == 0)   { nomore = `đang trong kho`; }

        if (data.nomore == true) {
            $(".content").empty().append(`
                <div class="message">
                    <div class="message-icon"><i class="fa-solid fa-car-rear"></i></div>
                    <div class="message-title">Chưa có phương tiện</div>
                    <div class="message-text">Không có phương tiện ${nomore} tại garage này.</div>
                </div>
            `);
        }

        if (data.reset == true) {
            $(".search-container").html(`
                <i class="fas fa-search"></i>
                <input type="text" id="search" placeholder="Tìm theo tên xe hoặc biển số...">
                <span class="garage-result-count">0 phương tiện</span>
            `);
            $("#search").off('keyup.garage').on('keyup.garage', function() {
                let searchTerm = $(this).val().toLowerCase();
                $(".garage-item").each(function() {
                    $(this).toggle(String($(this).data('search') || '').toLowerCase().includes(searchTerm));
                });
                updateVisibleCount();
            });
        }
    }
});
