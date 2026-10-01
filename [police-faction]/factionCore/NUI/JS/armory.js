document.addEventListener('DOMContentLoaded', function () {
    $(document).on('click', '.armory-item', function() {
        selectArmoryCard($(this));
    });
});

let currentArmoryCategory = '';
let armoryCount = 0;

function escapeArmoryHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, function(character) {
        return ({'&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'})[character];
    });
}

function updateArmoryCount() {
    let visible = $(".armory-item:visible").length;
    $(".garage-result-count").text(`${visible} ô vật phẩm`);
}

function handleArmoryImageError(image) {
    image.style.display = 'none';
    image.parentElement.classList.add('show-fallback');
}

function selectArmoryCard(card) {
    let action = card.data('action');
    let itemData = card.data('itemdata') || {};

    if (action === 'open_stash') {
        $.post('https://factionCore/ArmoryAction', JSON.stringify({
            action: action,
            data: itemData
        }));
        return;
    }

    $(".armory-item").removeClass("selected");
    card.addClass("selected");

    let label = escapeArmoryHtml(itemData.label || 'Vật phẩm');
    let priceText = itemData.price ? ` · $${itemData.price.toLocaleString()}` : '';

        $(".footer").empty().append(`
        <div class="armory-selection-copy">
            <span>ĐÃ CHỌN VẬT PHẨM</span>
            <strong>${label}${priceText}</strong>
        </div>
        <div class="armory-footer-actions">
            <button class="button buttonClosed" onclick="CloseMenu()"><i class="fa-solid fa-xmark"></i> Đóng</button>
            <button class="button buttonConfirm" id="armory-primary-action"><i class="fa-solid fa-arrow-down"></i> Lấy vật phẩm</button>
        </div>
    `);

    $("#armory-primary-action").off('click').on('click', function() {
        $.post('https://factionCore/ArmoryAction', JSON.stringify({
            action: action,
            data: itemData
        }));
    });
}

function SwitchArmoryCategory(category) {
    $.post('https://factionCore/SwitchArmoryCategory', JSON.stringify({ category: category }));
}

window.addEventListener('message', function (event) {
    var data = event.data;

    if (data.display === true && data.edit === 'armoryMenu') {
        if (data.reset === true) {
            armoryCount = 0;
            $("#search").val('');
            $(".content").empty();
            $(".footer").empty();
        }

        currentArmoryCategory = data.category || 'main';

        let menuHtml = '';
        let categories = data.categories || [];
        for (let i = 0; i < categories.length; i++) {
            let cat = categories[i];
            let activeClass = (cat.id === currentArmoryCategory) ? 'active' : 'unactive';
            let onclickAttr = (cat.id === currentArmoryCategory) ? '' : `onclick="SwitchArmoryCategory('${cat.id}')"`;
            menuHtml += `<a href="#" class="${activeClass}" ${onclickAttr}><i class="${cat.icon}"></i><span>${cat.label}<small>${cat.sublabel}</small></span></a>`;
        }

        $(".listmenu").empty().append(`
            <div class="armory-location-card">
                <span>TỦ ĐỒ FACTION</span>
                <strong><i class="fa-solid fa-box-archive"></i> ${escapeArmoryHtml(data.tag || 'FACTION')}</strong>
                <small>Locker #${data.lockerId || 1}</small>
            </div>
            <div class="armory-nav-label">DANH MỤC</div>
            ${menuHtml}
        `);

        if (data.results === true && data.items) {
            for (let i = 0; i < data.items.length; i++) {
                let item = data.items[i];
                armoryCount += 1;

                let safeLabel = escapeArmoryHtml(item.label);
                let safeDesc = escapeArmoryHtml(item.desc || '');
                let imgPath = item.icon ? `nui://ox_inventory/web/images/${encodeURIComponent(item.icon)}.png` : '';
                let priceBadge = item.price ? `<span class="armory-price-badge">$${item.price.toLocaleString()}</span>` : '';
                let imageHtml = imgPath ? `<img src="${imgPath}" alt="" onerror="handleArmoryImageError(this)">` : '';

                let directClass = item.action === 'open_stash' ? ' armory-direct-action' : '';
                let cardElement = $(`
                    <div class="armory-item${directClass}" data-search="${safeLabel} ${safeDesc}">
                        <span class="armory-slot-number">${armoryCount}</span>
                        <div class="armory-img-wrapper">
                            ${imageHtml}
                            <div class="armory-fallback-icon" aria-hidden="true"><i class="fa-solid fa-box-open"></i></div>
                        </div>
                        <div class="armory-item-details">
                            <div class="armory-item-heading">
                                <p class="armory-item-name">${safeLabel}</p>
                                ${priceBadge}
                            </div>
                            <div class="armory-item-desc">${safeDesc}</div>
                        </div>
                        ${item.action === 'open_stash' ? '<span class="armory-open-hint">MỞ</span>' : ''}
                    </div>
                `);

                if (!imgPath) {
                    cardElement.find('.armory-img-wrapper').addClass('show-fallback');
                }

                cardElement.data('action', item.action);
                cardElement.data('itemdata', item);

                $(".content").append(cardElement);
            }
            $(".garage-result-count").text(`${armoryCount} ô vật phẩm`);
        }

        if (data.nomore === true && armoryCount === 0) {
            $(".content").empty().append(`
                <div class="message">
                    <div class="message-icon"><i class="fa-solid fa-box-open"></i></div>
                    <div class="message-title">Không có vật phẩm</div>
                    <div class="message-text">Danh mục này hiện chưa có trang bị nào.</div>
                </div>
            `);
        }

        if (data.reset === true) {
            $(".search-container").html(`
                <i class="fas fa-search"></i>
                <input type="text" id="search" placeholder="Tìm theo tên vật phẩm...">
                <span class="garage-result-count">0 ô vật phẩm</span>
            `);
            $("#search").off('keyup.armory').on('keyup.armory', function() {
                let searchTerm = $(this).val().toLowerCase();
                $(".armory-item").each(function() {
                    $(this).toggle(String($(this).data('search') || '').toLowerCase().includes(searchTerm));
                });
                updateArmoryCount();
            });
        }
    }
});
