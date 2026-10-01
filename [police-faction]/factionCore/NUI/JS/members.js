var edit
var playerName = ''
var factionId
var playerRank = {}
var playerDivision = {}
var playerBadge = {}

function GetPlayerName(name) {
    playerName = name
}

function InvitePlayer() {
    let targetId = $('#invitePlayerId').val();
    if (targetId && !isNaN(targetId)) {
        $.post('https://factionCore/InvitePlayer', JSON.stringify({ targetId: targetId }));
        $('#invitePlayerId').val('');
    }
}

function RankChanged(name) {
    const nameNoSpace = name.replace(/\s/g, '');
    const newRank = document.getElementById("editRank" + nameNoSpace).value;
    if (Number(newRank) !== Number(playerRank[name])) {
        $("#rankof" + nameNoSpace).empty();
        let btnConfirm = $('<button class="button buttonConfirm"></button>');
        btnConfirm.click(function() {
            EditMembers('rank', name, newRank);
        });
        $("#rankof" + nameNoSpace).append(btnConfirm);
    } else {
        $("#rankof" + nameNoSpace).empty();
    }
}

function DivisionChanged(name) {
    const nameNoSpace = name.replace(/\s/g, '');
    const newDivision = document.getElementById("editDivision" + nameNoSpace).value;
    if (Number(newDivision) !== Number(playerDivision[name])) {
        $("#divisionof" + nameNoSpace).empty();
        let btnConfirm = $('<button class="button buttonConfirm"></button>');
        btnConfirm.click(function() {
            EditMembers('division', name, newDivision);
        });
        $("#divisionof" + nameNoSpace).append(btnConfirm);
    } else {
        $("#divisionof" + nameNoSpace).empty();
    }
}

function BadgeChanged(name) {
    const nameNoSpace = name.replace(/\s/g, '');
    const newBadge = document.getElementById("editBadge" + nameNoSpace).value;
    if (newBadge !== playerBadge[name]) {
        $("#badgeof" + nameNoSpace).empty();
        let btnConfirm = $('<button class="button buttonConfirm"></button>');
        btnConfirm.click(function() {
            EditMembers('badge', name, newBadge);
        });
        $("#badgeof" + nameNoSpace).append(btnConfirm);
    } else {
        $("#badgeof" + nameNoSpace).empty();
    }
}

function EditMembers(type, playerName, value) {
    $.post('https://factionCore/EditMembers', JSON.stringify({id: factionId, type: type, playerName: playerName, value: value}));
}

function KickPlayer(playerName) {
    console.log(playerName, playerName.replace(/\s/g, ''))
    const nameNoSpace = playerName.replace(/\s/g, '');
    $('#kick' + nameNoSpace).empty()
    
    let btnConfirm = $('<button class="button buttonConfirm"></button>');
    btnConfirm.click(function() {
        EditMembers('kick', playerName, '0');
    });
    let btnCancel = $('<button class="button buttonCancelSel"></button>');
    btnCancel.click(function() {
        CancelKick(playerName);
    });
    
    $("#kick" + nameNoSpace).append(btnConfirm).append(btnCancel);
}

function CancelKick(playerName) {
    $('#kick' + playerName.replace(/\s/g, '')).empty()
}

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit

    if (data.display === true & data.edit === 'members' & data.reupdate === true) {
        playerRank = {}
        $("#memberList").empty()
    }
    if (data.display === true & data.edit === 'members' & data.update === false) {

        factionId = data.id

        if (data.permission.leader == true) {
            var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                <a class="active">Members</a>
                <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                ${garageBtn}
                <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
            `)
        } else {
            $(".listmenu").empty()
            var memberGarageBtn = data.type === 'business' ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
            if (data.permission.members == true & data.permission.role == false) {
                $(".listmenu").append(`
                    <a class="active">Members</a>
                    ${memberGarageBtn}
                `)
            }
            if (data.permission.role == true & data.permission.members == true) {
                $(".listmenu").append(`
                    <a class="active">Members</a>
                    <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                    <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                    ${memberGarageBtn}
                `)
            }    
        }
        let badgeHeader = (data.type === 'business') ? 'Mã Nhân Viên' : 'Badge';
        $('.content').empty()
        $('.content').append(`
            <table id="memberList">
                <tr>
                    <th>Name</th>
                    <th>Rank</th>
                    <th>Division</th>
                    <th>${badgeHeader}</th>
                </tr>
            </table>
        `)

        if (data.permission.leader == true || data.permission.members == true) {
            $('.content').append(`
                <div class="invite-container">
                    <div class="invite-title">Mời Thành Viên Mới</div>
                    <div class="invite-form">
                        <input type="number" id="invitePlayerId" placeholder="Nhập ID người chơi (Server ID)..." required />
                        <button class="button buttonInvite" onclick="InvitePlayer()">Mời Vào Tổ Chức</button>
                    </div>
                </div>
            `)
        }

        $(".footer").empty()
        $(".footer").append(`
            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
        `)
    }
    if (data.display == true & data.edit == 'members' & data.update == true) {
            const nameNoSpace = data.name.replace(/\s/g, '');
            const spanId = "kickSpan_" + nameNoSpace;
            const rankSelectId = "editRank" + nameNoSpace;
            const divSelectId = "editDivision" + nameNoSpace;
            const badgeInputId = "editBadge" + nameNoSpace;

            $("#memberList").append(`
                <tr>
                    <td>
                        ${data.name}
                        <span id="${spanId}"></span>
                        <div id="kick${nameNoSpace}" class="buttonKick"></div>
                    </td>
                    <td>
                        <select name="EditRank" id="${rankSelectId}"></select>
                        <div id="rankof${nameNoSpace}" class="buttonRank"></div>
                    </td>
                    <td>
                        <select name="EditDivision" id="${divSelectId}"></select>
                        <div id="divisionof${nameNoSpace}" class="buttonDivision"></div>
                    </td>
                    <td>
                        <input type="text" id="${badgeInputId}" placeholder="Chưa có" style="width: 80px; background: rgba(0, 0, 0, 0.2); border: 1px solid rgba(255, 255, 255, 0.15); color: #fff; padding: 4px 8px; border-radius: 4px; font-family: inherit; font-size: 13px;" />
                        <div id="badgeof${nameNoSpace}" class="buttonBadge" style="display: inline-block; vertical-align: middle;"></div>
                    </td>
                </tr>
            `);

            $("#" + spanId).click(function() {
                KickPlayer(data.name);
            });
            $("#" + rankSelectId).change(function() {
                RankChanged(data.name);
            });
            $("#" + divSelectId).change(function() {
                DivisionChanged(data.name);
            });
            $("#" + badgeInputId).change(function() {
                BadgeChanged(data.name);
            });
    }

    if (data.updateRank == true) {
        $("#editRank" + data.name.replace(/\s/g, '')).append(`
            <option value="${data.rankId}" >${data.rankName}</option>
        `)
    }
    if (data.updateDivision == true) {
        $("#editDivision" + data.name.replace(/\s/g, '')).append(`
            <option value="${data.divisionId}" >${data.divisionName}</option>
        `)
    }

    if (data.display == true & data.edit == 'members' & data.updateValue == true) {
        let rankElem = document.getElementById("editRank" + data.name.replace(/\s/g, ''));
        if (rankElem) {
            rankElem.value = data.rank;
            playerRank[data.name] = data.rank;
        }

        let divElem = document.getElementById("editDivision" + data.name.replace(/\s/g, ''));
        if (divElem) {
            divElem.value = data.division;
            playerDivision[data.name] = data.division;
        }

        let badgeElem = document.getElementById("editBadge" + data.name.replace(/\s/g, ''));
        if (badgeElem) {
            badgeElem.value = data.badge || '';
            playerBadge[data.name] = data.badge || '';
        }
    }
});
