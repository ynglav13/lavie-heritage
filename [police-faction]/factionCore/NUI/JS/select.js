var createType = ''
var SelectFaction = false


window.addEventListener("input", function() {
    if (SelectFaction == true) {
        const input = document.getElementById("createFaction");
        if (!input) return;
        const val = input.value;
        if (val !== '') {
            $("#ButtonCreateFaction").empty();
            let btnConfirm = $('<button class="button buttonConfirm"></button>');
            btnConfirm.click(function() {
                CreateFaction(createType, val);
            });
            let btnCancel = $('<button class="button buttonCancelSel"></button>');
            btnCancel.click(function() {
                CreateFaction('cancelSelect');
            });
            $("#ButtonCreateFaction").append(btnConfirm).append(btnCancel);
        } else {
            $("#ButtonCreateFaction").empty()
        }
    }
})

function CreateFaction(type, name) {
    const input = document.getElementById('createFaction')
    if (input) input.value = ''
    if (type == 'cancelSelect') {
        $("#ButtonCreateFaction").empty()
    } else {
        $.post('https://factionCore/CreateFaction', JSON.stringify({type: type, name: name}));
    }
}

function SelectItem(logo, id) {
    var elements = document.getElementsByClassName("label");
    for(var i = 0; i < elements.length; i++) {
        if (elements[i].id !== id) {
            let logoVal = document.getElementById(elements[i].id).logo;
            let bg = "linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%))";
            if (logoVal && logoVal !== 'undefined' && logoVal !== '') {
                bg += `, url('${logoVal}')`;
            }
            document.getElementById(elements[i].id).style.backgroundImage = bg;
            document.getElementById(elements[i].id).style.backgroundSize = "cover";

            document.getElementById(elements[i].id).style.filter = 'grayscale(100%)'
            document.getElementById(elements[i].id).style.opacity = "0.5"
        }
    }

    document.getElementById(id).style.opacity = "1.0"
    document.getElementById(id).style.filter = 'none'
    document.getElementById(id).style.backgroundSize = "cover";
    
    let selectBg = 'linear-gradient(to bottom, rgba(245, 246, 252, 0.253), rgba(33, 163, 238, 0.534))';
    if (logo && logo !== 'undefined' && logo !== '') {
        selectBg += `, url('${logo}')`;
    }
    document.getElementById(id).style.backgroundImage = selectBg;

    $('.footer').empty()
    $('.footer').append(`
        <button class="button buttonEntered" onclick="Select('${id}')">Chọn</button>
        <button class="button buttonClosed" onclick="DeleteFaction('${id}')" style="margin-left: 10px; background: #e74c3c;">Xóa</button>
    `)
}

function Select(id) {
    SelectFaction = false
    $.post('https://factionCore/SelectFaction', JSON.stringify({id: id}));
}

function SelectGroupType(type) {
    $.post('https://factionCore/SelectGroupType', JSON.stringify({type: type}));
}

function DeleteFaction(id) {
    const logo = document.getElementById(id).logo;
    $('.footer').empty()
    $('.footer').append(`
        <span style="color: white; margin-right: 10px; font-family: 'Outfit', sans-serif; font-size: 14px;">Xóa Faction?</span>
        <button class="button buttonConfirm" onclick="ConfirmDeleteFaction('${id}')"></button>
        <button class="button buttonCancelSel" onclick="SelectItem('${logo}', '${id}')"></button>
    `)
}

function ConfirmDeleteFaction(id) {
    $.post('https://factionCore/DeleteFaction', JSON.stringify({id: id}));
}

window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.display === true & data.edit === 'select') {
        createType = data.type
        SelectFaction = true
        if (data.type === 'gov') {
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="active">Government</a>
                <a class="unactive" onclick="SelectGroupType('business')">Business</a>
            `)
        } else if (data.type === 'business') {
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectGroupType('gov')">Government</a>
                <a class="active">Business</a>
            `)
        } else {
            $(".listmenu").empty()
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectGroupType('gov')">Government</a>
                <a class="unactive" onclick="SelectGroupType('business')">Business</a>
            `)
        }
        if (data.nonFaction == undefined) {
            let bgImage = "linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%))";
            if (data.logo && data.logo !== 'undefined' && data.logo !== '') {
                bgImage += `, url(${data.logo})`;
            }
            $(".content").append(`
                    <div class="label" id='${data.id}' value='${data.logo}' onclick="SelectItem('${data.logo}', '${data.id}')" style="background-size: cover; background-image: ${bgImage};">
                        <p class="label-name">${data.name}</p>
                    </div>
            `)
            document.getElementById(data.id).logo = data.logo
        } else {
            $(".main-bg").empty()
            $(".main-bg").append(`
                <div class="content">
                </div>
            `)
        }
        $(".footer").empty()
        $(".footer").append(`
            <a id="ButtonCreateFaction" class="buttonCreateFaction"></a>
            <input class="CreateFaction=" style="border: 1px solid #13131359; border-radius: 3px;" type="text" id="createFaction" placeholder="Tạo thêm group" required minlength="3" maxlength="64" size="25" />
            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
        `)
        const input = document.getElementById("createFaction")
        if (input) input.value = ''

    }
});
