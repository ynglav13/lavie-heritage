var edit
var factionId
var factionRank = {}
var createValue = ''

Object.size = function(obj) {
    var size = 0,
      key;
    for (key in obj) {
      if (obj.hasOwnProperty(key)) size++;
    }
    return size;
  };

window.addEventListener("input", function() {
    if (edit == 'rank') {

        if (document.getElementById("createRank").value !== createValue) {
            $("#ButtonCreateRank").empty()
            $("#ButtonCreateRank").append(`
                <button class="button buttonConfirm" onclick="CreateRank('${document.getElementById("createRank").value}')"></button>
                <button class="button buttonCancelSel" onclick="CreateRank('cancelSelect')"></button>
            `)
        } else {
            $("#ButtonCreateRank").empty()
        }

        for(var i = 1; i <= Object.size(factionRank); i++) {
            if (factionRank[i].name !== document.getElementById("editFactionRank" + factionRank[i].id).value) {
                $("#Rank" + factionRank[i].id).empty()
                $("#Rank" + factionRank[i].id).append(`
                    <button class="button buttonConfirm" onclick="EditRank('update', '${factionRank[i].id}', '${document.getElementById("editFactionRank" + factionRank[i].id).value}')"></button>
                    <button class="button buttonCancelSel" onclick="EditRank('cancelSelect', '${factionRank[i].id}')"></button>
                `)
            } else {
                $("#Rank" + factionRank[i].id).empty()
            }
        }
    }
})

function CreateRank(rankName) {
    document.getElementById('createRank').value = ''
    if (rankName == 'cancelSelect') {
        $("#ButtonCreateRank").empty()
    } else {
        $.post('https://factionCore/CreateRank', JSON.stringify({id: factionId, rankName: rankName}));
    }
}

function EditRank(type, rankId, value) {
    if (type == 'cancelSelect') {
        $("#Rank" + rankId).empty()
    } else {
        $.post('https://factionCore/EditRank', JSON.stringify({id: factionId, type: type, rankId: rankId, value: value}));
    }
}

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit
    if (data.reset === true) {
        factionRank = {}
    }
    if (data.display === true & data.edit === 'rank') {
        if (data.update === false) {
            factionId = data.id
            if (data.permission.leader == true) {
                var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
                $(".listmenu").empty()
                $(".listmenu").append(`
                    <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                    <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                    <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                    <a class="active">Rank</a>
                    <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                    ${garageBtn}
                    <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                    <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
                `)
            } else {
                $(".listmenu").empty()
                var memberGarageBtn = data.type === 'business' ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
                if (data.permission.role == true & data.permission.members == false) {
                    $(".listmenu").append(`
                        <a class="active">Rank</a>
                        <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                        ${memberGarageBtn}
                    `)
                }
                if (data.permission.role == true & data.permission.members == true) {
                    $(".listmenu").append(`
                        <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                        <a class="active">Rank</a>
                        <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                        ${memberGarageBtn}
                    `)
                }
            }
            $('.content').empty()
            $('.content').append(`
                <table id="rankList">
                    <tr>
                        <th>#</th>
                        <th>Rank Name</th>
                        <th>Action</th>
                    </tr>
                </table>
            `)

            $(".footer").empty()
            $(".footer").append(`
                <a id="ButtonCreateRank" class="buttonCreateRank"></a>
                <input class="CreateRank=" style="border: 1px solid #13131359; border-radius: 3px;" type="text" id="createRank" placeholder="Tạo Rank" required minlength="2" maxlength="64" size="25" />
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `)
            document.getElementById("createRank").value = createValue
        }
        if (data.update == true) {
            if (data.canRemove == true) {
                $("#rankList").append(`
                    <tr>
                        <td>
                            ${data.rankId}
                        </td>
                        <td>
                            <input class="EditFactionRank=" type="text" id="editFactionRank${data.rankId}" placeholder="${data.rankName}" required minlength="2" maxlength="64" size="25" />
                            <div id="Rank${data.rankId}" class="buttonEditRank"></div>
                        </td>
                        <td>
                            <button class="button buttonRemove" onclick="EditRank('remove', '${data.rankId}', '${data.rankName}')">Xóa</button>
                        </td>
                    </tr>
                `)
            } else {
                $("#rankList").append(`
                    <tr>
                        <td>
                            ${data.rankId}
                        </td>
                        <td>
                            <input class="EditFactionRank=" type="text" id="editFactionRank${data.rankId}" placeholder="${data.rankName}" required minlength="2" maxlength="64" size="25" />
                            <div id="Rank${data.rankId}" class="buttonEditRank"></div>
                        </td>
                        <td>
                        </td>
                    </tr>
                `)
            }
            document.getElementById("editFactionRank" + data.rankId).value = data.rankName
            factionRank[Object.size(factionRank)+1] = {id: data.rankId, name: data.rankName}
            document.getElementById("createRank").value = createValue

        }
    }
});
