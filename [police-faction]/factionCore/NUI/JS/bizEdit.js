let itemSelected = ''
let bizEdit = false
let messData = {
    edit: '',
    type: ''
}

function ResetVarriable() {
    messData.edit = null
    messData.type = null
    bizEdit = false
}

function ClickAddItem() {
    var elements = document.getElementsByClassName("item");
    for(var i = 0; i < elements.length; i++) {
        document.getElementById(elements[i].id).style.backgroundImage = 'linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%)), url(images/items/' + document.getElementById(elements[i].id).item + '.png)';
        document.getElementById(elements[i].id).style.backgroundRepeat = "no-repeat";
        document.getElementById(elements[i].id).style.backgroundPosition = "right";

        document.getElementById(elements[i].id).style.filter = 'grayscale(100%)'
        document.getElementById(elements[i].id).style.opacity = "0.5"
    }
    itemSelected = ''
}

window.addEventListener("input", function() {
    if (bizEdit === true) {
        if (messData.edit === 'bizEdit') {
            if (messData.type == 'item') {
                console.log(document.getElementById("addItem").value)
                if (document.getElementById("addItem").value !== '') {
                    $("#ButtonAddItem").empty()
                    $("#ButtonAddItem").append(`
                        <button class="button buttonConfirm" onclick="AddItem('${document.getElementById("addItem").value}')"></button>
                        <button class="button buttonCancelSel" onclick="AddItem('cancelSelect')"></button>
                    `)
                } else {
                    $("#ButtonAddItem").empty()
                }
        
                if (itemSelected !== '') {
                    if (Number(document.getElementById("editPrice" + itemSelected).value) !== Number(document.getElementById("editPrice" + itemSelected).price)) {
                        let newPrice = document.getElementById("editPrice" + itemSelected).value
                        $(".footer").empty()
                        $(".footer").append(`
                            <a id="ButtonAddItem" class="buttonAddItem"></a>
                            <input id="addItem" class="AddItem" onclick="ClickAddItem()" style="border: 1px solid #13131359; border-radius: 3px;" type="text" placeholder="Thêm vật phẩm" required minlength="5" maxlength="32" size="15" />
                            <button class="button buttonEntered" onclick="RestockItem('${itemSelected}')">Restock</button>
                            <button class="button buttonGreen" onclick="EditItemPrice('${itemSelected}', '${newPrice}')">Thay đổi giá</button>
                            <button class="button buttonRemove" onclick="RemoveItem('${itemSelected}')">Xóa vật phẩm</button>
                            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
                        `)
                    } else {
                        $(".footer").empty()
                        $(".footer").append(`
                            <a id="ButtonAddItem" class="buttonAddItem"></a>
                            <input id="addItem" class="AddItem" onclick="ClickAddItem()" style="border: 1px solid #13131359; border-radius: 3px;" type="text" placeholder="Thêm vật phẩm" required minlength="5" maxlength="32" size="15" />
                            <button class="button buttonEntered" onclick="RestockItem('${itemSelected}')">Restock</button>
                            <button class="button buttonRemove" onclick="RemoveItem('${itemSelected}')">Xóa vật phẩm</button>
                            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
                        `)
                    }
                }
            }
            else if (messData.type == 'advanced') {
                console.log(document.getElementById("editBizOwner").owner)
                if (document.getElementById("editBizOwner").value !== document.getElementById("editBizOwner").owner) {
                    $("#ButtonEditBizOwner").empty()
                    $("#ButtonEditBizOwner").append(`
                        <button class="button buttonConfirm" onclick="EditBizOwner('${document.getElementById("editBizOwner").value}')"></button>
                        <button class="button buttonCancelSel" onclick="EditBizOwner('cancelSelect')"></button>
                    `)
                } else {
                    $("#ButtonEditBizOwner").empty()

                }
            }
        } 
    }
})

function EditBizOwner(owner) {
    $("#ButtonEditBizOwner").empty()
    if (owner !== 'cancelSelect') {
        $.post('https://factionCore/EditBizOwner', JSON.stringify({owner: owner}));
    }
    ResetVarriable()
}

function SetBuyPoint() {
    $.post('https://factionCore/SetBuyPoint');
    ResetVarriable()
}

function SetOrderPoint() {
    $.post('https://factionCore/SetOrderPoint');
}

function SetSafePoint() {
    $.post('https://factionCore/SetSafePoint');
}

function GotoPoint(type) {
    $.post('https://factionCore/GotoPoint', JSON.stringify({type: type}));
    ResetVarriable()
}

function AddItem(itemName) {
    document.getElementById('addItem').value = ''
    $("#ButtonAddItem").empty()
    if (itemName !== 'cancelSelect') {
        $.post('https://factionCore/AddItem', JSON.stringify({itemName: itemName}));
    }
    ResetVarriable()
}

function EditItemPrice(itemName, price) {
    $.post('https://factionCore/EditItemPrice', JSON.stringify({itemName: itemName, price: price}));
    ResetVarriable()
}

function RemoveItem(itemName) {
    if (itemName !== 'cancelSelect') {
        $.post('https://factionCore/RemoveItem', JSON.stringify({itemName: itemName}));
    }
    ResetVarriable()
}

function RestockItem(itemName) {
    if (itemName !== 'cancelSelect') {
        $.post('https://factionCore/RestockItem', JSON.stringify({itemName: itemName}));
    }
    ResetVarriable()
}

function SelectBizItem(item) {
    if (itemSelected !== '') {
        if (Number(document.getElementById("editPrice" + itemSelected).value) !== Number(document.getElementById("editPrice" + itemSelected).price)) {
            document.getElementById("editPrice" + itemSelected).value = document.getElementById("editPrice" + itemSelected).price
        }
    }

    var elements = document.getElementsByClassName("item");
    for(var i = 0; i < elements.length; i++) {
        if (elements[i].id !== item) {
            document.getElementById(elements[i].id).style.backgroundImage = 'linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%)), url(images/items/' + document.getElementById(elements[i].id).item + '.png)';
            document.getElementById(elements[i].id).style.backgroundRepeat = "no-repeat";
            document.getElementById(elements[i].id).style.backgroundPosition = "right";

            document.getElementById(elements[i].id).style.filter = 'grayscale(100%)'
            document.getElementById(elements[i].id).style.opacity = "0.5"
        }
    }

    document.getElementById(item).style.opacity = "1.0"
    document.getElementById(item).style.filter = 'none'
    document.getElementById(item).style.backgroundRepeat = "no-repeat";
    document.getElementById(item).style.backgroundPosition = "right";
    document.getElementById(item).style.backgroundImage = 'linear-gradient(to bottom, rgba(245, 246, 252, 0.253), rgba(33, 163, 238, 0.534)), url(images/items/' + item + '.png)'
    
    itemSelected = item

    $(".footer").empty()
    $(".footer").append(`
        <a id="ButtonAddItem" class="buttonAddItem"></a>
        <input id="addItem" class="AddItem" onclick="ClickAddItem()" style="border: 1px solid #13131359; border-radius: 3px;" type="text" placeholder="Thêm vật phẩm" required minlength="5" maxlength="32" size="15" />
        <button class="button buttonEntered" onclick="RestockItem('${item}')">Restock</button>
        <button class="button buttonRemove" onclick="RemoveItem('${item}')">Xóa vật phẩm</button>
        <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
    `)
}

function SelectBizMenu(type) {
    $.post('https://factionCore/SelectBizMenu', JSON.stringify({type: type}));
    ResetVarriable()
}

function SelectBizMenu(type) {
    $.post('https://factionCore/SelectBizMenu', JSON.stringify({type: type}));
    ResetVarriable()
}

window.addEventListener('message', function (event) {
    var data = event.data;

    if (data.display == true & data.edit == 'bizEdit') {
        bizEdit = true
        messData.type = data.type
        messData.edit = data.edit
        if (data.reset == true) {
            itemSelected = ''
            $(".main-bg").empty()
            $(".main-bg").append(`
                <div class="content">
                </div>
            `);
        }

        if (data.type == 'item') {
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="active">Items</a>
                <a class="unactive" onclick="SelectBizMenu('advanced')">Advanced</a>
            `)

            if (data.results == true) {
                $(".content").append(`
                    <div class="item" id='${data.itemName}' onclick="SelectBizItem('${data.itemName}')" style="background-repeat: no-repeat; background-position: right; background-image: linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%)), url(images/items/${data.itemName}.png);">
                        <p class="item-name">${data.itemName}</p>
                        <p class="item-price">
                            <input class="EditPrice${data.itemName}" type="text" id="editPrice${data.itemName}" placeholder="${data.itemPrice}" required minlength="1" maxlength="5" size="1" />
                            <div class="buttonEditPrice"></div>
                        </p>
                        <p class="item-stock">Stock: ${data.itemStock}</p>
                    </div>
                `);
                document.getElementById("editPrice" + data.itemName).value = data.itemPrice
                document.getElementById("editPrice" + data.itemName).price = data.itemPrice
                document.getElementById(data.itemName).item = data.itemName

            } else {
                $(".main-bg").empty()
                $(".main-bg").append(`
                    <div class="message">
                        <div class="message-text">Chưa có vật phẩm</div>
                    </div>
                `);
            }
            $(".footer").empty()
            $(".footer").append(`
                <a id="ButtonAddItem" class="buttonAddItem"></a>
                <input id="addItem" class="AddItem" onclick="ClickAddItem()" style="border: 1px solid #13131359; border-radius: 3px;" type="text" placeholder="Thêm vật phẩm" required minlength="5" maxlength="32" size="15" />
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `)
        } else if (data.type == 'advanced') {
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectBizMenu('item')">Items</a>
                <a class="active">Advanced</a>
            `)

            $(".main-bg").empty()
            $(".content").empty()
            $(".main-bg").append(`
                <div class="content">
                    <table id="business">
                        <tr>
                            <td>Owner</td>
                            <td>
                                <input class="EditBizOwner=" type="text" id="editBizOwner" placeholder="${data.Owner}" required minlength="2" maxlength="32" size="15" />
                                <a id="ButtonEditBizOwner" class="buttonEditBizOwner"></a>
                            </td>
                            <td>
                            </td>
                        </tr>
                        <tr>
                            <td>Buy Point</td>
                            <td>${data.BuyPoint}</td>
                            <td>
                                <button class="button buttonEntered" onclick="SetBuyPoint()">Set</button>
                                <button class="button buttonEntered" onclick="GotoPoint('buyPoint')">Goto</button>
                            </td>
                        </tr>
                        <tr>
                            <td>Order Point</td>
                            <td>${data.OrderPoint}</td>
                            <td>
                                <button class="button buttonEntered" onclick="SetOrderPoint()">Set</button>
                                <button class="button buttonEntered" onclick="GotoPoint('orderPoint')">Goto</button>
                            </td>
                        </tr>
                        <tr>
                            <td>Safe Point</td>
                            <td>${data.SafePoint}</td>
                            <td>
                                <button class="button buttonEntered" onclick="SetSafePoint()">Set</button>
                                <button class="button buttonEntered" onclick="GotoPoint('SafePoint')">Goto</button>
                            </td>
                        </tr>
                    </table>
                </div>
            `)
            document.getElementById("editBizOwner").value = data.Owner
            document.getElementById("editBizOwner").owner = data.Owner

            $(".footer").empty()
            $(".footer").append(`
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `)
        }
    }
});