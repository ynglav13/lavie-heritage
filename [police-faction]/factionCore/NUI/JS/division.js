var edit
var factionId
var factionDivision = {}
var createValue = ''

Object.size = function (obj) {
    var size = 0,
        key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) size++;
    }
    return size;
};

window.addEventListener("input", function () {
    if (edit == 'division') {

        if (document.getElementById("createDivision").value !== createValue) {
            $("#ButtonCreateDivision").empty()
            $("#ButtonCreateDivision").append(`
                <button class="button buttonConfirm" onclick="CreateDivision('${document.getElementById("createDivision").value}')"></button>
                <button class="button buttonCancelSel" onclick="CreateDivision('cancelSelect')"></button>
            `)
        } else {
            $("#ButtonCreateDivision").empty()
        }

        for (var i = 1; i <= Object.size(factionDivision); i++) {
            if (factionDivision[i].name !== document.getElementById("editFactionDivision" + factionDivision[i].id).value) {
                $("#Division" + factionDivision[i].id).empty()
                $("#Division" + factionDivision[i].id).append(`
                    <button class="button buttonConfirm" onclick="EditDivision('update', '${factionDivision[i].id}', '${document.getElementById("editFactionDivision" + factionDivision[i].id).value}')"></button>
                    <button class="button buttonCancelSel" onclick="EditDivision('cancelSelect', '${factionDivision[i].id}')"></button>
                `)
            } else {
                $("#Division" + factionDivision[i].id).empty()
            }
        }
    }
})

function CreateDivision(divisionName) {
    document.getElementById('createDivision').value = ''
    if (divisionName == 'cancelSelect') {
        $("#ButtonCreateDivision").empty()
    } else {
        $.post('https://factionCore/CreateDivision', JSON.stringify({ id: factionId, divisionName: divisionName }));
    }
}

function EditDivision(type, divisionId, value) {
    if (type == 'cancelSelect') {
        $("#Division" + divisionId).empty()
    } else {
        $.post('https://factionCore/EditDivision', JSON.stringify({ id: factionId, type: type, divisionId: divisionId, value: value }));
    }
}

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit
    if (data.reset === true) {
        factionDivision = {}
    }
    if (data.display === true & data.edit === 'division') {
        if (data.update === false) {
            factionId = data.id
            if (data.permission.leader == true) {
                var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
                $(".listmenu").empty()
                $(".listmenu").append(`
                    <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                    <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                    <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                    <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                    <a class="active">Division</a>
                    ${garageBtn}
                    <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                    <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
                `)
            } else {
                $(".listmenu").empty()
                var memberGarageBtn = data.type === 'business' ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
                if (data.permission.role == true & data.permission.members == false) {
                    $(".listmenu").append(`
                        <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                        <a class="active">Division</a>
                        ${memberGarageBtn}
                    `)
                }
                if (data.permission.role == true & data.permission.members == true) {
                    $(".listmenu").append(`
                    <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                    <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                        <a class="active">Division</a>
                        ${memberGarageBtn}
                    `)
                }
            }

            $('.content').empty()
            $('.content').append(`
                <table id="rankList">
                    <tr>
                        <th>#</th>
                        <th>Division Name</th>
                        <th>Action</th>
                    </tr>
                </table>
            `)

            $(".footer").empty()
            $(".footer").append(`
                <a id="ButtonCreateDivision" class="buttonCreateDivision"></a>
                <input class="CreateDivision=" style="border: 1px solid #13131359; border-radius: 3px;" type="text" id="createDivision" placeholder="Tạo Division" required minlength="2" maxlength="64" size="25" />
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `)
            document.getElementById("createDivision").value = createValue
        }
        if (data.update == true) {
            // The async callback can arrive after the player has switched tabs.
            // Do not append a division row into another tab's #rankList.
            if (!document.getElementById('rankList') || !document.getElementById('createDivision')) return;

            if (data.canRemove == true) {
                $("#rankList").append(`
                    <tr>
                        <td>
                            ${data.divisionId}
                        </td>
                        <td>
                            <input class="EditFactionDivision=" type="text" id="editFactionDivision${data.divisionId}" placeholder="${data.divisionName}" required minlength="2" maxlength="64" size="25" />
                            <div id="Division${data.divisionId}" class="buttonEditDivision"></div>
                        </td>
                        <td>
                            <button class="button buttonRemove" onclick="EditDivision('remove', '${data.divisionId}', '${data.divisionName}')">Xóa</button>
                        </td>
                    </tr>
                `)
            } else {
                $("#rankList").append(`
                    <tr>
                        <td>
                            ${data.divisionId}
                        </td>
                        <td>
                            <input class="EditFactionDivision=" type="text" id="editFactionDivision${data.divisionId}" placeholder="${data.divisionName}" required minlength="2" maxlength="64" size="25" />
                            <div id="Division${data.divisionId}" class="buttonEditDivision"></div>
                        </td>
                        <td>
                        </td>
                    </tr>
                `)
            }
            const divisionInput = document.getElementById("editFactionDivision" + data.divisionId)
            if (!divisionInput) return;
            divisionInput.value = data.divisionName
            factionDivision[Object.size(factionDivision) + 1] = { id: data.divisionId, name: data.divisionName }
            document.getElementById("createDivision").value = createValue
        }
    }
});
