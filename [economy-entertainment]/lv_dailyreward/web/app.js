const app = document.getElementById('app');
const freeRewardsEl = document.getElementById('free-rewards');
const premiumRewardsEl = document.getElementById('premium-rewards');
const premiumTrackEl = document.getElementById('premium-track');
const claim = document.getElementById('claim');
const claimPastPremiumBtn = document.getElementById('claim-past-premium');
let state;
let rewards = { free: [], premium: [] };
let pass = { milestones: [], freeLabel: 'FREE REWARDS', premiumLabel: 'PRIME REWARDS' };

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  });
}

function hasDay(mask, day) {
  const value = Number(mask) || 0;
  return (value & (2 ** (day - 1))) !== 0;
}

function isMilestone(day) {
  return (pass.milestones || []).includes(day);
}

function rewardImage(reward) {
  if (reward.image) return reward.image;
  if (reward.metadata && reward.metadata.imageurl) return reward.metadata.imageurl;
  const itemName = reward.type === 'item' ? reward.item : reward.type === 'magazine' ? 'magazine' : 'money';
  return `https://cfx-nui-ox_inventory/web/images/${itemName}.png`;
}

function rewardAmount(reward) {
  const amount = Number(reward.amount || 0).toLocaleString('vi-VN');
  return reward.type === 'item' || reward.type === 'gacha_crate' ? `${amount}x` : `$${amount}`;
}

function cardStatus(track, day) {
  const trackMask = track === 'premium' ? state.premiumClaimedDays : state.freeClaimedDays;
  const received = hasDay(trackMask, day);
  const checked = hasDay(state.claimedDays, day);
  const current = day === state.claimDay && !state.completed;

  if (received) return { label: 'ĐÃ NHẬN', className: 'claimed' };
  if (track === 'premium' && checked && hasDay(state.premiumAccessDays, day)) {
    return { label: 'NHẬN BÙ', className: 'claimable-past' };
  }
  if (checked) return { label: 'ĐÃ BỎ LỠ', className: 'missed' };
  if (track === 'premium' && !hasDay(state.premiumAccessDays, day)) {
    return { label: 'ĐANG KHÓA', className: 'locked' };
  }
  if (current && state.canClaim) return { label: 'CÓ THỂ NHẬN', className: 'current' };
  if (current) return { label: 'HÔM NAY', className: 'current waiting' };
  return { label: 'CHƯA MỞ', className: '' };
}

function renderTrack(element, track, trackRewards) {
  element.innerHTML = trackRewards.slice(0, state.passDays).map((reward, index) => {
    const day = index + 1;
    const status = cardStatus(track, day);
    const milestone = isMilestone(day);
    return `
      <article class="card ${reward.accent || ''} ${status.className} ${milestone ? 'milestone' : ''}" data-track="${track}" data-day="${day}">
        <div class="card-top">
          <span class="day">NGÀY ${day}</span>
          ${milestone ? '<span class="milestone-badge">MỐC</span>' : ''}
        </div>
        <div class="icon"><img src="${rewardImage(reward)}" alt="${reward.label}"></div>
        <div>
          <div class="name">${reward.label}</div>
          <div class="amount">${rewardAmount(reward)}</div>
        </div>
        <span class="tag">${status.label}</span>
      </article>`;
  }).join('');
}

function renderStatus() {
  document.getElementById('streak').textContent = `${state.streak} / ${state.passDays} ngày`;

  if (state.completed) {
    document.getElementById('status').textContent = 'Bạn đã hoàn thành toàn bộ Daily Pass 30 ngày.';
  } else if (state.claimedToday) {
    document.getElementById('status').textContent = `Đã điểm danh Ngày ${state.claimDay}. Hãy quay lại vào ngày mai.`;
  } else if (state.requiredOnlineMinutes > 0 && state.onlineMinutes < state.requiredOnlineMinutes) {
    document.getElementById('status').textContent =
      `Cần online hợp lệ ${state.onlineMinutes}/${state.requiredOnlineMinutes} phút để điểm danh hôm nay.`;
  } else if (state.reset && state.checkedDayBefore) {
    document.getElementById('status').textContent =
      'Bạn đã bỏ lỡ một ngày. Tiến độ về Ngày 1 và quà mốc cũ sẽ không được nhận lại.';
  } else if (state.reset) {
    document.getElementById('status').textContent =
      'Bạn đã bỏ lỡ một ngày — tiến độ hôm nay bắt đầu lại từ Ngày 1.';
  } else if (state.checkedDayBefore) {
    document.getElementById('status').textContent =
      `Ngày ${state.claimDay} đã từng điểm danh. Hôm nay chỉ cập nhật lại tiến độ.`;
  } else {
    document.getElementById('status').textContent =
      `Đủ thời gian online. Hôm nay mở phần thưởng Ngày ${state.claimDay}.`;
  }

  claim.disabled = !state.canClaim;
  claim.textContent = state.completed
    ? 'ĐÃ HOÀN THÀNH DAILY PASS'
    : state.claimedToday
      ? 'ĐÃ ĐIỂM DANH HÔM NAY'
      : state.checkedDayBefore
        ? 'ĐIỂM DANH LẠI MỐC NÀY'
        : 'ĐIỂM DANH & NHẬN QUÀ';

  if (state.unclaimedPremiumCount > 0) {
    claimPastPremiumBtn.classList.remove('hidden');
    claimPastPremiumBtn.textContent = `NHẬN BÙ PRIME (${state.unclaimedPremiumCount} MỐC)`;
  } else {
    claimPastPremiumBtn.classList.add('hidden');
  }

  premiumTrackEl.classList.toggle('track-locked', state.premiumTier === 'none');
  premiumTrackEl.classList.toggle('track-partial', state.premiumTier === 'prime');
  document.getElementById('premium-status').textContent = state.premiumTier === 'prime_plus'
    ? 'Prime Plus · mở đủ 30 ngày'
    : state.premiumTier === 'prime'
      ? 'Prime · Quà dành cho Prime/Prime Plus'
      : 'Yêu cầu Prime hoặc Prime Plus';
}

function render() {
  renderStatus();
  document.getElementById('free-label').textContent = pass.freeLabel || 'FREE REWARDS';
  document.getElementById('premium-label').textContent = pass.premiumLabel || 'PRIME REWARDS';
  renderTrack(freeRewardsEl, 'free', rewards.free || []);
  renderTrack(premiumRewardsEl, 'premium', rewards.premium || []);
}

window.addEventListener('message', ({ data }) => {
  if (data.action === 'close') {
    app.classList.add('hidden');
    return;
  }
  if (data.action === 'open') {
    state = data.state;
    rewards = data.rewards || rewards;
    pass = data.pass || pass;
    document.getElementById('title').textContent = data.title || 'Daily Pass';
    app.classList.remove('hidden');
    render();
  }
  if (data.action === 'update') {
    state = data.state;
    render();
  }
});

claim.addEventListener('click', () => post('claim'));
claimPastPremiumBtn.addEventListener('click', () => post('claimPastPremium'));
document.getElementById('close').addEventListener('click', () => post('close'));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') post('close');
});

document.addEventListener('click', event => {
  const card = event.target.closest('.card.claimable-past');
  if (card) {
    const day = Number(card.dataset.day);
    if (day) post('claimPastPremium', { day });
  }
});
