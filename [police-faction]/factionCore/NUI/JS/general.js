var edit = false

var faction = {
    id: 0,
    name: '',
    tag: '',
    type: '',
    logo: '',
    category: '',
    color: '',
    sirenbox: '',
}

window.addEventListener("input", function () {
    if (edit == 'general') {
        const newName = document.getElementById("factionName").value
        if (newName !== faction.name) {
            $(".buttonName").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function () {
                EditFaction('name', newName);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function () {
                CancelEdit('Name', faction.name);
            });
            $(".buttonName").append(btnConfirm).append(btnCancel);
        } else {
            $(".buttonName").empty()
        }

        const newTag = document.getElementById("factionTag").value
        if (newTag !== faction.tag) {
            $(".buttonTag").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function () {
                EditFaction('tag', newTag);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function () {
                CancelEdit('Tag', faction.tag);
            });
            $(".buttonTag").append(btnConfirm).append(btnCancel);
        } else {
            $(".buttonTag").empty()
        }

        const newType = document.getElementById("factionType").value
        if (newType !== faction.type) {
            $(".buttonType").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function () {
                EditFaction('type', newType);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function () {
                CancelEdit('Type', faction.type);
            });
            $(".buttonType").append(btnConfirm).append(btnCancel);
        } else {
            $(".buttonType").empty()
        }

        const newLogo = document.getElementById("factionLogo").value
        if (newLogo !== faction.logo) {
            $(".buttonLogo").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function () {
                EditFaction('logo', newLogo);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function () {
                CancelEdit('logo', faction.logo);
            });
            $(".buttonLogo").append(btnConfirm).append(btnCancel);
        } else {
            $(".buttonLogo").empty()
        }

        const catEl = document.getElementById("factionCategory")
        if (catEl) {
            const newCategory = catEl.value
            if (newCategory !== faction.category) {
                $(".buttonCategory").empty();
                let btnConfirm = $('<button class="button buttonConfirm"></button>');
                btnConfirm.click(function () {
                    EditFaction('category', newCategory);
                });
                let btnCancel = $('<button class="button buttonCancelSel"></button>');
                btnCancel.click(function () {
                    CancelEdit('Category', faction.category);
                });
                $(".buttonCategory").append(btnConfirm).append(btnCancel);
            } else {
                $(".buttonCategory").empty()
            }
        }

        const newColour = document.getElementById("factionColour").value
        if (newColour !== faction.color) {
            $(".buttonColour").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function () {
                EditFaction('color', newColour);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function () {
                CancelEdit('Colour', faction.color);
            });
            $(".buttonColour").append(btnConfirm).append(btnCancel);
        } else {
            $(".buttonColour").empty()
        }

        const sirenEl = document.getElementById("factionSirenbox")
        if (sirenEl) {
            const newSirenbox = sirenEl.value
            if (newSirenbox !== faction.sirenbox) {
                $(".buttonSirenbox").empty();
                let btnConfirm = $('<button class="button buttonConfirm"></button>');
                btnConfirm.click(function () {
                    EditFaction('sirenbox', newSirenbox);
                });
                let btnCancel = $('<button class="button buttonCancelSel"></button>');
                btnCancel.click(function () {
                    CancelEdit('Sirenbox', faction.sirenbox);
                });
                $(".buttonSirenbox").append(btnConfirm).append(btnCancel);
            } else {
                $(".buttonSirenbox").empty()
            }
        }
    }
})

window.addEventListener("change", function () {
    if (edit == 'general') {
        window.dispatchEvent(new Event('input'));
    }
})

function EditFaction(type, value) {
    $(".buttonType").empty()
    $.post('https://factionCore/EditFaction', JSON.stringify({ id: faction.id, type: type, value: value }));
}

function CancelEdit(type, value) {
    document.getElementById("faction" + type).value = value
    $(".button" + type).empty()
}

function ResetFactionVehicles(tag) {
    $.post('https://factionCore/ResetFactionVehicles', JSON.stringify({ tag: tag }));
}

window.addEventListener('message', function (event) {
    var data = event.data;
    edit = data.edit
    if (data.display === true & data.edit === 'general') {
        faction.id = data.id
        faction.name = data.name
        faction.tag = data.tag
        faction.type = data.type
        faction.logo = data.logo
        faction.category = data.category
        faction.color = data.colour
        faction.sirenbox = data.sirenbox || 'SmartControllerB'

        if (data.permission.leader == true) {
            $(".listmenu").empty()
            var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
            $(".listmenu").append(`
                <a class="active">General</a>
                <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                ${garageBtn}
                <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                <a class="unactive" onclick="SelectMenu('budget',       '${data.id}')">Budget</a>
            `)
        }
        var category = ''
        var sirenboxHtml = ''
        if (faction.type == 'gov') {
            category = `
                <td>Category</td>
                <td>
                    <select class="EditFactionCategory=" id="factionCategory" >
                        <option value="police">Police</option>
                        <option value="medic">Medic</option>
                    </select>
                    <div class="buttonCategory"></div>
                </td>
            `
            sirenboxHtml = `
                <tr>
                    <td>SirenBox</td>
                    <td>
                        <select class="EditFactionSirenbox=" id="factionSirenbox">
                            <option value="CCRSN36">CCRSN36</option>
                            <option value="CHPWhelenCoreS">CHPWhelenCoreS</option>
                            <option value="PF200S17B">PF200S17B</option>
                            <option value="SmartControllerB">SmartControllerB</option>
                            <option value="WeCamXCCRSN36">WeCamXCCRSN36</option>
                        </select>
                        <div class="buttonSirenbox"></div>
                    </td>
                </tr>
            `
        } else {
            category = ``
        }
        $(".content").empty()
        $(".content").append(`
            <table id="general">
                <tr>
                    <td>Name</td>
                    <td>
                        <input class="EditFactionName=" type="text" id="factionName" placeholder="${faction.name}" required minlength="3" maxlength="64" size="25" />
                        <div class="buttonName"></div>
                    </td>
                </tr>
                <tr>
                    <td>Tag</td>
                    <td>
                        <input class="EditFactionTag=" type="text" id="factionTag" placeholder="${faction.tag}" required minlength="2" maxlength="24" size="25" />
                        <div class="buttonTag"></div>
                    </td>
                </tr>
                <tr>
                    <td>Logo</td>
                    <td>
                        <input class="EditFactionLogo=" type="text" id="factionLogo" placeholder="https://i.imgur.com/xxxxxxx" required minlength="10" maxlength="500" size="25" />
                        <div class="buttonLogo"></div>
                    </td>
                </tr>
                <tr>
                    <td>Type</td>
                    <td>
                        <select class="EditFactionType=" id="factionType" >
                            <option value="gov" >Government</option>
                            <option value="business" >Business</option>
                        </select>
                        <div class="buttonType"></div>
                    </td>
                </tr>
                <tr>
                    ${category}
                </tr>
                ${sirenboxHtml}
                <tr>
                    <td>Faction Colour</td>
                    <td class="EditFactionColour" style="display: flex; gap: 12px; align-items: center;">
                        <span class="badge" style="background-color: ${faction.color}22; color: ${faction.color}; border-color: ${faction.color}44;">${faction.color}</span>
                        <input type="color" id="factionColour" value="${faction.color}"/>
                        <div class="buttonColour"></div>
                    </td>
                </tr>
                <tr>
                    <td>Reset Vehicles</td>
                    <td style="display: flex; gap: 12px; align-items: center;">
                        <button class="button buttonConfirm" onclick="ResetFactionVehicles('${faction.tag}')" style="width: auto; padding: 5px 15px; background: #e74c3c; border-radius: 4px; color: white; cursor: pointer; border: none; font-family: 'Inter', sans-serif;">Reset All Vehicles</button>
                    </td>
                </tr>
            </table>
        `)
        document.getElementById("factionName").value = faction.name
        document.getElementById("factionTag").value = faction.tag
        document.getElementById("factionLogo").value = faction.logo
        document.getElementById("factionType").value = faction.type
        if (document.getElementById("factionCategory")) {
            document.getElementById("factionCategory").value = faction.category
        }
        if (document.getElementById("factionSirenbox")) {
            document.getElementById("factionSirenbox").value = faction.sirenbox
        }
        document.getElementById("factionColour").value = faction.color

        $(".footer").empty()
        $(".footer").append(`
            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
        `)
    }
});
