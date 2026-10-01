const app=document.querySelector('#app'),content=document.querySelector('#content'),officer=document.querySelector('#officer'),toast=document.querySelector('#mdt-toast');let boot={},currentApp='mdt',tab='home',toastTimer;
function setTask(name){const el=document.querySelector('.task');if(el)el.textContent=name;}
function esc(value){return String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));}
function priority(value){return `<span class="badge ${esc(value)}">${esc(value).toUpperCase()}</span>`;}
function showNotice(message,type='error'){if(!toast)return;toast.textContent=message;toast.style.borderLeftColor=type==='success'?'#107c10':'#c42b1c';toast.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.hidden=true,4500);}
function request(action,payload={}){return fetch(`https://${GetParentResourceName()}/request`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...payload})}).then(r=>r.json());}
function confirmBolo(){return new Promise(resolve=>{const box=document.querySelector('#mdt-confirm');if(!box)return resolve(false);box.hidden=false;document.querySelector('#confirm-no').onclick=()=>{box.hidden=true;resolve(false)};document.querySelector('#confirm-yes').onclick=()=>{box.hidden=true;resolve(true)}});}

const mdtNavItems=[
  {id:'home',label:'Dashboard',icon:'fa-chart-line'},
  {id:'people',label:'Công dân',icon:'fa-user-shield'},
  {id:'vehicles',label:'Phương tiện',icon:'fa-car'},
  {id:'tickets',label:'Ticket',icon:'fa-receipt'},
  {id:'bolos',label:'BOLO',icon:'fa-triangle-exclamation'}
];

const cadNavItems=[
  {id:'cad-unit',label:'My Unit',icon:'fa-id-badge'},
  {id:'cad-roster',label:'Duty Roster',icon:'fa-users'},
  {id:'cad-911',label:'911 Calls',icon:'fa-phone-flip'},
  {id:'cad-codes',label:'Codes & Laws',icon:'fa-book'}
];

function renderNav(){
  const nav=document.querySelector('#app-nav');
  if(!nav) return;
  const items=currentApp==='cad'?cadNavItems:mdtNavItems;
  nav.innerHTML=items.map(item=>`<button data-tab="${item.id}" class="${tab===item.id?'active':''}"><i class="fa-solid ${item.icon}"></i> <span>${item.label}</span></button>`).join('');
  nav.querySelectorAll('button').forEach(btn=>btn.onclick=()=>setTab(btn.dataset.tab));
}

function setTab(next){
  tab=next;
  renderNav();
  render();
}

function launcher(){
  const win=document.querySelector('.window');
  if(win) win.style.display='none';
  setTask('Desktop');
}

function openApp(appType){
  const win=document.querySelector('.window');
  if(!win) return;
  win.style.display='flex';
  currentApp=appType;
  const title=document.querySelector('#win-app-title');
  const icon=document.querySelector('#win-app-icon');
  if(appType==='cad'){
    if(title) title.textContent='C.A.D Terminal';
    if(icon) icon.className='fa-solid fa-laptop-code win-app-icon';
    setTask('C.A.D Terminal');
    setTab('cad-unit');
  } else {
    if(title) title.textContent='MDT System';
    if(icon) icon.className='fa-solid fa-shield-halved win-app-icon';
    setTask('MDT System');
    setTab('home');
  }
}

function render(){
  if(tab==='home') return home();
  if(tab==='people') return people();
  if(tab==='vehicles') return vehicles();
  if(tab==='tickets') return tickets();
  if(tab==='bolos') return bolos();
  if(tab==='cad-unit') return cadUnit();
  if(tab==='cad-roster') return cadRoster();
  if(tab==='cad-911') return cad911();
  if(tab==='cad-codes') return cadCodes();
}

function home(){const bolos=boot.bolos||[];content.innerHTML=`<h1 class="title">Tổng quan MDT</h1><div class="grid"><div class="card"><h3>BOLO đang hiệu lực</h3><div>${bolos.length}</div></div><div class="card"><h3>Tra cứu công dân</h3><div class="muted">IDCard, xe sở hữu, ticket, lịch sử arrest</div></div><div class="card"><h3>Tra cứu phương tiện</h3><div class="muted">Biển số, chủ xe và cảnh báo</div></div></div><section class="panel"><h3>BOLO ưu tiên</h3>${bolos.slice(0,5).map(b=>`<div class="row" data-bolo="${b.id}">${priority(b.priority)} <strong>${esc(b.title)}</strong><span class="muted">${b.plate?'Biển số: ':b.idcard_no?'Số IDCard: ':''}${esc(b.plate||b.idcard_no||'')}</span></div>`).join('')||'<div class="empty">Không có BOLO hiệu lực.</div>'}</section>`;}
const getDutyBtnHtml=()=>`<div class="duty-status-container" style="display:inline-flex;align-items:center;gap:10px;"><span class="duty-badge" style="padding:4px 10px;border-radius:4px;font-weight:600;font-size:12px;display:inline-flex;align-items:center;gap:6px;background:${boot.onDuty?'rgba(16,124,16,0.18)':'rgba(196,43,28,0.18)'};color:${boot.onDuty?'#4ade80':'#f87171'};border:1px solid ${boot.onDuty?'#107c10':'#c42b1c'};"><i class="fa-solid fa-circle" style="font-size:8px;"></i>${boot.onDuty?'Đang ON DUTY':'Đang OFF DUTY'}</span><button class="${boot.onDuty?'secondary':'primary'}" id="cad-duty" style="font-weight:600;min-width:110px;">${boot.onDuty?'Tắt On Duty':'Bật On Duty'}</button></div>`;
const updateDutyBtnUI=()=>{const container=document.querySelector('.duty-wrap');if(container){container.innerHTML=getDutyBtnHtml();bindDutyBtn();}};
const bindDutyBtn=()=>{const btn=document.querySelector('#cad-duty');if(!btn)return;btn.onclick=async()=>{btn.disabled=true;btn.style.opacity='0.6';try{const r=await fetch(`https://${GetParentResourceName()}/toggleDuty`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).then(res=>res.json());if(r&&r.ok&&r.onDuty!==undefined){boot.onDuty=(r.onDuty===true);showNotice(boot.onDuty?'Đã chuyển sang ON DUTY.':'Đã chuyển sang OFF DUTY.',boot.onDuty?'success':'info');}}catch(e){}updateDutyBtnUI();};};

async function cadUnit(){
  const response=await request('cadMyUnit'),u=response.data||{},target=document.querySelector('#content');
  if(!target)return;
  target.innerHTML=`
    <section class="panel unit-panel">
      <div class="unit-header">
        <h3>Quản lý Unit (Sĩ quan)</h3>
        <div class="duty-wrap">${getDutyBtnHtml()}</div>
      </div>
      <div class="unit-grid">
        <div class="unit-card">
          <h4>Callsign Sĩ quan</h4>
          <div class="input-inline">
            <input id="cad-callsign" placeholder="Nhập callsign..." value="${esc(u.callsign||'')}">
            <button class="primary" id="cad-save-callsign">Lưu</button>
            <button class="secondary" id="cad-clear-callsign">Xóa</button>
          </div>
        </div>
        <div class="unit-card">
          <h4>Trạng thái & Vị trí</h4>
          <div class="form-row">
            <label>
              <span>Trạng thái (Status)</span>
              <select id="cad-status">
                ${['Available','Unavailable','Code 6','Code 6 ADAM','Code 6 CHARLES','Code 7','In TAC','Responding to Backup'].map(x=>`<option ${u.status===x?'selected':''}>${x}</option>`).join('')}
              </select>
            </label>
            <label>
              <span>Vị trí (Location)</span>
              <select id="cad-location">
                <option ${u.location==='Mobile'?'selected':''}>Mobile</option>
                <option ${u.location==='Station'?'selected':''}>Station</option>
                <option ${u.location==='Unknown'?'selected':''}>Unknown</option>
              </select>
            </label>
          </div>
          <div class="unit-actions">
            <button class="primary wide-btn" id="cad-save">Cập nhật Status</button>
          </div>
        </div>
      </div>
    </section>`;

  const payload=callsign=>({callsign,status:document.querySelector('#cad-status').value,location:document.querySelector('#cad-location').value});
  bindDutyBtn();

  document.querySelector('#cad-save-callsign').onclick=async()=>{
    const r=await request('cadSaveUnit',payload(document.querySelector('#cad-callsign').value));
    showNotice(r.ok?'Đã lưu callsign.':r.message,r.ok?'success':'error');
  };

  document.querySelector('#cad-clear-callsign').onclick=async()=>{
    document.querySelector('#cad-callsign').value='';
    const r=await request('cadSaveUnit',payload(''));
    showNotice(r.ok?'Đã xóa callsign.':r.message,r.ok?'success':'error');
  };

  document.querySelector('#cad-save').onclick=async()=>{
    const r=await request('cadSaveUnit',payload(undefined));
    showNotice(r.ok?'Đã lưu status.':r.message,r.ok?'success':'error');
  };
}

async function cadRoster(){const response=await request('cadRoster'),rows=response.data||[];const draw=term=>{content.innerHTML=`<section class="panel"><h3>Duty Roster</h3><div class="search"><input id="roster-search" placeholder="Tìm callsign hoặc tên sĩ quan" value="${esc(term)}"></div><table class="table"><tr><th>Unit</th><th>Occupants</th><th>Status</th><th>Location</th><th></th></tr>${rows.filter(u=>(u.callsign+' '+u.occupants.map(o=>o.name).join(' ')).toLowerCase().includes(term.toLowerCase())).map(u=>`<tr><td>${esc(u.callsign)}</td><td>${u.occupants.map(o=>`${esc(o.name)} <span class="muted">${esc(o.agency)}</span>`).join('<br>')}</td><td>${esc(u.status)}</td><td>${esc(u.location)}</td><td>${u.location==='Mobile'?`<button class="secondary" data-locate="${esc(u.callsign)}">Định vị</button>`:''}</td></tr>`).join('')||'<tr><td colspan="5">Không tìm thấy sĩ quan on-duty.</td></tr>'}</table></section>`;const input=document.querySelector('#roster-search');if(input){input.oninput=e=>draw(e.target.value);input.focus();input.setSelectionRange(term.length,term.length);}document.querySelectorAll('[data-locate]').forEach(button=>button.onclick=async()=>{const r=await request('cadLocate',{callsign:button.dataset.locate});showNotice(r.ok?'Đã đặt checkpoint tới unit.':r.message,r.ok?'success':'error');});};draw('');}
async function cad911(){const response=await request('cad911Calls'),calls=(response.data||[]).filter(call=>call.type==='police');content.innerHTML=`<section class="panel"><h3>911 Calls</h3><table class="table"><tr><th>Caller</th><th>Số điện thoại</th><th>Lý do</th><th>Nhận bởi</th><th></th></tr>${calls.map(call=>`<tr><td>${esc(call.callerName)}</td><td>${esc(call.callerPhone||'')}</td><td>${esc(call.reason)}</td><td>${esc(call.assignedName||'Chưa nhận')}</td><td>${call.status==='pending'?`<button class="primary" data-call="${call.id}">Nhận</button>`:call.status==='accepted'?`<button class="secondary" data-finish="${call.id}">Finish</button>`:''}</td></tr>`).join('')||'<tr><td colspan="5">Không có cuộc gọi 911 cho police.</td></tr>'}</table></section>`;document.querySelectorAll('[data-call]').forEach(button=>button.onclick=async()=>{await request('cad911Accept',{id:button.dataset.call});cad911();});document.querySelectorAll('[data-finish]').forEach(button=>button.onclick=async()=>{await request('cad911Finish',{id:button.dataset.finish});cad911();});}
async function cadCodes(){let book='penal',term='',section='';const draw=async()=>{const response=await request('cadCodeSearch',{book,term,section}),rows=response.data||[],sections=response.sections||[];content.innerHTML=`<section class="panel"><div class="topline"><div><h3>${book==='vehicle'?'San Andreas Vehicle Code':'San Andreas Penal Code'}</h3><div class="muted">San Andreas Law Enforcement Reference</div></div><div><button class="${book==='penal'?'primary':'secondary'}" id="code-penal">Penal Code</button><button class="${book==='vehicle'?'primary':'secondary'}" id="code-vehicle">Vehicle Code</button></div></div><div class="form"><label class="wide">Tra cứu đa năng<input id="code-term" placeholder="Mã luật, hành vi, mô tả hoặc tên section" value="${esc(term)}"></label><label class="wide">Section<select id="code-section"><option value="">Tất cả sections</option>${sections.map(value=>`<option value="${esc(value)}" ${section===value?'selected':''}>${esc(value)}</option>`).join('')}</select></label><div><button class="primary" id="code-search">Tra cứu</button></div></div><div class="muted">${rows.length} điều luật hiển thị</div><div class="list">${rows.map(row=>`<article class="row code-row"><div><strong>${esc(row.code)} · ${esc(row.title)}</strong><div class="muted">${esc(row.section||'San Andreas Code')}</div><p>${esc(row.description||'')}</p><span class="badge">${esc(row.category||'')}</span> <span class="muted">Phạt: $${Number(row.fine||0).toLocaleString('en-US')} · Giam giữ: ${esc(row.prison_months||0)} tháng</span></div></article>`).join('')||'<div class="empty">Không tìm thấy điều luật phù hợp.</div>'}</div></section>`;document.querySelector('#code-penal').onclick=()=>{book='penal';section='';draw()};document.querySelector('#code-vehicle').onclick=()=>{book='vehicle';section='';draw()};document.querySelector('#code-search').onclick=()=>{term=document.querySelector('#code-term').value;section=document.querySelector('#code-section').value;draw()};document.querySelector('#code-section').onchange=event=>{section=event.currentTarget.value;draw()};document.querySelector('#code-term').onkeydown=event=>{if(event.key==='Enter'){term=event.currentTarget.value;section=document.querySelector('#code-section').value;draw()}};};draw();}

function people(){content.innerHTML=`<h1 class="title">Tra cứu công dân</h1><div class="search"><input id="person-term" placeholder="Họ tên hoặc số IDCard"><button class="primary" id="person-search">Tìm kiếm</button></div><div id="results" class="list"><div class="empty">Nhập tối thiểu 2 ký tự để tìm.</div></div>`;document.querySelector('#person-search').onclick=async()=>{const data=await request('searchPeople',{term:document.querySelector('#person-term').value});const result=document.querySelector('#results');result.innerHTML=(data.data||[]).map(row=>`<div class="row" data-person="${esc(row.identifier)}"><img class="photo" src="${esc(row.photo_url||'')}"><div><strong>${esc(row.firstname)} ${esc(row.lastname)}</strong><div class="muted">Số IDCard: ${esc(row.idcard_no||'Chưa cấp')} · ${esc(row.dob||'')}</div></div></div>`).join('')||'<div class="empty">Không tìm thấy công dân.</div>';result.querySelectorAll('[data-person]').forEach(el=>el.onclick=()=>personDetail(el.dataset.person));};}
async function personDetail(identifier){const response=await request('personDetail',{identifier});const p=response.data;if(!p)return;const vehicles=(p.vehicles||[]).map(v=>`<tr data-plate="${esc(v.plate)}"><td>${esc(v.plate)}</td><td>${esc(v.model)}</td><td>${v.towed?'Bãi tạm giữ':v.stored?'Trong garage':'Đang lưu thông'}</td></tr>`).join('')||'<tr><td colspan="3">Không có xe sở hữu.</td></tr>';const tickets=(p.tickets||[]).map(t=>`<tr><td>${esc(t.ticket_no)}</td><td>${esc(t.violation)}</td><td>$${esc(t.fine_amount)}</td><td>${esc(t.status)}</td></tr>`).join('')||'<tr><td colspan="4">Không có ticket xử phạt.</td></tr>';const arrests=(p.arrests||[]).map(a=>`<tr><td>${esc(a.arrested_at)}</td><td>${esc(a.reason)}</td><td>${esc(a.final_minutes)} phút</td><td>${esc(a.officer_name)}</td></tr>`).join('')||'<tr><td colspan="4">Không có lịch sử bắt giữ.</td></tr>';content.innerHTML=`<div class="topline"><h1 class="title">Hồ sơ công dân</h1><button class="secondary" id="back">Quay lại</button></div>${(p.bolos||[]).map(b=>`<div class="alert">${priority(b.priority)} BOLO: ${esc(b.title)} — ${esc(b.reason)}</div>`).join('')}<section class="panel profile"><img class="photo" src="${esc(p.photo||'')}"><div><h2>${esc(p.name)}</h2><div>Số IDCard: ${esc(p.idcardNo||'Chưa cấp')}</div><div class="muted">${p.hasIdCard?'IDCard hợp lệ':'Chưa có IDCard hợp lệ'} · GPLX: ${esc(p.driverLicense)} · Giấy phép vũ khí: ${esc(p.weaponLicense)}</div><p>${esc(p.dob)} · ${esc(p.sex)} · ${esc(p.height)}<br>${esc(p.address)}</p></div></section><div class="cols"><section class="panel"><h3>Xe cá nhân sở hữu</h3><table class="table"><tr><th>Biển số</th><th>Xe</th><th>Trạng thái</th></tr>${vehicles}</table></section><section class="panel"><h3>Ticket xử phạt</h3><table class="table"><tr><th>Mã</th><th>Vi phạm</th><th>Phạt</th><th>Trạng thái</th></tr>${tickets}</table></section></div><section class="panel"><h3>Lịch sử bắt giữ</h3><table class="table"><tr><th>Thời gian</th><th>Lý do</th><th>Thời hạn</th><th>Sĩ quan</th></tr>${arrests}</table></section>`;document.querySelector('#back').onclick=people;}
function vehicles(){content.innerHTML=`<h1 class="title">Tra cứu phương tiện</h1><div class="search"><input id="plate-term" placeholder="Biển số xe"><button class="primary" id="plate-search">Tìm kiếm</button></div><div id="results" class="list"><div class="empty">Nhập tối thiểu 2 ký tự của biển số.</div></div>`;document.querySelector('#plate-search').onclick=async()=>{const data=await request('searchVehicles',{term:document.querySelector('#plate-term').value}),result=document.querySelector('#results');result.innerHTML=(data.data||[]).map(v=>`<div class="row" data-owner="${esc(v.ownerIdentifier)}"><div><strong>${esc(v.plate)} · ${esc(v.model)}</strong><div class="muted">Chủ xe: ${esc(v.ownerName)}</div>${(v.bolos||[]).map(b=>priority(b.priority)+' '+esc(b.title)).join('')}</div></div>`).join('')||'<div class="empty">Không tìm thấy xe.</div>';result.querySelectorAll('[data-owner]').forEach(el=>el.onclick=()=>personDetail(el.dataset.owner));};}
function ticketStatusBadge(status){
  const s=String(status||'').toLowerCase();
  if(s==='active') return `<span class="badge low">CHƯA ĐÓNG</span>`;
  if(s==='overdue') return `<span class="badge critical">TRỄ HẠN</span>`;
  if(s==='paid') return `<span class="badge">ĐÃ ĐÓNG</span>`;
  if(s==='void') return `<span class="badge high">ĐÃ HỦY</span>`;
  return `<span class="badge">${esc(status).toUpperCase()}</span>`;
}
function tickets(){
  let currentStatus='all',currentTerm='';
  const draw=async()=>{
    content.innerHTML=`<div class="topline"><h1 class="title">Quản lý vé phạt (Tickets)</h1></div><div class="topline" style="gap:6px;flex-wrap:wrap;justify-content:flex-start;margin-bottom:14px;"><button class="${currentStatus==='all'?'primary':'secondary'}" data-status="all">Tất cả</button><button class="${currentStatus==='active'?'primary':'secondary'}" data-status="active">Chưa đóng</button><button class="${currentStatus==='overdue'?'primary':'secondary'}" data-status="overdue">Trễ hạn</button><button class="${currentStatus==='paid'?'primary':'secondary'}" data-status="paid">Đã đóng</button><button class="${currentStatus==='void'?'primary':'secondary'}" data-status="void">Đã hủy</button></div><div class="search"><input id="ticket-term" placeholder="Tìm theo Mã ticket, Họ tên hoặc Số IDCard..." value="${esc(currentTerm)}"><button class="primary" id="ticket-search"><i class="fa-solid fa-magnifying-glass"></i> Tìm kiếm</button></div><div id="results" class="list"><div class="empty">Đang tải dữ liệu...</div></div>`;
    document.querySelectorAll('[data-status]').forEach(btn=>btn.onclick=()=>{currentStatus=btn.dataset.status;draw();});
    const doSearch=async()=>{
      const term=document.querySelector('#ticket-term')?.value||'';
      currentTerm=term;
      const res=await request('searchTickets',{status:currentStatus,term:term});
      const rows=res.data||[];
      const listEl=document.querySelector('#results');
      if(!listEl) return;
      listEl.innerHTML=rows.map(t=>`<div class="row" style="justify-content:space-between;" data-id="${t.id}"><div><strong>${ticketStatusBadge(t.status)} ${esc(t.ticket_no)} · ${esc(t.target_name)}</strong><div class="muted">Hành vi: ${esc(t.violation)} · Phạt: <strong>$${Number(t.fine_amount||0).toLocaleString('en-US')}</strong></div><div class="muted">Sĩ quan lập: ${esc(t.officer_name||'N/A')} · Hạn: ${esc(t.due_at_text||'Không có')}</div></div><div style="display:flex;gap:8px;align-items:center;">${(t.status==='active'||t.status==='overdue')?`<button class="secondary" data-void="${t.id}" style="color:#c42b1c;font-weight:600;">Hủy vé</button>`:''}<button class="primary" data-person="${esc(t.target_identifier)}">Hồ sơ</button></div></div>`).join('')||'<div class="empty">Không tìm thấy vé phạt nào.</div>';
      listEl.querySelectorAll('[data-person]').forEach(el=>el.onclick=(e)=>{e.stopPropagation();personDetail(el.dataset.person);});
      listEl.querySelectorAll('[data-void]').forEach(btn=>btn.onclick=async(e)=>{e.stopPropagation();if(await confirmBolo()){const r=await request('voidTicket',{id:btn.dataset.void});showNotice(r.ok?(r.message||'Đã hủy vé phạt.'):(r.message||'Không thể hủy vé phạt.'),r.ok?'success':'error');doSearch();}});
    };
    document.querySelector('#ticket-search').onclick=doSearch;
    const termInp=document.querySelector('#ticket-term');
    if(termInp) termInp.onkeydown=(e)=>{if(e.key==='Enter')doSearch();};
    doSearch();
  };
  draw();
}
function bolos(){content.innerHTML=`<div class="topline"><h1 class="title">BOLO</h1><button class="primary" id="new-bolo">Tạo BOLO</button></div><div id="bolo-list" class="list"></div>`;loadBolos();document.querySelector('#new-bolo').onclick=boloForm;}
async function loadBolos(){const data=await request('listBolos'),list=document.querySelector('#bolo-list');if(!list)return;list.innerHTML=(data.data||[]).map(b=>`<div class="row"><div><strong>${priority(b.priority)} ${esc(b.title)}</strong><div class="muted">${b.type==='vehicle'?'Biển số: ':'Công dân: '}${esc(b.type==='vehicle'?b.plate:b.target_name||'Chưa xác định')} · ${esc(b.reason)} · Tạo bởi: ${esc(b.created_by_name||'Không rõ')}</div></div><button class="secondary" data-resolve="${b.id}">Đóng</button></div>`).join('')||'<div class="empty">Không có BOLO hiệu lực.</div>';list.querySelectorAll('[data-resolve]').forEach(button=>button.onclick=async event=>{event.stopPropagation();if(await confirmBolo()){await request('resolveBolo',{id:button.dataset.resolve});loadBolos();}});}
function boloForm(){content.innerHTML=`<div class="topline"><h1 class="title">Tạo BOLO</h1><button class="secondary" id="back">Quay lại</button></div><section class="panel"><div class="form"><label>Loại<select id="type"><option value="person">Công dân</option><option value="vehicle">Phương tiện</option></select></label><label>Ưu tiên<select id="priority"><option value="medium">Trung bình</option><option value="low">Thấp</option><option value="high">Cao</option><option value="critical">Khẩn cấp</option></select></label><label id="name-wrap">Họ tên người cần truy tìm<input id="target-name" placeholder="Nhập họ tên"></label><label id="plate-wrap">Biển số phương tiện<input id="plate" placeholder="Nhập biển số"></label><label class="wide">Tiêu đề<input id="title"></label><label class="wide">Lý do<textarea id="reason"></textarea></label><label>Thời hạn giờ, 0 là không hạn<input id="hours" type="number" min="0" max="720" value="24"></label><div><button class="primary" id="save">Lưu BOLO</button></div></div></section>`;const type=document.querySelector('#type'),toggle=()=>{document.querySelector('#name-wrap').style.display=type.value==='person'?'grid':'none';document.querySelector('#plate-wrap').style.display=type.value==='vehicle'?'grid':'none';};type.onchange=toggle;toggle();document.querySelector('#back').onclick=bolos;document.querySelector('#save').onclick=async()=>{const response=await request('createBolo',{type:type.value,priority:document.querySelector('#priority').value,targetName:document.querySelector('#target-name').value,plate:document.querySelector('#plate').value,title:document.querySelector('#title').value,reason:document.querySelector('#reason').value,hours:document.querySelector('#hours').value});if(response.ok){showNotice('Đã tạo BOLO.','success');return bolos();}showNotice(response.message||'Không thể lưu BOLO.');};}

window.addEventListener('message',event=>{
  if(event.data.action==='open'){
    boot=event.data.data||{};
    app.hidden=false;
    officer.textContent=`${boot.officer?.name||''} · ${boot.officer?.factionTag||''}`;
    if(event.data.initialApp){
      openApp(event.data.initialApp);
      if(event.data.initialTab) setTab(event.data.initialTab);
    } else {
      launcher();
    }
  }
  if(event.data.action==='navigate'){
    openApp(event.data.app||'mdt');
    if(event.data.tab) setTab(event.data.tab);
  }
  if(event.data.action==='close')app.hidden=true;
  if(event.data.action==='boloChanged'&&tab==='bolos')loadBolos();
  if(event.data.action==='dutyChanged'){boot.onDuty=(event.data.onDuty===true);updateDutyBtnUI();}
});

const closeComputer=()=>fetch(`https://${GetParentResourceName()}/close`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});

document.querySelector('#close').onclick=launcher;
document.querySelector('#minimize').onclick=launcher;
document.querySelector('#win-show-desktop').onclick=launcher;
document.querySelector('.start').onclick=closeComputer;

const updateWinClock=()=>{const n=new Date(),t=document.querySelector('#win-time'),d=document.querySelector('#win-date');if(t)t.textContent=n.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',second:'2-digit'});if(d)d.textContent=n.toLocaleDateString('vi-VN');};setInterval(updateWinClock,1000);updateWinClock();

const dtMdt=document.querySelector('#dt-mdt'),dtCad=document.querySelector('#dt-cad');
if(dtMdt) dtMdt.onclick=()=>openApp('mdt');
if(dtCad) dtCad.onclick=()=>openApp('cad');
