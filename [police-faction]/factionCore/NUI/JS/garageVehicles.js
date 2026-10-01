var currentGarageId;
var currentFactionId;

window.addEventListener('message', function (event) {
    var data = event.data;

    if (data.display === true && data.edit === 'garage_vehicles') {
        if (data.update === false) {
            currentFactionId = data.id;
            currentGarageId = data.garageId;

            $('.content').empty();
            $('.content').append(`
                <div style="margin-bottom: 15px;">
                    <h3>Garage #${currentGarageId} - Vehicles</h3>
                </div>
                <table id="vehicleList">
                    <tr>
                        <th>Phương tiện</th>
                        <th>Biển số</th>
                        <th>Lần cuối sử dụng</th>
                        <th>Action</th>
                    </tr>
                </table>
            `);

            $(".footer").empty();
            $(".footer").append(`
                <input type="text" id="newVehicleModel" placeholder="Tên model xe..." class="input" style="width: 200px; padding: 5px; margin-right: 10px;">
                <input type="text" id="newVehiclePlate" placeholder="Biển số (Để trống tự Random)" class="input" style="width: 200px; padding: 5px; margin-right: 10px;">
                <label style="color: white; margin-right: 10px; display: inline-flex; align-items: center; gap: 5px; cursor: pointer;">
                    <input type="checkbox" id="newVehicleChooseColor"> Chọn màu khi spawn
                </label>
                <button class="button buttonConfirm" onclick="CreateVehicle()">Tạo Phương Tiện</button>
                <button class="button buttonClosed" onclick="BackToGarage()">Quay lại</button>
            `);
        }

        if (data.update === true) {
            let lastDriver = data.lastDriver ? data.lastDriver : "Không có";
            let vName = data.name.charAt(0).toUpperCase() + data.name.slice(1);
            if (data.name === 'police') vName = 'Police Cruiser';
            
            $("#vehicleList").append(`
                <tr>
                    <td>${vName}</td>
                    <td>${data.plate}</td>
                    <td>${lastDriver}</td>
                    <td>
                        <button class="button buttonRemove" onclick="RemoveVehicle('${data.plate}')">Xóa</button>
                    </td>
                </tr>
            `);
        }
    }
});

function CreateVehicle() {
    let model = $("#newVehicleModel").val();
    let plate = $("#newVehiclePlate").val();
    let chooseColor = $("#newVehicleChooseColor").is(":checked");
    if (!model || model.trim() === "") {
        return;
    }
    $.post('https://factionCore/CreateGarageVehicle', JSON.stringify({
        id: currentFactionId, 
        garageId: currentGarageId,
        model: model.trim(),
        plate: plate.trim(),
        chooseColor: chooseColor
    }));
    $("#newVehicleModel").val('');
    $("#newVehiclePlate").val('');
}

function RemoveVehicle(plate) {
    $.post('https://factionCore/RemoveGarageVehicle', JSON.stringify({
        id: currentFactionId, 
        garageId: currentGarageId,
        plate: plate
    }));
}

function BackToGarage() {
    SelectMenu('garage', currentFactionId);
}
