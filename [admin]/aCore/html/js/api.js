const API = (() => {
    const _cb = {};

    window.addEventListener('message', e => {
        const { type, data, total, page, message, notifyType, adminName, level, ranks, maxLevel, mode } = e.data || {};
        if (!type) return;

        switch (type) {
            case 'open':
                App.open(level, ranks, maxLevel, mode);
                break;
            case 'close':
                App.close();
                break;
            case 'setLevel':
                App.setLevel(level);
                break;
            case 'syncRankNames':
                App.syncRankNames(e.data.data || {});
                break;
            case 'updatePlayers':
                App.renderPlayers(data || []);
                break;
            case 'updateBans':
                App.renderBans(data || [], total || 0, page || 1);
                break;
            case 'updateReports':
                App.renderReports(data || []);
                break;
            case 'updateGiftcodes':
                App.renderGiftcodes(data || []);
                break;
            case 'showInfo':
                App.showPlayerInfo(data);
                break;
            case 'announce':
                App.showAnnounce(message, adminName);
                break;
        }
    });

    function post(event, data) {
        fetch(`https://${GetParentResourceName()}/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    return {
        close:      ()           => post('close'),
        getPlayers: ()           => post('getPlayers'),
        getBans:    (page)       => post('getBans',  { page }),
        getReports: ()           => post('getReports'),
        reportAction: (data)     => post('reportAction', data),
        cancelMyReport: ()       => post('cancelMyReport'),
        action:     (data)       => post('action', data),
        getGiftcodes: ()         => post('getGiftcodes'),
        deleteGiftcode: (code)   => post('deleteGiftcode', { code }),
    };
})();
