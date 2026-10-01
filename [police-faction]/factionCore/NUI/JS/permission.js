var edit
var playerName = ''
var factionId
var playerRank = {}
var isCarDealer = false
var isCasino = false

function GetPlayerName(name) {
    playerName = name
}

function RemovePlayerName() {
    playerName = ''
}

window.addEventListener("input", function () {
    if (edit == 'permission') {
        if (document.getElementById("createPermission").value !== '') {
            $("#ButtonCreatePermission").empty()
            $("#ButtonCreatePermission").append(`
                <button class="button buttonConfirm" onclick="CreatePerm('${document.getElementById("createPermission").value}')"></button>
                <button class="button buttonCancelSel" onclick="CreatePerm('cancelSelect')"></button>
            `)
        } else {
            $("#ButtonCreatePermission").empty()
        }
    }
})

window.addEventListener("input", function () {
    if (edit == 'permission') {
        if (playerName !== '') {
            if (document.getElementById("editPermLeader" + playerName.replace(/\s/g, '')).checked == true ||
                document.getElementById("editPermLeader" + playerName.replace(/\s/g, '')).checked == false ||
                document.getElementById("editPermMember" + playerName.replace(/\s/g, '')).checked == true ||
                document.getElementById("editPermMember" + playerName.replace(/\s/g, '')).checked == false ||
                document.getElementById("editPermRole" + playerName.replace(/\s/g, '')).checked == true ||
                document.getElementById("editPermRole" + playerName.replace(/\s/g, '')).checked == false ||
                document.getElementById("editPermRadio" + playerName.replace(/\s/g, '')).checked == true ||
                document.getElementById("editPermRadio" + playerName.replace(/\s/g, '')).checked == false ||
                document.getElementById("editPermGun" + playerName.replace(/\s/g, '')).checked == true ||
                document.getElementById("editPermGun" + playerName.replace(/\s/g, '')).checked == false) {

                const leader = document.getElementById("editPermLeader" + playerName.replace(/\s/g, '')).checked
                const members = document.getElementById("editPermMember" + playerName.replace(/\s/g, '')).checked
                const role = document.getElementById("editPermRole" + playerName.replace(/\s/g, '')).checked
                const radio = document.getElementById("editPermRadio" + playerName.replace(/\s/g, '')).checked
                const gun = document.getElementById("editPermGun" + playerName.replace(/\s/g, '')).checked
                const dealerPermissions = isCarDealer ? {
                    dealer_manage_employees: document.getElementById("editPermDealerEmployees" + playerName.replace(/\s/g, '')).checked,
                    dealer_manage_inventory: document.getElementById("editPermDealerInventory" + playerName.replace(/\s/g, '')).checked,
                    dealer_manage_finances: document.getElementById("editPermDealerFinances" + playerName.replace(/\s/g, '')).checked,
                    dealer_sell: document.getElementById("editPermDealerSell" + playerName.replace(/\s/g, '')).checked,
                    dealer_deliver: document.getElementById("editPermDealerDeliver" + playerName.replace(/\s/g, '')).checked,
                    dealer_view_records: document.getElementById("editPermDealerRecords" + playerName.replace(/\s/g, '')).checked
                } : {}
                const casinoPermissions = isCasino ? {
                    casino_cashier: document.getElementById("editPermCasinoCashier" + playerName.replace(/\s/g, '')).checked,
                    casino_membership: document.getElementById("editPermCasinoMembership" + playerName.replace(/\s/g, '')).checked,
                    casino_ledger: document.getElementById("editPermCasinoLedger" + playerName.replace(/\s/g, '')).checked
                } : {}

                EditPerm('update', playerName, leader, members, role, radio, gun, {...dealerPermissions, ...casinoPermissions})
            }
        }
    }
})

function EditPerm(type, playerName, leader, members, role, radio, gun, dealerPermissions = {}) {
    $.post('https://factionCore/EditPermission', JSON.stringify({ id: factionId, type: type, playerName: playerName, leader: leader, members: members, role: role, radio: radio, gun: gun, ...dealerPermissions }));
}

function CreatePerm(name) {
    $.post('https://factionCore/CreatePermission', JSON.stringify({ id: factionId, name: name }));
}

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit

    if (data.display === true & data.edit === 'permission' & data.reupdate === true) {
        playerRank = {}
        $("#memberList").empty()
    }
    if (data.display === true & data.edit === 'permission' & data.update === false) {
        factionId = data.id
        isCarDealer = data.isCarDealer === true
        isCasino = data.isCasino === true
        if (data.permission.leader == true) {
            var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                <a class="active">Permission</a>
                <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                ${garageBtn}
                <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
            `)
        }
        $('.content').empty()
        $('.content').append(`
            <table id="permList">
                <tr>
                    <th>Name</th>
                    <th>Permission</th>
                    <th>Action</th>
                </tr>
            </table>
        `)

        $(".footer").empty()
        $(".footer").append(`
            <a id="ButtonCreatePermission" class="buttonCreatePermission"></a>
            <input class="CreatePermission=" onclick="RemovePlayerName()" style="border: 1px solid #13131359; border-radius: 3px;" type="text" id="createPermission" placeholder="Thêm (John Garcia)" required minlength="5" maxlength="32" size="20" />
            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
        `)
    }
    if (data.display == true & data.edit == 'permission' & data.update == true) {

        var checked = { leader: '', members: '', role: '', radio: '', gun: '', dealerEmployees: '', dealerInventory: '', dealerFinances: '', dealerSell: '', dealerDeliver: '', dealerRecords: '', casinoCashier: '', casinoMembership: '', casinoLedger: '' }

        if (data.leader == true) { checked.leader = 'checked' }
        if (data.members == true) { checked.members = 'checked' }
        if (data.role == true) { checked.role = 'checked' }
        if (data.radio == true) { checked.radio = 'checked' }
        if (data.gun == true) { checked.gun = 'checked' }
        if (data.dealer_manage_employees == true) { checked.dealerEmployees = 'checked' }
        if (data.dealer_manage_inventory == true) { checked.dealerInventory = 'checked' }
        if (data.dealer_manage_finances == true) { checked.dealerFinances = 'checked' }
        if (data.dealer_sell == true) { checked.dealerSell = 'checked' }
        if (data.dealer_deliver == true) { checked.dealerDeliver = 'checked' }
        if (data.dealer_view_records == true) { checked.dealerRecords = 'checked' }
        if (data.casino_cashier == true) { checked.casinoCashier = 'checked' }
        if (data.casino_membership == true) { checked.casinoMembership = 'checked' }
        if (data.casino_ledger == true) { checked.casinoLedger = 'checked' }

        $("#permList").append(`
            <tr>
                <td>
                    ${data.name}
                </td>
                <td>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermLeader${data.name.replace(' ', '')}" value='leader' name="permission"  ${checked.leader}/>
                    <a class="button">Leader</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermMember${data.name.replace(' ', '')}" value='members' name="permission" ${checked.members}/>
                    <a class="button">Members</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermRole${data.name.replace(' ', '')}"   value='role' name="permission"    ${checked.role}/>    
                    <a class="button">Rank/Div</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermRadio${data.name.replace(' ', '')}"   value='radio' name="permission"    ${checked.radio}/>    
                    <a class="button">Radio</a>

                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermGun${data.name.replace(' ', '')}"   value='gun' name="permission"    ${checked.gun}/>    
                    <a class="button">Gun</a>
                    ${isCarDealer ? `
                    <br/>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerEmployees${data.name.replace(/\s/g, '')}" ${checked.dealerEmployees}/><a class="button">Dealer: Nhân viên</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerInventory${data.name.replace(/\s/g, '')}" ${checked.dealerInventory}/><a class="button">Dealer: Kho xe</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerFinances${data.name.replace(/\s/g, '')}" ${checked.dealerFinances}/><a class="button">Dealer: Tài chính</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerSell${data.name.replace(/\s/g, '')}" ${checked.dealerSell}/><a class="button">Dealer: Bán xe</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerDeliver${data.name.replace(/\s/g, '')}" ${checked.dealerDeliver}/><a class="button">Dealer: Giao xe</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermDealerRecords${data.name.replace(/\s/g, '')}" ${checked.dealerRecords}/><a class="button">Dealer: Lịch sử</a>` : ''}
                    ${isCasino ? `
                    <br/>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermCasinoCashier${data.name.replace(/\s/g, '')}" ${checked.casinoCashier}/><a class="button">Casino: Thu ngân</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermCasinoMembership${data.name.replace(/\s/g, '')}" ${checked.casinoMembership}/><a class="button">Casino: Hội viên</a>
                    <input type="checkbox" onclick="GetPlayerName('${data.name}')" id="editPermCasinoLedger${data.name.replace(/\s/g, '')}" ${checked.casinoLedger}/><a class="button">Casino: Sổ quỹ</a>` : ''}
                </td>
                <td>
                    <button class="button buttonRemove" onclick="EditPerm('remove', '${data.name}')">Xóa</button>
                </td>
            </tr>
        `)
    }
});
