'use strict';

const RESOURCE = 'lv_idcard';
let currentCardId = null;
let photoDebounce = null;

const $ = id => document.getElementById(id);

function nuiPost(endpoint, data = {}) {
    const resourceName = typeof GetParentResourceName !== 'undefined' ? GetParentResourceName() : RESOURCE;
    return fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).catch((err) => {
        console.error('NUI Post error:', err);
    });
}

function closeUI() {
    showView(null);
    nuiPost('closeUI');
}

function showError(msg) {
    const el = $('form-error');
    const txt = $('form-error-text');
    if (el && txt) {
        txt.textContent = msg;
        el.classList.remove('hidden');
        setTimeout(() => el.classList.add('hidden'), 4000);
    }
}

function parseToDate(val) {
    if (!val) return null;
    if (val instanceof Date) return val;
    const num = Number(val);
    if (!isNaN(num) && String(val).trim() !== '' && num > 100000000) {
        return new Date(num);
    }
    if (typeof val === 'string') {
        const iso = val.replace(/(\d{2})\/(\d{2})\/(\d{4})/, '$3-$2-$1');
        const d = new Date(iso + (iso.length === 10 ? 'T00:00:00' : ''));
        if (!isNaN(d)) return d;
    }
    const dDirect = new Date(val);
    if (!isNaN(dDirect)) return dDirect;
    return null;
}

function formatDateCard(str) {
    const d = parseToDate(str);
    if (!d) return str || '';
    return `${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}/${d.getFullYear()}`;
}

function formatExpiry(str) {
    const d = parseToDate(str);
    if (!d) return str || '';
    return `${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
}

function normalizeToISO(str) {
    const d = parseToDate(str);
    if (!d) return '';
    try {
        return d.toISOString().substring(0, 10);
    } catch (e) {
        return '';
    }
}

function generateMRZ(card) {
    const ln = (card.lastname || '').toUpperCase().replace(/\s/g, '<').padEnd(9, '<');
    const fn = (card.firstname || '').toUpperCase().replace(/\s/g, '<').padEnd(9, '<');
    const id = (card.id_number || '').replace('I', '').padStart(8, '0');
    const dob = (card.dob || '').replace(/[^\d]/g, '').substring(2, 8);
    return `IDSA${ln}${fn}<<${id}<${dob}<<<`;
}

function setPermitChip(id, enabled) {
    const el = $(id);
    if (!el) return 0;
    el.classList.toggle('active', enabled);
    el.classList.toggle('hidden', !enabled);
    return enabled ? 1 : 0;
}

function populateCard(card) {
    const seed = (Number(card.id || 0) * 135791 + 97531) % 9000000 + 1000000;
    const idNum = card.id_number || `I${seed}`;
    $('cd-id-number').textContent = idNum;
    $('cd-lastname').textContent = (card.lastname || '').toUpperCase();
    $('cd-firstname').textContent = (card.firstname || '').toUpperCase();
    $('cd-dob').textContent = formatDateCard(card.dob);
    $('cd-expire').textContent = formatDateCard(card.expire_date);
    $('cd-address').textContent = card.address || '';
    $('cd-issue').textContent = formatDateCard(card.issue_date);
    $('cd-sex').textContent = card.sex || '';
    $('cd-nationality').textContent = (card.nationality || '').toUpperCase();
    $('cd-hair').textContent = card.hair || '';
    $('cd-eyes').textContent = card.eyes || '';
    let heightVal = (card.height || '').trim();
    if (heightVal && !heightVal.toLowerCase().includes('cm') && !heightVal.toLowerCase().includes("'")) {
        heightVal = heightVal + ' cm';
    }
    $('cd-height').textContent = heightVal;

    let weightVal = (card.weight || '').trim();
    if (weightVal && !weightVal.toLowerCase().includes('kg') && !weightVal.toLowerCase().includes('lb')) {
        weightVal = weightVal + ' kg';
    }
    $('cd-weight').textContent = weightVal;
    $('cd-holo-text').textContent = `L-1 ${(card.lastname || '').toUpperCase().substring(0, 4)}`;
    $('cd-sig-text').textContent = `${card.firstname || ''} ${card.lastname || ''}`;
    $('cd-dd').textContent = generateMRZ(card);

    const hasDriverPermit = card.driver_license === 'PASS' || card.is_license_review;
    const hasWeaponPermit = card.weapon_license === 'PASS' || card.weapon_permit === 'PASS' || card.firearm_license === 'PASS' || card.is_weapon_review;
    const permitCount = setPermitChip('cd-driver-permit', hasDriverPermit) + setPermitChip('cd-weapon-permit', hasWeaponPermit);
    if ($('cd-permit-count')) $('cd-permit-count').textContent = String(permitCount).padStart(2, '0');
    if ($('cd-permit-empty')) $('cd-permit-empty').classList.toggle('hidden', permitCount > 0);

    const dobStamp = (card.dob || '').replace(/[^\d]/g, '').substring(2);
    $('cd-ghost-num').textContent = dobStamp;
    $('cd-photo-wm').textContent = dobStamp;

    const photo = card.photo_url || '';
    const img = $('cd-photo');
    const ghost = $('cd-ghost');
    const ph = $('cd-photo-ph');
    if (photo) {
        img.src = photo;
        ghost.src = photo;
        img.style.display = 'block';
        ghost.style.display = 'block';
        ph.style.display = 'none';
    } else {
        img.style.display = 'none';
        ghost.style.display = 'none';
        ph.style.display = 'flex';
    }
}

function showView(id) {
    document.querySelectorAll('.view').forEach(v => v.classList.add('hidden'));
    if (id) $(id).classList.remove('hidden');
}

function openForm(playerInfo) {
    const ln = $('f-lastname');
    const fn = $('f-firstname');
    const dob = $('f-dob');

    ln.value = (playerInfo.lastname || '').toUpperCase();
    fn.value = (playerInfo.firstname || '').toUpperCase();
    dob.value = normalizeToISO(playerInfo.dob || '');

    ln.readOnly = !!playerInfo.lastname;
    fn.readOnly = !!playerInfo.firstname;
    dob.readOnly = !!playerInfo.dob;

    const sex = playerInfo.sex || 'M';
    $('f-sex').value = sex;
    const mRadio = $('sex-m');
    const fRadio = $('sex-f');
    if (mRadio && fRadio) {
        mRadio.checked = sex === 'M';
        fRadio.checked = sex === 'F';
        mRadio.disabled = true;
        fRadio.disabled = true;
    }

    const nat = $('f-nationality');
    if (nat) {
        const currentNat = (playerInfo.nationality || '').trim().toUpperCase();
        if (currentNat) {
            let matchOpt = Array.from(nat.options).find(opt => 
                opt.value.toUpperCase() === currentNat || opt.textContent.toUpperCase().includes(currentNat)
            );
            if (matchOpt) {
                nat.value = matchOpt.value;
            } else {
                const opt = document.createElement('option');
                opt.value = currentNat;
                opt.textContent = currentNat;
                nat.appendChild(opt);
                nat.value = currentNat;
            }
            nat.disabled = true;
        } else {
            nat.disabled = false;
            nat.selectedIndex = 0;
        }
    }

    $('f-address').value = '';
    $('f-photo').value = '';
    $('photo-preview-img').style.display = 'none';
    $('photo-placeholder').style.display = 'flex';
    $('photo-status').textContent = '';
    $('photo-status').className = 'photo-url-status';

    const now = new Date();
    if ($('today-date')) $('today-date').textContent = String(now.getDate()).padStart(2, '0');
    if ($('today-month')) $('today-month').textContent = String(now.getMonth() + 1).padStart(2, '0');
    if ($('today-year')) $('today-year').textContent = now.getFullYear();

    if ($('paper-sig-name')) {
        const fnVal = (playerInfo.firstname || '').trim();
        const lnVal = (playerInfo.lastname || '').trim();
        $('paper-sig-name').textContent = `${fnVal} ${lnVal}`.trim();
    }

    $('form-error').classList.add('hidden');
    showView('form-view');
}

function showCard(card, isOwner, isPending) {
    currentCardId = card.id;
    populateCard(card);

    const policePanel = $('police-actions');
    if (isPending) {
        policePanel.classList.remove('hidden');
        const btnApprove = $('btn-approve-card');
        const btnReject = $('btn-reject-card');
        if (card.is_license_review) {
            btnApprove.innerHTML = '<i class="fas fa-check-circle"></i> Duyệt Tích Hợp ($2,500)';
            btnApprove.onclick = () => nuiPost('approveCard', { id: currentCardId, isLicenseReview: true });
            btnReject.onclick = () => nuiPost('rejectCard', { id: currentCardId, isLicenseReview: true });
        } else if (card.is_weapon_review) {
            btnApprove.innerHTML = '<i class="fas fa-check-circle"></i> Duyệt Bằng Súng ($10,000)';
            btnApprove.onclick = () => nuiPost('approveCard', { id: currentCardId, isWeaponReview: true });
            btnReject.onclick = () => nuiPost('rejectCard', { id: currentCardId, isWeaponReview: true });
        } else {
            btnApprove.innerHTML = '<i class="fas fa-check-circle"></i> Duyệt & Cấp ($5,000)';
            btnApprove.onclick = () => nuiPost('approveCard', { id: currentCardId, isLicenseReview: false, photo_url: card.photo_url || '' });
            btnReject.onclick = () => nuiPost('rejectCard', { id: currentCardId, isLicenseReview: false });
        }
    } else {
        policePanel.classList.add('hidden');
    }
    showView('card-view');
}

function loadPhotoPreview(url) {
    const img = $('photo-preview-img');
    const ph = $('photo-placeholder');
    const status = $('photo-status');
    if (!url || !url.startsWith('http')) {
        img.style.display = 'none';
        ph.style.display = 'flex';
        status.textContent = '';
        status.className = 'photo-url-status';
        return;
    }
    const testImg = new Image();
    testImg.onload = () => {
        img.src = url;
        img.style.display = 'block';
        ph.style.display = 'none';
        status.textContent = '✓ Ảnh hợp lệ';
        status.className = 'photo-url-status ok';
    };
    testImg.onerror = () => {
        img.style.display = 'none';
        ph.style.display = 'flex';
        status.textContent = '✗ Không tải được ảnh – kiểm tra lại URL';
        status.className = 'photo-url-status error';
    };
    testImg.src = url;
}

window.addEventListener('message', e => {
    const { action, playerInfo, card, isOwner } = e.data;
    if (action === 'openForm') openForm(playerInfo);
    if (action === 'showCard') showCard(card, isOwner, false);
    if (action === 'showPendingCard') showCard(card, false, true);
    if (action === 'closeUI') showView(null);
});

document.addEventListener('DOMContentLoaded', () => {
    $('form-close-btn').addEventListener('click', closeUI);
    $('btn-cancel').addEventListener('click', closeUI);
    $('btn-close-card').addEventListener('click', closeUI);

    const overlay = $('form-overlay');
    if (overlay) overlay.addEventListener('click', closeUI);

    $('btn-submit').addEventListener('click', () => {
        const firstname = $('f-firstname').value.trim();
        const lastname = $('f-lastname').value.trim();
        const dob = $('f-dob').value.trim();
        const address = $('f-address').value.trim();
        const photo_url = $('f-photo').value.trim();
        const nationality = $('f-nationality').value.trim();
        const sex = $('f-sex') ? $('f-sex').value : 'M';

        if (!firstname || !lastname) {
            showError('Vui lòng điền đầy đủ họ và tên.');
            $('btn-submit').classList.add('shake');
            setTimeout(() => $('btn-submit').classList.remove('shake'), 500);
            return;
        }
        if (!dob) {
            showError('Vui lòng chọn ngày sinh.');
            return;
        }
        if (!nationality) {
            showError('Vui lòng điền quốc tịch.');
            return;
        }
        if (!address) {
            showError('Vui lòng điền địa chỉ thường trú.');
            return;
        }
        const height = $('f-height').value.trim();
        const weight = $('f-weight').value.trim();
        if (!height || isNaN(height) || Number(height) <= 0) {
            showError('Chiều cao phải là số hợp lệ (Ví dụ: 175).');
            $('f-height').focus();
            return;
        }
        if (!weight || isNaN(weight) || Number(weight) <= 0) {
            showError('Cân nặng phải là số hợp lệ (Ví dụ: 65).');
            $('f-weight').focus();
            return;
        }


        nuiPost('submitForm', {
            firstname, lastname, dob, address, sex, photo_url, nationality,
            hair: $('f-hair').value,
            eyes: $('f-eyes').value,
            height: height,
            weight: weight
        });
    });

    $('f-photo').addEventListener('input', e => {
        clearTimeout(photoDebounce);
        photoDebounce = setTimeout(() => loadPhotoPreview(e.target.value.trim()), 600);
    });

    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') closeUI();
    }, true);
});
