var edit
var factionId

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit;

    if (data.display === true && data.edit === 'garage') {
        if (data.update === false) {
            factionId = data.id;
            
            if (data.permission.leader == true) {
                var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="active">Garage</a>` : '';
                $(".listmenu").empty();
                $(".listmenu").append(`
                    <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                    <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                    <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                    <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                    <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                    ${garageBtn}
                    <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                    <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
                `);
            } else if (data.type === 'business') {
                $(".listmenu").empty();
                $(".listmenu").append(`
                    ${data.permission.members == true ? `<a class="unactive" onclick="SelectMenu('members', '${data.id}')">Members</a>` : ''}
                    ${data.permission.role == true ? `<a class="unactive" onclick="SelectMenu('rank', '${data.id}')">Rank</a><a class="unactive" onclick="SelectMenu('division', '${data.id}')">Division</a>` : ''}
                    <a class="active">Garage</a>
                `);
            }

            $('.content').empty();
            $('.content').append(`
                <table id="garageList">
                    <tr>
                        <th>#</th>
                        <th>Vị trí</th>
                        <th>Action</th>
                    </tr>
                </table>
            `);

            $(".footer").empty();
            if (data.permission.leader == true) {
                $(".footer").append(`
                    <button class="button buttonConfirm" onclick="CreateGarage()">Tạo Garage ở vị trí hiện tại</button>
                    <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
                `);
            } else {
                $(".footer").append(`<button class="button buttonClosed" onclick="CloseMenu()">Log out</button>`);
            }
        }

        if (data.update == true) {
            if (data.permission && data.permission.leader != true) {
                $("#garageList").append(`
                    <tr>
                        <td>${data.garageId}</td>
                        <td>${data.locationName}</td>
                        <td>Đến vị trí garage để sử dụng</td>
                    </tr>
                `);
            } else if (data.canRemove == true) {
                $("#garageList").append(`
                    <tr>
                        <td>${data.garageId}</td>
                        <td>${data.locationName}</td>
                        <td>
                            <button class="button buttonConfirm" onclick="EditGarage('${data.garageId}')">Lưu Vị Trí Hiện Tại</button>
                            <button class="button buttonRemove" onclick="RemoveGarage('${data.garageId}')">Xóa</button>
                            <button class="button buttonSelect" onclick="ManageVehicles('${data.garageId}')">Quản lý Xe</button>
                        </td>
                    </tr>
                `);
            } else {
                $("#garageList").append(`
                    <tr>
                        <td>${data.garageId}</td>
                        <td>${data.locationName}</td>
                        <td>
                            <button class="button buttonConfirm" onclick="EditGarage('${data.garageId}')">Lưu Vị Trí Hiện Tại</button>
                            <button class="button buttonSelect" onclick="ManageVehicles('${data.garageId}')">Quản lý Xe</button>
                        </td>
                    </tr>
                `);
            }
        }
    }
});

function CreateGarage() {
    $.post('https://factionCore/CreateGarage', JSON.stringify({id: factionId}));
}

function EditGarage(garageId) {
    $.post('https://factionCore/EditGarage', JSON.stringify({id: factionId, garageId: garageId}));
}

function RemoveGarage(garageId) {
    $.post('https://factionCore/RemoveGarage', JSON.stringify({id: factionId, garageId: garageId}));
}

function ManageVehicles(garageId) {
    $.post('https://factionCore/ManageGarageVehicles', JSON.stringify({id: factionId, garageId: garageId}));
}
