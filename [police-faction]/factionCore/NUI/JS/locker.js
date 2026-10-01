var edit
var factionId

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit;

    if (data.display === true && data.edit === 'locker') {
        if (data.update === false) {
            factionId = data.id;
            
            if (data.permission.leader == true) {
                var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
                $(".listmenu").empty();
                $(".listmenu").append(`
                    <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                    <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                    <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                    <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                    <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                    ${garageBtn}
                    <a class="active">Locker</a>
                    <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
                `);
            }

            $('.content').empty();
            $('.content').append(`
                <table id="lockerList">
                    <tr>
                        <th>#</th>
                        <th>Locker Name</th>
                        <th>Action</th>
                    </tr>
                </table>
            `);

            $(".footer").empty();
            $(".footer").append(`
                <button class="button buttonConfirm" onclick="CreateLocker()">Tạo Locker ở vị trí hiện tại</button>
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `);
        }

        if (data.update == true) {
            if (data.canRemove == true) {
                $("#lockerList").append(`
                    <tr>
                        <td>${data.lockerId}</td>
                        <td>${data.locationName}</td>
                        <td>
                            <button class="button buttonConfirm" onclick="EditLocker('${data.lockerId}')">Lưu Vị Trí Hiện Tại</button>
                            <button class="button buttonRemove" onclick="RemoveLocker('${data.lockerId}')">Xóa</button>
                        </td>
                    </tr>
                `);
            } else {
                $("#lockerList").append(`
                    <tr>
                        <td>${data.lockerId}</td>
                        <td>${data.locationName}</td>
                        <td>
                            <button class="button buttonConfirm" onclick="EditLocker('${data.lockerId}')">Lưu Vị Trí Hiện Tại</button>
                        </td>
                    </tr>
                `);
            }
        }
    }
});

function CreateLocker() {
    $.post('https://factionCore/CreateLocker', JSON.stringify({id: factionId}));
}

function EditLocker(lockerId) {
    $.post('https://factionCore/EditLocker', JSON.stringify({id: factionId, lockerId: lockerId}));
}

function RemoveLocker(lockerId) {
    $.post('https://factionCore/RemoveLocker', JSON.stringify({id: factionId, lockerId: lockerId}));
}
