const App = (() => {
    let state = {
        level: 0,
        maxLevel: 5,
        rankNames: {},
        players: [],
        filteredPlayers: [],
        reports: [],
        selectedPlayer: null,
        banPage: 1,
        banTotal: 0,
        mode: 'admin',
    };

    const $ = id => document.getElementById(id);

    // ─── OPEN / CLOSE ───────────────────────────────────────
    function open(level, ranks, maxLevel, mode) {
        state.level = level || 0;
        state.maxLevel = maxLevel || 5;
        state.rankNames = ranks || {};
        state.mode = mode || 'admin';
        $('panel').classList.remove('hidden');
        applyPanelMode();
        updateHeaderRank();
        if (state.mode === 'reports') {
            switchTab('reports');
            API.getReports();
        } else {
            switchTab('players');
            API.getPlayers();
        }
    }

    function close() {
        $('panel').classList.add('hidden');
        $('action-modal').classList.add('hidden');
        API.close();
    }

    function setLevel(level) {
        state.level = level;
        updateHeaderRank();
    }

    function syncRankNames(cache) {
        state.rankNames = cache;
        updateHeaderRank();
    }

    function updateHeaderRank() {
        const el = $('header-rank');
        const r = state.rankNames[state.level];
        el.textContent = (r && r.name) || ('Level ' + state.level);
        el.style.color = (r && r.color) || '#4f7cff';
        el.style.borderColor = ((r && r.color) || '#4f7cff') + '55';
        el.style.background = ((r && r.color) || '#4f7cff') + '18';
    }

    function applyPanelMode() {
        document.querySelectorAll('.tab-btn').forEach(btn => {
            const tab = btn.dataset.tab;
            let hide = state.mode === 'reports'
                ? tab !== 'reports'
                : tab === 'reports';
            if (tab === 'giftcodes' && state.level < 4) {
                hide = true;
            }
            btn.classList.toggle('hidden', hide);
        });

        const title = document.querySelector('.header-title');
        if (title) title.textContent = state.mode === 'reports' ? 'REPORT PANEL' : 'ADMIN PANEL';
    }

    // ─── TABS ────────────────────────────────────────────────
    function switchTab(tab) {
        if (state.mode === 'admin' && tab === 'reports') tab = 'players';
        if (state.mode === 'reports') tab = 'reports';

        document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.toggle('active', c.id === 'tab-' + tab));

        if (tab === 'bans') API.getBans(state.banPage);
        if (tab === 'reports') API.getReports();
        if (tab === 'giftcodes') API.getGiftcodes();
    }

    // ─── PLAYERS ─────────────────────────────────────────────
    function renderPlayers(players) {
        state.players = players;
        state.filteredPlayers = players;
        $('player-count').textContent = players.length + ' player(s)';
        _drawPlayerList(players);
    }

    function filterPlayers(query) {
        const q = query.trim().toLowerCase();
        state.filteredPlayers = q
            ? state.players.filter(p => p.name.toLowerCase().includes(q) || String(p.id).includes(q))
            : state.players;
        _drawPlayerList(state.filteredPlayers);
    }

    function _drawPlayerList(players) {
        const el = $('player-list');
        if (!players.length) {
            el.innerHTML = '<div class="empty-state" style="height:80px;font-size:12px;color:var(--text-muted)">Không có người chơi</div>';
            return;
        }
        el.innerHTML = players.map(p => {
            const initial = p.name.charAt(0).toUpperCase();
            const pingCls = p.ping < 80 ? 'ping-good' : p.ping < 180 ? 'ping-ok' : 'ping-bad';
            const rankTag = p.adminLevel >= 1
                ? `<span class="rank-tag" style="background:${p.adminColor || '#4f7cff'}22;color:${p.adminColor || '#4f7cff'};border:1px solid ${p.adminColor || '#4f7cff'}44">${p.adminName || 'Lv' + p.adminLevel}</span>`
                : '';
            return `<div class="player-card" data-id="${p.id}" onclick="App.selectPlayer(${p.id})">
                <div class="player-avatar">${initial}</div>
                <div class="player-info">
                    <div class="player-name">${escHtml(p.name)} ${rankTag}</div>
                    <div class="player-meta">ID:${p.id} · ${escHtml(p.job)}</div>
                </div>
                <div class="player-ping ${pingCls}">${p.ping}ms</div>
            </div>`;
        }).join('');
    }

    function selectPlayer(id) {
        state.selectedPlayer = state.players.find(p => p.id === id) || null;
        document.querySelectorAll('.player-card').forEach(c => c.classList.toggle('selected', Number(c.dataset.id) === id));
        API.action({ action: 'getinfo', id });
    }

    function showPlayerInfo(info) {
        if (!info) return;
        state.selectedPlayer = info;
        const el = $('player-detail');
        const myLevel = state.level;
        const targetLevel = info.adminLevel || 0;
        const rankLabel = info.adminName || ('Level ' + targetLevel);
        const rankColor = info.adminColor || '#ffffff';

        const canKick      = myLevel >= 2;
        const canWarn      = myLevel >= 2;
        const canFreeze    = myLevel >= 2;
        const canSpectate  = myLevel >= 1;
        const canBan       = myLevel >= 4;
        const canRevive    = myLevel >= 2;
        const canCheckinv  = myLevel >= 2;
        const canGoto      = myLevel >= 1;
        const canGethere   = myLevel >= 1;
        const canSetLevel  = myLevel >= 4 && targetLevel < myLevel;
        const canSetPrime  = myLevel >= 4;
        const canSetWatchdog = myLevel >= 4;

        el.innerHTML = `
        <div class="detail-header">
            <div class="detail-avatar">${info.name.charAt(0).toUpperCase()}</div>
            <div>
                <div class="detail-name">${escHtml(info.name)}</div>
                <div class="detail-id">ID: ${info.id} · ${escHtml(info.identifier || '')} · Ping: ${info.ping}ms</div>
            </div>
        </div>
        <div class="info-grid">
            <div class="info-item"><div class="info-label">Job</div><div class="info-value">${escHtml(info.job || 'N/A')} (${escHtml(info.jobGrade || 'N/A')})</div></div>
            <div class="info-item"><div class="info-label">Tiền mặt</div><div class="info-value">$${(info.money || 0).toLocaleString()}</div></div>
            <div class="info-item"><div class="info-label">Ngân hàng</div><div class="info-value">$${(info.bank || 0).toLocaleString()}</div></div>
            <div class="info-item"><div class="info-label">Cảnh cáo</div><div class="info-value" style="color:${info.warns > 0 ? 'var(--warning)' : 'inherit'}">${info.warns || 0} lần</div></div>
            <div class="info-item"><div class="info-label">Lần bị ban</div><div class="info-value" style="color:${info.bans > 0 ? 'var(--danger)' : 'inherit'}">${info.bans || 0} lần</div></div>
            <div class="info-item"><div class="info-label">Cấp bậc</div><div class="info-value" style="color:${rankColor}">${rankLabel}</div></div>
            <div class="info-item" style="grid-column:1/-1"><div class="info-label">Tọa độ</div><div class="info-value">${info.coords ? `X:${info.coords.x} Y:${info.coords.y} Z:${info.coords.z}` : 'N/A'}</div></div>
        </div>
        <div class="action-grid">
            <button class="action-btn" ${!canGoto ? 'disabled' : ''} onclick="App.doAction('goto')">Teleport đến</button>
            <button class="action-btn" ${!canGethere ? 'disabled' : ''} onclick="App.doAction('gethere')">Kéo về</button>
            <button class="action-btn" ${!canSpectate ? 'disabled' : ''} onclick="App.doAction('spectate')">Spectate</button>
            <button class="action-btn" ${!canCheckinv ? 'disabled' : ''} onclick="App.doAction('checkinv')">Check Inv</button>
            <button class="action-btn warn" ${!canWarn ? 'disabled' : ''} onclick="App.doActionPrompt('warn','Lý do cảnh cáo:')">Warn</button>
            <button class="action-btn" ${!canFreeze ? 'disabled' : ''} onclick="App.doAction('freeze')">Freeze</button>
            <button class="action-btn success" ${!canRevive ? 'disabled' : ''} onclick="App.doAction('revive')">Revive</button>
            <button class="action-btn danger" ${!canKick ? 'disabled' : ''} onclick="App.doActionPrompt('kick','Lý do kick:')">Kick</button>
            <button class="action-btn danger" ${!canBan ? 'disabled' : ''} onclick="App.doActionBan()">Ban</button>
            ${canSetLevel ? `<button class="action-btn" onclick="App.doActionSetLevel()">Set Level</button>` : ''}
            ${canSetWatchdog ? `<button class="action-btn" style="background-color: #94a3b822; color: #94a3b8; border-color: #94a3b855;" onclick="App.doAction('setwatchdog')">${info.isWatchdog ? 'Xóa Watchdog' : 'Set Watchdog'}</button>` : ''}
            ${canSetPrime ? `<button class="action-btn" style="background-color: #ffd70018; color: #ffd700; border-color: #ffd70055;" onclick="App.doActionPrime()">Quản lý Prime</button>` : ''}
        </div>`;
    }

    // ─── ACTIONS ─────────────────────────────────────────────
    function doAction(action) {
        if (!state.selectedPlayer) return;
        API.action({ action, id: state.selectedPlayer.id });
    }

    function doActionPrompt(action, label) {
        if (!state.selectedPlayer) return;
        openModal(action.toUpperCase(), `
            <p>${escHtml(label)}</p>
            <input class="modal-input" id="modal-reason" type="text" placeholder="Nhập lý do..." autofocus>
        `, () => {
            const reason = $('modal-reason').value.trim();
            if (!reason) return;
            API.action({ action, id: state.selectedPlayer.id, reason });
            closeModal();
        });
    }

    function doActionBan() {
        if (!state.selectedPlayer) return;
        openModal('BAN NGƯỜI CHƠI', `
            <p>Ban: <b>${escHtml(state.selectedPlayer.name)}</b></p>
            <span class="modal-label">Lý do:</span>
            <input class="modal-input" id="modal-reason" type="text" placeholder="Nhập lý do..." autofocus>
        `, () => {
            const reason   = $('modal-reason').value.trim() || 'Không có lý do';
            API.action({ action: 'ban', id: state.selectedPlayer.id, reason });
            closeModal();
        });
    }

    function doActionSetLevel() {
        if (!state.selectedPlayer) return;
        const maxSet = state.level >= state.maxLevel ? state.maxLevel : state.level - 1;
        openModal('ĐẶT CẤP ADMIN', `
            <p>Đặt cấp cho: <b>${escHtml(state.selectedPlayer.name)}</b></p>
            <span class="modal-label">Level (0 = xóa quyền, max ${maxSet}):</span>
            <input class="modal-input" id="modal-level" type="number" value="0" min="0" max="${maxSet}">
        `, () => {
            const level = parseInt($('modal-level').value) || 0;
            API.action({ action: 'setlevel', id: state.selectedPlayer.id, level });
            closeModal();
        });
    }

    function doActionPrime() {
        if (!state.selectedPlayer) return;
        openModal('QUẢN LÝ PRIME', `
            <p>Set Prime cho: <b>${escHtml(state.selectedPlayer.name)}</b></p>
            <span class="modal-label">Thời gian (Ngày, 0 = Xóa Prime):</span>
            <input class="modal-input" id="modal-prime-days" type="number" value="30" min="0">
        `, () => {
            const days = parseInt($('modal-prime-days').value) || 0;
            API.action({ action: 'setprime', id: state.selectedPlayer.id, days });
            closeModal();
        });
    }

    // ─── BANS ────────────────────────────────────────────────
    function renderBans(bans, total, page) {
        state.banTotal = total;
        state.banPage  = page;
        $('ban-total').textContent = total + ' bản ghi';
        $('ban-page-info').textContent = 'Trang ' + page;
        $('ban-prev').disabled = page <= 1;
        $('ban-next').disabled = page * 20 >= total;

        const el = $('ban-list');
        if (!bans.length) {
            el.innerHTML = '<div style="text-align:center;padding:24px;color:var(--text-muted);font-size:13px">Không có dữ liệu ban</div>';
            return;
        }
        el.innerHTML = bans.map(b => {
            const isActive = b.active === 1;
            const duration = b.ban_duration ? (b.ban_duration + ' phút') : 'Vĩnh viễn';
            return `<div class="record-item">
                <div class="record-icon" style="background:rgba(245,101,101,0.12);color:var(--danger)"></div>
                <div class="record-body">
                    <div class="record-name">${escHtml(b.name || '?')}</div>
                    <div class="record-reason">${escHtml(b.reason)} · ${duration} · By: ${escHtml(b.banned_by_name || '?')}</div>
                </div>
                <div class="record-meta">
                    <div class="record-date">${fmtDate(b.created_at)}</div>
                    <div class="record-status ${isActive ? 'status-active' : 'status-inactive'}">${isActive ? 'ACTIVE' : 'Ended'}</div>
                    ${isActive && state.level >= 4 ? `<button class="ban-unban-btn" onclick="App.doUnban(${b.id})">Gỡ cấm</button>` : ''}
                </div>
            </div>`;
        }).join('');
    }

    function doUnban(defaultId) {
        openModal('GỠ CẤM (UNBAN)', `
            <span class="modal-label">Ban ID hoặc Identifier:</span>
            <input class="modal-input" id="modal-ban-id" type="text" value="${defaultId || ''}" placeholder="Nhập Ban ID (VD: 1)" autofocus>
            <span class="modal-label">Lý do:</span>
            <input class="modal-input" id="modal-unban-reason" type="text" placeholder="Kháng cáo thành công / Gỡ phạt">
        `, () => {
            const banId = $('modal-ban-id').value.trim();
            if (!banId) return;
            const reason = $('modal-unban-reason').value.trim();
            API.action({ action: 'unban', id: banId, reason });
            closeModal();
        });
    }

    function prevBanPage() { if (state.banPage > 1) { state.banPage--; API.getBans(state.banPage); } }
    function nextBanPage() { if (state.banPage * 20 < state.banTotal) { state.banPage++; API.getBans(state.banPage); } }

    // ─── GIFTCODES ───────────────────────────────────────────
    function renderGiftcodes(giftcodes) {
        $('giftcode-total').textContent = giftcodes.length + ' giftcode';

        const el = $('giftcode-list');
        if (!giftcodes.length) {
            el.innerHTML = '<div style="text-align:center;padding:24px;color:var(--text-muted);font-size:13px">Không có dữ liệu giftcode</div>';
            return;
        }
        el.innerHTML = giftcodes.map(g => {
            const expireStr = g.expire_at ? fmtDate(g.expire_at) : 'Không hết hạn';
            const maxUse = g.max_redeem > 0 ? g.max_redeem : '∞';
            const rewardTypeLabel = g.reward_type === 'item'
                ? 'Vật phẩm'
                : g.reward_type === 'vehicle'
                    ? 'Phương tiện'
                    : g.reward_type === 'prime'
                        ? 'Prime'
                        : g.reward_type === 'prime_plus'
                            ? 'Prime Plus'
                            : g.reward_type;
            return `<div class="record-item">
                <div class="record-icon" style="background:rgba(79,124,255,0.12);color:var(--accent)">🎁</div>
                <div class="record-body">
                    <div class="record-name">${escHtml(g.code)}</div>
                    <div class="record-reason">Phần quà: ${escHtml(g.reward)} (${rewardTypeLabel}) x${g.amount}</div>
                </div>
                <div class="record-meta">
                    <div class="record-date">Hạn dùng: ${expireStr}</div>
                    <div class="record-status status-active">Đã dùng: ${g.current_redeem}/${maxUse}</div>
                    <button class="ban-unban-btn" style="background-color: var(--danger); border-color: var(--danger);" onclick="App.doDeleteGiftcode('${escHtml(g.code)}')">Xóa</button>
                </div>
            </div>`;
        }).join('');
    }

    function doDeleteGiftcode(code) {
        openModal('XÓA GIFTCODE', `<p>Bạn có chắc chắn muốn xóa giftcode này?<br><code style="color:var(--danger)">${escHtml(code)}</code></p>`, () => {
            API.deleteGiftcode(code);
            closeModal();
        });
    }

    // ─── REPORTS ────────────────────────────────────────────
    function renderReports(reports) {
        state.reports = reports || [];
        const count = state.reports.length;
        $('report-total').textContent = count + ' report';

        const badge = $('report-count');
        badge.textContent = count;
        badge.classList.toggle('hidden', count <= 0);

        const el = $('report-list');
        if (!count) {
            el.innerHTML = '<div style="text-align:center;padding:30px;color:var(--text-muted);font-size:13px">Không có report đang mở</div>';
            return;
        }

        el.innerHTML = state.reports.map(report => {
            const isAdvisorTicket = report.status === 'advisor' || report.status === 'advisor_accepted';
            const statusLabel = reportStatusLabel(report.status);
            const accepted = report.acceptedName ? ` · Nhận bởi ${escHtml(report.acceptedName)}` : '';
            const pushed = report.pushedName ? ` · Đẩy bởi ${escHtml(report.pushedName)}` : '';
            
            // Accept conditions
            let canAccept = false;
            if (state.level >= 2) {
                // Admin can only accept open reports (not advisor or advisor_accepted)
                canAccept = report.status === 'open';
            } else if (state.level === 1) {
                // Advisor can only accept advisor reports
                canAccept = report.status === 'advisor';
            }

            const canPush = (report.status === 'open' || report.status === 'admin_accepted') && state.level >= 2;
            const canDeny = (report.status === 'open' || report.status === 'admin_accepted') && state.level >= 2;
            const canFinish = (report.status === 'admin_accepted' && state.level >= 2) || (report.status === 'advisor_accepted' && state.level === 1);
            
            // Delete conditions (Admins level >= 2 can delete)
            const showDelete = state.level >= 2;
            const canDelete = showDelete;

            return `<div class="report-card report-${escHtml(report.status)}">
                <div class="report-card-top">
                    <div>
                        <div class="report-title">Report #${report.id}</div>
                        <div class="report-meta">${escHtml(report.playerName || '?')} · ID ${report.playerId}${accepted}${pushed}</div>
                    </div>
                    <span class="report-status ${isAdvisorTicket ? 'advisor' : ''}">${statusLabel}</span>
                </div>
                <div class="report-message">${escHtml(report.message || '')}</div>
                <div class="report-actions">
                    <button class="action-btn success" ${!canAccept ? 'disabled' : ''} onclick="App.reportAction('accept', ${report.id})">Nhận</button>
                    <button class="action-btn" ${!canPush ? 'disabled' : ''} onclick="App.reportAction('push', ${report.id})">Đẩy Advisor</button>
                    <button class="action-btn danger" ${!canDeny ? 'disabled' : ''} onclick="App.denyReport(${report.id})">Từ chối</button>
                    <button class="action-btn warn" ${!canFinish ? 'disabled' : ''} onclick="App.reportAction('finish', ${report.id})">Kết thúc</button>
                    ${showDelete ? `<button class="action-btn danger" ${!canDelete ? 'disabled' : ''} onclick="App.reportAction('delete', ${report.id})">Xoá</button>` : ''}
                </div>
            </div>`;
        }).join('');
    }

    function reportStatusLabel(status) {
        const labels = {
            open: 'Mới',
            admin_accepted: 'Admin nhận',
            advisor: 'Advisor',
            advisor_accepted: 'Advisor nhận',
        };
        return labels[status] || status || 'Unknown';
    }

    function reportAction(action, id) {
        API.reportAction({ action, id });
    }

    function denyReport(id) {
        openModal('TỪ CHỐI REPORT', `
            <p>Từ chối report #${id}</p>
            <input class="modal-input" id="modal-report-reason" type="text" placeholder="Lý do..." autofocus>
        `, () => {
            const reason = $('modal-report-reason').value.trim() || 'Không phù hợp';
            API.reportAction({ action: 'deny', id, reason });
            closeModal();
        });
    }

    function showReportNotify() {}

    // ─── MODAL ───────────────────────────────────────────────
    function openModal(title, bodyHtml, onConfirm) {
        $('modal-title').textContent = title;
        $('modal-body').innerHTML = bodyHtml;
        $('modal-confirm').onclick = onConfirm;
        $('action-modal').classList.remove('hidden');
        const input = $('modal-body').querySelector('input');
        if (input) setTimeout(() => input.focus(), 50);
    }

    function closeModal() {
        $('action-modal').classList.add('hidden');
    }

    // ─── NOTIFY ──────────────────────────────────────────────
    function showNotify() {}

    // ─── ANNOUNCE ────────────────────────────────────────────
    function showAnnounce(msg, adminName) {
        const overlay = $('announce-overlay');
        $('announce-msg').textContent   = msg;
        $('announce-admin').textContent = 'Bởi: ' + (adminName || '?');
        overlay.classList.remove('hidden');
        setTimeout(() => overlay.classList.add('hidden'), 8000);
    }

    // ─── UTILS ───────────────────────────────────────────────
    function escHtml(str) {
        return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    function fmtDate(raw) {
        if (!raw) return '';
        const d = new Date(raw);
        if (isNaN(d)) return raw;
        return d.toLocaleDateString('vi-VN') + ' ' + d.toLocaleTimeString('vi-VN', {hour:'2-digit',minute:'2-digit'});
    }

    // ─── KEY: ESC to close ───────────────────────────────────
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') {
            if (!$('action-modal').classList.contains('hidden')) {
                closeModal();
            } else if (!$('panel').classList.contains('hidden')) {
                App.close();
            }
        }
    });

    return {
        open, close, setLevel, syncRankNames, switchTab,
        renderPlayers, filterPlayers, selectPlayer, showPlayerInfo,
        doAction, doActionPrompt, doActionBan, doActionSetLevel, doActionPrime, doUnban,
        renderBans, prevBanPage, nextBanPage,
        renderGiftcodes, doDeleteGiftcode,
        renderReports, reportAction, denyReport, showReportNotify,
        openModal, closeModal,
        showNotify, showAnnounce,
        get banPage() { return state.banPage; },
    };
})();
