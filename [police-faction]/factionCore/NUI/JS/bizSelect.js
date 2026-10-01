function SelectBiz(logo, id) {
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
        <button class="button buttonEntered" onclick="ConfirmBusiness('${id}')">Chọn</button>
    `)
}

function ConfirmBusiness(id) {
    $.post('https://factionCore/SelectBusiness', JSON.stringify({id: id}));
}

function StringFirstChar(string) {
    return string.charAt(0).toUpperCase() + string.slice(1);
}

window.addEventListener('message', function (event) {
    var data = event.data;

    
    if (data.display === true & data.edit === 'bizSelect') {
        if (data.reset == true) {
            $(".main-bg").empty()
            $(".main-bg").append(`
                <div class="content">
                </div>
            `)
            $(".listmenu").empty()
        } else {
            let name = StringFirstChar(data.name)
            let category = StringFirstChar(data.category)
            let owner = StringFirstChar(data.owner)
            let bgImage = "linear-gradient(to bottom, rgb(56 56 56 / 50%), rgb(121 121 151 / 50%))";
            if (data.logo && data.logo !== 'undefined' && data.logo !== '') {
                bgImage += `, url(${data.logo})`;
            }
            $(".content").append(`
                <div class="label" id='${data.id}' onclick="SelectBiz('${data.logo}', '${data.id}')" style="background-size: cover; background-image: ${bgImage};">
                    <p class="label-biz">${name}</p>
                    <p class="label-category">${category}</p>
                    <p class="label-owner">${owner}</p>
                </div>
            `)
            document.getElementById(data.id).logo = data.logo
            $(".footer").empty()
            $(".footer").append(`
                <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
            `)
        }
    }
});