var factionId = null;

window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.display === true && data.edit === 'budget') {
        factionId = data.id;

        // Build list menu for leader
        if (data.permission.leader == true) {
            $(".listmenu").empty();
            var garageBtn = (data.type === 'gov' || data.type === 'business') ? `<a class="unactive" onclick="SelectMenu('garage', '${data.id}')">Garage</a>` : '';
            $(".listmenu").append(`
                <a class="unactive" onclick="SelectMenu('general',      '${data.id}')">General</a>
                <a class="unactive" onclick="SelectMenu('members',      '${data.id}')">Members</a>
                <a class="unactive" onclick="SelectMenu('permission',   '${data.id}')">Permission</a>
                <a class="unactive" onclick="SelectMenu('rank',         '${data.id}')">Rank</a>
                <a class="unactive" onclick="SelectMenu('division',     '${data.id}')">Division</a>
                ${garageBtn}
                <a class="unactive" onclick="SelectMenu('locker',       '${data.id}')">Locker</a>
                <a class="active">Budget</a>
            `);
        }
        $(".content").empty().append(`
            <div class="budget-container" style="display: flex; flex-direction: column; gap: 24px; padding: 10px;">
                <!-- Premium Budget Display Card -->
                <div style="background: var(--bg-secondary); border: 1px solid var(--border-color); border-radius: var(--border-radius-lg); padding: 30px; text-align: center; box-shadow: 0 4px 20px rgba(0,0,0,0.15); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;">
                    <span style="font-size: 14px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-muted);">Quỹ Ngân Sách</span>
                    <span id="currentBudget" style="font-size: 42px; font-weight: 700; color: #2ecc71; text-shadow: 0 0 15px rgba(46, 204, 113, 0.2); font-family: 'Outfit', sans-serif;">$0</span>
                </div>

                <!-- Actions Row -->
                <div style="display: flex; gap: 20px;">
                    <!-- Deposit Panel -->
                    <div style="flex: 1; background: var(--bg-secondary); border: 1px solid var(--border-color); border-radius: var(--border-radius-lg); padding: 24px; display: flex; flex-direction: column; gap: 16px;">
                        <h3 style="font-size: 18px; font-weight: 600; color: var(--text-main); margin-bottom: 4px; display: flex; align-items: center; gap: 8px;">
                            <i class="fa-solid fa-arrow-right-to-bracket" style="color: #2ecc71;"></i> Nộp Tiền
                        </h3>
                        <span style="font-size: 13px; color: var(--text-muted); line-height: 1.4;">Nộp tiền mặt từ túi đồ cá nhân vào ngân sách tổ chức.</span>
                        <input type="number" id="depositAmount" placeholder="Nhập số tiền cần nộp..." min="1" style="width: 100%;" />
                        <button onclick="DepositMoney()" style="background: #2ecc71; color: white; width: 100%; padding: 12px; font-size: 14px; border-radius: var(--border-radius-md); font-weight: 600; border: none; cursor: pointer;">Nộp tiền</button>
                    </div>

                    <!-- Withdraw Panel -->
                    <div style="flex: 1; background: var(--bg-secondary); border: 1px solid var(--border-color); border-radius: var(--border-radius-lg); padding: 24px; display: flex; flex-direction: column; gap: 16px;">
                        <h3 style="font-size: 18px; font-weight: 600; color: var(--text-main); margin-bottom: 4px; display: flex; align-items: center; gap: 8px;">
                            <i class="fa-solid fa-arrow-right-from-bracket" style="color: #e74c3c;"></i> Rút Tiền
                        </h3>
                        <span style="font-size: 13px; color: var(--text-muted); line-height: 1.4;">Rút tiền từ ngân sách tổ chức về ví cá nhân.</span>
                        <input type="number" id="withdrawAmount" placeholder="Nhập số tiền cần rút..." min="1" style="width: 100%;" />
                        <button onclick="WithdrawMoney()" style="background: #e74c3c; color: white; width: 100%; padding: 12px; font-size: 14px; border-radius: var(--border-radius-md); font-weight: 600; border: none; cursor: pointer;">Rút tiền</button>
                    </div>
                </div>
            </div>
        `);

        var budgetVal = data.budget || 0;
        $("#currentBudget").text("$" + budgetVal.toLocaleString());

        $(".footer").empty().append(`
            <button class="button buttonClosed" onclick="CloseMenu()">Log out</button>
        `);
    }
});

function DepositMoney() {
    var amount = parseInt($("#depositAmount").val());
    if (amount && amount > 0) {
        $.post('https://factionCore/DepositBudget', JSON.stringify({ id: factionId, amount: amount }));
        $("#depositAmount").val('');
    }
}

function WithdrawMoney() {
    var amount = parseInt($("#withdrawAmount").val());
    if (amount && amount > 0) {
        $.post('https://factionCore/WithdrawBudget', JSON.stringify({ id: factionId, amount: amount }));
        $("#withdrawAmount").val('');
    }
}
