const checkURL = "https://gta-api.avscripts.net/alpr/check";

const isServer = IsDuplicityVersion();

if (isServer) {
    onNet("av_alpr:scanPlate", (plate) => {
        const src = source;
        const ped = GetPlayerPed(src);
        if (ped && DoesEntityExist(ped)) {
            const vehicle = GetVehiclePedIsIn(ped, false);
            if (vehicle && DoesEntityExist(vehicle)) {
                const model = GetEntityModel(vehicle);
                if (IsThisModelAPoliceCar(model)) {
                    PerformHttpRequest(checkURL + "?plate=" + encodeURIComponent(plate), (statusCode, response, headers) => {
                        if (statusCode === 200) {
                            try {
                                const data = JSON.parse(response);
                                if (data && data.warrant) {
                                    emitNet("av_alpr:warrantFound", src, plate, data.reason);
                                }
                            } catch (e) {
                                console.error("[av_alpr] Error parsing JSON response from API: ", e.message);
                            }
                        }
                    }, "GET");
                }
            }
        }
    });
} else {

    let inPoliceVehicle = false;

    setInterval(() => {
        const ped = PlayerPedId();
        if (IsPedInAnyVehicle(ped, false)) {
            const vehicle = GetVehiclePedIsIn(ped, false);
            const model = GetEntityModel(vehicle);
            if (IsThisModelAPoliceCar(model)) {
                if (GetPedInVehicleSeat(vehicle, -1) === ped) {
                    inPoliceVehicle = true;
                } else {
                    inPoliceVehicle = false;
                }
            } else {
                inPoliceVehicle = false;
            }
        } else {
            inPoliceVehicle = false;
        }
    }, 1000);
}
