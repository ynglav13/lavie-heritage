window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.clear == true) {
        $(".content").empty();
    }
    if (data.display == true) {
        $(".container").css('display', 'flex');
        $(".panel-wrapper").toggleClass('garage-spawn-panel', data.edit === 'garageSpawn');
        $(".panel-wrapper").toggleClass('armory-panel', data.edit === 'armoryMenu');
        
        if (data.edit === 'garageSpawn') {
            $(".search-container").show();
            $(".overlap-icon").html('<i class="fas fa-warehouse"></i>');
            $(".header").empty().append(`
                <div class="title-group">
                    <div class="garage-eyebrow">QUẢN LÝ PHƯƠNG TIỆN</div>
                    <div class="main-title">Garage Faction</div>
                    <div class="sub-title">Theo dõi và sử dụng phương tiện của tổ chức</div>
                </div>
                <div class="header-right">
                    <div class="esc-hint"><span class="key">ESC</span> Đóng</div>
                </div>
            `);
        } else if (data.edit === 'armoryMenu') {
            $(".search-container").show();
            $(".overlap-icon").html('<i class="fa-solid fa-shield-halved"></i>');
            $(".header").empty().append(`
                <div class="title-group">
                    <div class="garage-eyebrow">OX STYLE STORAGE</div>
                    <div class="main-title">Faction Locker</div>
                    <div class="sub-title">Trang bị và kho lưu trữ của tổ chức</div>
                </div>
                <div class="header-right">
                    <div class="esc-hint"><span class="key">ESC</span> Đóng</div>
                </div>
            `);
        } else {
            $(".search-container").hide();
            $(".overlap-icon").html('<i class="fa-solid fa-users-gear"></i>');
        }
    }
    if (data.display == false) {
        $(".container").fadeOut(150);
    }
});

document.addEventListener('DOMContentLoaded', function () {
    $(".container").hide();
    
    $(document).keyup(function(e) {
        if (e.keyCode === 27) {
            if ($("#receipt-container").is(":visible")) {
                payReceipt('decline');
            } else if ($("#receipt-creator-container").is(":visible")) {
                closeReceiptCreator();
            } else {
                CloseMenu();
            }
        }
    });
});

function CloseMenu() {
    if (typeof ResetVarriable === 'function') {
        ResetVarriable();
    }
    $.post('https://factionCore/CloseMenu');
}

function SelectMenu(type, id) {
    $.post('https://factionCore/SelectMenu', JSON.stringify({ type: type, id: id }));
}

window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.edit === 'general' || data.edit === 'members' || data.edit === 'permission' || data.edit === 'rank' || data.edit === 'division' || data.edit === 'garage' || data.edit === 'locker') {
        $(".header").empty()
        $(".header").append(`
            <div class="title-group">
                <div class="main-title">FACTION PANEL</div>
                <div class="sub-title">System Management</div>
            </div>
            <div class="header-right">
                <div class="esc-hint"><span class="key">ESC</span> to close</div>
            </div>
        `)
    }
    if (data.edit === 'select') {
        $(".header").empty()
        $(".header").append(`
            <div class="title-group">
                <div class="main-title">SELECT FACTION</div>
                <div class="sub-title">System Management</div>
            </div>
            <div class="header-right">
                <div class="esc-hint"><span class="key">ESC</span> to close</div>
            </div>
        `)
    }
    if (data.edit === 'bizSelect') {
        $(".header").empty()
        $(".header").append(`
            <div class="title-group">
                <div class="main-title">SELECT BUSINESS</div>
                <div class="sub-title">System Management</div>
            </div>
            <div class="header-right">
                <div class="esc-hint"><span class="key">ESC</span> to close</div>
            </div>
        `)
    }
    if (data.edit === 'bizEdit') {
        $(".header").empty()
        $(".header").append(`
            <div class="title-group">
                <div class="main-title">BUSINESS PANEL</div>
                <div class="sub-title">System Management</div>
            </div>
            <div class="header-right">
                <div class="esc-hint"><span class="key">ESC</span> to close</div>
            </div>
        `)
    }
});

// Receipts custom NUI Logic
var currentVatPercent = 10;

window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.action === "showReceipt") {
        document.getElementById("receipt-shop-name").innerText = data.shopName;
        
        var itemsListContainer = $("#receipt-items-list");
        itemsListContainer.empty();
        
        var items = [];
        try {
            items = JSON.parse(data.description);
        } catch (e) {
            items = [{ name: data.description, price: data.basePrice }];
        }
        
        items.forEach(function(item) {
            var qty = item.qty || 1;
            var totalPrice = item.price * qty;
            itemsListContainer.append(`
                <div class="receipt-row">
                    <span class="receipt-col-desc">${item.name}</span>
                    <span class="receipt-col-qty" style="width: 40px; text-align: center; font-size: 13px;">${qty}</span>
                    <span class="receipt-col-price">$${totalPrice.toLocaleString()}</span>
                </div>
            `);
        });

        document.getElementById("receipt-total-price").innerText = "$" + data.totalAmount.toLocaleString();
        
        $("#receipt-container").fadeIn(150);
    } else if (data.action === "hideReceipt") {
        $("#receipt-container").fadeOut(150);
    } else if (data.action === "openReceiptCreator") {
        document.getElementById("creator-shop-name").innerText = data.shopName;
        
        // VAT removed
        
        $("#creator-items-container").empty();
        addCreatorRow(); // Start with one row
        
        $("#creator-customer-id").empty();
        if (data.nearbyPlayers && data.nearbyPlayers.length > 0) {
            $("#creator-customer-id").append('<option value="">Chọn khách hàng...</option>');
            data.nearbyPlayers.forEach(function(player) {
                $("#creator-customer-id").append(`<option value="${player.id}">${player.name} (${player.id})</option>`);
            });
        } else {
            $("#creator-customer-id").append('<option value="">Không có ai ở gần...</option>');
        }
        
        recalculateCreatorTotals();
        $("#receipt-creator-container").fadeIn(150);
    }
});

function payReceipt(method) {
    $("#receipt-container").fadeOut(150);
    $.post('https://factionCore/payReceipt', JSON.stringify({ method: method }));
}

function addCreatorRow() {
    var rowHtml = `
        <div class="receipt-row creator-item-row" style="margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between;">
            <input type="text" class="item-name-input" placeholder="Tên dịch vụ / sản phẩm..." required style="flex-grow: 1; min-width: 90px; border: none; border-bottom: 1px dashed #222; background: transparent; color: #222; outline: none; font-family: inherit; font-size: 13px; text-align: left; margin-right: 8px;" />
            <input type="number" class="item-qty-input" placeholder="SL" value="1" required min="1" style="width: 40px; text-align: center; border: none; border-bottom: 1px dashed #222; background: transparent; color: #222; outline: none; font-family: inherit; font-size: 13px; margin-right: 8px;" />
            <input type="number" class="item-price-input" placeholder="$0" required min="0" style="width: 95px; text-align: right; border: none; border-bottom: 1px dashed #222; background: transparent; color: #222; outline: none; font-family: inherit; font-size: 13px;" />
            <button class="remove-row-btn" type="button" onclick="removeCreatorRow(this)" style="background: transparent; border: none; color: #e74c3c; cursor: pointer; font-size: 18px; margin-left: 6px; padding: 0 4px; line-height: 1;">×</button>
        </div>
    `;
    $("#creator-items-container").append(rowHtml);
    
    // Bind change/input event to new inputs
    $("#creator-items-container .item-price-input, #creator-items-container .item-qty-input").off("input").on("input", recalculateCreatorTotals);
}

function removeCreatorRow(btn) {
    $(btn).closest(".creator-item-row").remove();
    // Ensure we always have at least one row
    if ($("#creator-items-container .creator-item-row").length === 0) {
        addCreatorRow();
    }
    recalculateCreatorTotals();
}

function recalculateCreatorTotals() {
    var subtotal = 0;
    $("#creator-items-container .creator-item-row").each(function() {
        var qtyVal = parseFloat($(this).find(".item-qty-input").val()) || 1;
        var priceVal = parseFloat($(this).find(".item-price-input").val()) || 0;
        subtotal += (priceVal * qtyVal);
    });
    
    document.getElementById("creator-total-val").innerText = "$" + subtotal.toLocaleString();
}

function submitReceiptCreator() {
    var targetId = parseInt($("#creator-customer-id").val());
    if (!targetId || targetId <= 0) return;

    var items = [];
    var totalBasePrice = 0;
    var valid = true;

    $("#creator-items-container .creator-item-row").each(function() {
        var name = $(this).find(".item-name-input").val() || "";
        var qty = parseFloat($(this).find(".item-qty-input").val()) || 1;
        var price = parseFloat($(this).find(".item-price-input").val()) || 0;

        if (name.trim() === "" || price <= 0 || qty <= 0) {
            valid = false;
            return false;
        }

        items.push({ name: name.trim(), price: price, qty: qty });
        totalBasePrice += (price * qty);
    });

    if (!valid || items.length === 0) return;

    $("#receipt-creator-container").fadeOut(150);
    $.post('https://factionCore/submitReceipt', JSON.stringify({
        targetId: targetId,
        basePrice: totalBasePrice,
        description: JSON.stringify(items)
    }));
}

function closeReceiptCreator() {
    $("#receipt-creator-container").fadeOut(150);
    $.post('https://factionCore/closeReceiptCreator');
}
