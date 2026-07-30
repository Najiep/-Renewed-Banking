const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Renewed-Banking';
const root = document.getElementById('app');

const state = {
  visible: false,
  session: null,
  context: null,
  selectedKey: null,
  transactions: [],
  nextCursor: null,
  hasMore: false,
  loading: false,
  error: null,
  modal: null
};

const escapeHtml = (value) => String(value ?? '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&#039;');

const uuid = () => globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;

const icons = {
  deposit: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M4 21h16"/></svg>`,
  withdraw: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21V9"/><path d="m7 14 5-5 5 5"/><path d="M4 3h16"/></svg>`,
  transfer: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7"/><path d="M7 7h10v10"/></svg>`,
  members: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>`,
  close: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>`,
  refresh: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/><path d="M16 16h5v5"/></svg>`,
  plus: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>`,
  bank: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M6 12h.01M18 12h.01"/></svg>`,
  warning: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`,
  empty: `<svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="14" x="2" y="5" rx="2"/><line x1="2" x2="22" y1="10" y2="10"/></svg>`
};

async function nui(name, payload = {}) {
  if (location.hostname === 'localhost') return mock(name, payload);
  const response = await fetch(`https://${resourceName}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload)
  });
  return response.json();
}

function mock(name, payload) {
  if (name === 'getSession') return Promise.resolve({ ok: true, data: demoSession() });
  if (name === 'transactions') return Promise.resolve({ ok: true, data: { items: demoTransactions(), nextCursor: null, hasMore: false } });
  return Promise.resolve({ ok: true, data: { groupId: uuid(), status: 'committed' } });
}

function demoSession() {
  return {
    framework: 'esx', currency: { code: 'USD', symbol: '$', precision: 0 },
    migrationRequired: false, capabilities: { sharedAccounts: true },
    accounts: [
      { kind: 'personal', key: 'DEMO1001', displayName: 'Alex Morgan', accountType: 'personal', balance: 24500, cash: 1350, status: 'active', role: 'owner', permissions: { view: true, deposit: true, withdraw: true, transfer: true } },
      { kind: 'database', key: 'police', displayName: 'Los Santos Police Department', accountType: 'job', balance: 875000, status: 'active', role: 'group', permissions: { view: true, deposit: true, withdraw: true, transfer: true } },
      { kind: 'database', key: 'family_savings', displayName: 'Family Savings', accountType: 'shared', balance: 64250, status: 'active', role: 'owner', permissions: { view: true, deposit: true, withdraw: true, transfer: true, members: true, rename: true, close: true } }
    ]
  };
}

function demoTransactions() {
  return [
    { id: 3, direction: 'credit', transaction_type: 'cash_deposit', amount: 2500, counterparty_ref: 'cash', description: 'Cash deposit', created_at: new Date().toISOString(), group_id: 'demo-3' },
    { id: 2, direction: 'debit', transaction_type: 'transfer_debit', amount: 1250, counterparty_ref: 'ambulance', description: 'Equipment reimbursement', created_at: new Date(Date.now() - 3600000).toISOString(), group_id: 'demo-2' },
    { id: 1, direction: 'credit', transaction_type: 'migration_credit', amount: 23250, counterparty_ref: 'legacy_v2', description: 'Imported opening balance', created_at: new Date(Date.now() - 86400000).toISOString(), group_id: 'demo-1' }
  ];
}

function account() {
  return state.session?.accounts?.find((item) => item.key === state.selectedKey) || state.session?.accounts?.[0];
}

function money(value) {
  const currency = state.session?.currency || { code: 'USD', precision: 0 };
  const factor = 10 ** (currency.precision || 0);
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.code || 'USD', minimumFractionDigits: currency.precision || 0, maximumFractionDigits: currency.precision || 0 }).format((Number(value) || 0) / factor);
}

function date(value) {
  const parsed = value ? new Date(value) : null;
  return parsed && !Number.isNaN(parsed.valueOf()) ? new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(parsed) : '—';
}

function capabilities() {
  const selected = account();
  const location = state.context?.capabilities || {};
  const permission = selected?.permissions || {};
  return {
    deposit: location.deposit !== false && permission.deposit === true,
    withdraw: location.withdraw !== false && permission.withdraw === true,
    transfer: location.transfer !== false && permission.transfer === true,
    create: location.createSharedAccount === true && state.session?.capabilities?.sharedAccounts === true
  };
}

function statusBadge(selected) {
  const status = selected?.status || 'unknown';
  return `<span class="status-badge status-${escapeHtml(status)}"><span class="status-dot"></span>${escapeHtml(status.replaceAll('_', ' '))}</span>`;
}

function render() {
  root.classList.toggle('visible', state.visible);
  if (!state.visible || !state.session) { root.innerHTML = ''; return; }
  const selected = account();
  if (!selected) { root.innerHTML = `<div class="empty-state">${icons.empty}<span>No accessible accounts found.</span></div>`; return; }
  const caps = capabilities();
  const isNegative = Number(selected.balance) < 0;

  root.innerHTML = `
    <div class="shell" role="dialog" aria-label="Renewed Banking">
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-icon">
            ${icons.bank}
          </div>
          <div class="brand-info">
            <strong>Renewed Banking</strong>
            <small>Secure Financial Hub</small>
          </div>
        </div>
        
        <div class="sidebar-section">
          <div class="account-label">My Accounts</div>
          <nav class="account-list">
            ${state.session.accounts.map((item) => `
              <button class="account-item ${item.key === selected.key ? 'active' : ''}" data-account="${escapeHtml(item.key)}">
                <span class="account-symbol ${item.accountType}">${item.accountType === 'personal' ? 'P' : item.accountType === 'shared' ? 'S' : 'J'}</span>
                <span class="account-details">
                  <strong>${escapeHtml(item.displayName)}</strong>
                  <small>${escapeHtml(item.accountType)} · ${escapeHtml(item.role || 'Member')}</small>
                </span>
                <b class="account-amount ${Number(item.balance) < 0 ? 'text-negative' : ''}">${money(item.balance)}</b>
              </button>`).join('')}
          </nav>
        </div>

        <div class="sidebar-bottom">
          ${caps.create ? `<button class="secondary wide create-btn" data-action="create">${icons.plus} Create Shared Account</button>` : ''}
          <div class="sidebar-footer">
            <span class="pill-tag">${escapeHtml(state.session.framework)}</span>
            <span class="pill-tag muted">v3.0</span>
          </div>
        </div>
      </aside>

      <main class="content">
        <header class="topbar">
          <div class="topbar-info">
            <span class="topbar-badge">${escapeHtml(selected.accountType)} account</span>
            <h1>${escapeHtml(selected.displayName)}</h1>
          </div>
          <button class="icon-button close-btn" data-action="close" aria-label="Close">
            ${icons.close}
          </button>
        </header>

        ${state.session.migrationRequired ? `<div class="alert warning">${icons.warning} <span>Legacy balances detected. Database operations locked pending v3 migration.</span></div>` : ''}
        ${state.error ? `<div class="alert error">${icons.warning} <span>${escapeHtml(state.error)}</span></div>` : ''}

        <section class="balance-card">
          <div class="balance-card-bg"></div>
          <div class="balance-main">
            <span class="balance-label">Available Balance</span>
            <strong class="balance-value ${isNegative ? 'negative' : ''}">${money(selected.balance)}</strong>
            <div class="balance-meta">
              ${statusBadge(selected)}
            </div>
          </div>
          <div class="balance-aside">
            ${selected.kind === 'personal' 
              ? `<div class="cash-badge"><span class="label">Cash on Hand</span><b class="val">${money(selected.cash)}</b></div>` 
              : `<div class="key-badge"><span class="label">Account Key</span><b class="val">${escapeHtml(selected.key)}</b></div>`}
          </div>
        </section>

        <section class="actions">
          ${caps.deposit ? `
            <button class="action-card deposit" data-action="deposit">
              <div class="action-icon">${icons.deposit}</div>
              <div class="action-text">
                <b>Deposit</b>
                <small>Add cash to balance</small>
              </div>
            </button>` : ''}
          ${caps.withdraw ? `
            <button class="action-card withdraw" data-action="withdraw">
              <div class="action-icon">${icons.withdraw}</div>
              <div class="action-text">
                <b>Withdraw</b>
                <small>Receive physical cash</small>
              </div>
            </button>` : ''}
          ${caps.transfer ? `
            <button class="action-card transfer" data-action="transfer">
              <div class="action-icon">${icons.transfer}</div>
              <div class="action-text">
                <b>Transfer</b>
                <small>Send funds securely</small>
              </div>
            </button>` : ''}
          ${selected.permissions?.members ? `
            <button class="action-card members" data-action="members">
              <div class="action-icon">${icons.members}</div>
              <div class="action-text">
                <b>Members</b>
                <small>Manage permissions</small>
              </div>
            </button>` : ''}
        </section>

        <section class="statement">
          <div class="section-heading">
            <div>
              <p>Activity Log</p>
              <h2>Recent Transactions</h2>
            </div>
            <button class="secondary btn-sm refresh-btn" data-action="refresh">
              ${icons.refresh} Refresh
            </button>
          </div>
          
          <div class="transactions">
            ${state.loading 
              ? `<div class="empty-state"><div class="spinner"></div><span>Loading transactions…</span></div>` 
              : state.transactions.length 
                ? state.transactions.map(transactionRow).join('') 
                : `<div class="empty-state">${icons.empty}<span>No recent transactions found.</span></div>`}
          </div>

          ${state.hasMore ? `<button class="secondary wide load-more-btn" data-action="more">Load older transactions</button>` : ''}
        </section>
      </main>

      ${renderModal(selected)}
    </div>`;
}

function transactionRow(tx) {
  const positive = tx.direction === 'credit';
  return `
    <article class="transaction">
      <div class="transaction-icon ${positive ? 'positive' : 'negative'}">
        ${positive ? icons.deposit : icons.withdraw}
      </div>
      <div class="transaction-copy">
        <strong>${escapeHtml(tx.description || tx.transaction_type)}</strong>
        <small>${escapeHtml(tx.counterparty_ref || '—')} · ${date(tx.created_at)}</small>
      </div>
      <div class="transaction-amount ${positive ? 'positive' : 'negative'}">
        ${positive ? '+' : '−'}${money(tx.amount)}
        <small>${escapeHtml(tx.transaction_type.replaceAll('_', ' '))}</small>
      </div>
    </article>`;
}

function renderModal(selected) {
  if (!state.modal) return '';
  if (state.modal.type === 'money') {
    const transfer = state.modal.action === 'transfer';
    return `
      <div class="modal-backdrop">
        <form class="modal" data-form="money">
          <div class="modal-head">
            <div>
              <p>Secure Operation</p>
              <h3>${escapeHtml(state.modal.action)}</h3>
            </div>
            <button type="button" class="icon-button" data-action="dismiss">${icons.close}</button>
          </div>
          <input type="hidden" name="action" value="${escapeHtml(state.modal.action)}">
          <div class="field-group">
            <label>From Account
              <input value="${escapeHtml(selected.displayName)}" disabled class="disabled-input">
            </label>
          </div>
          ${transfer ? `
            <div class="split">
              <label>Recipient Type
                <select name="recipientType">
                  <option value="account">Account Key</option>
                  <option value="personal">Character ID</option>
                </select>
              </label>
              <label>Recipient
                <input name="recipientKey" maxlength="80" required placeholder="e.g. police or CID123">
              </label>
            </div>` : ''}
          <div class="field-group">
            <label>Amount
              <input name="amount" type="number" step="any" min="1" inputmode="decimal" autocomplete="off" required placeholder="0">
            </label>
          </div>
          <div class="field-group">
            <label>Note / Description
              <textarea name="description" maxlength="160" placeholder="Optional reference note"></textarea>
            </label>
          </div>
          <div class="modal-actions">
            <button type="button" class="secondary" data-action="dismiss">Cancel</button>
            <button class="primary" type="submit">Confirm ${escapeHtml(state.modal.action)}</button>
          </div>
        </form>
      </div>`;
  }
  if (state.modal.type === 'create') {
    return `
      <div class="modal-backdrop">
        <form class="modal" data-form="create">
          <div class="modal-head">
            <div>
              <p>Shared Account</p>
              <h3>Create New Account</h3>
            </div>
            <button type="button" class="icon-button" data-action="dismiss">${icons.close}</button>
          </div>
          <div class="field-group">
            <label>Account Key
              <input name="accountKey" required minlength="3" maxlength="50" pattern="[a-z0-9][a-z0-9_-]*" placeholder="family_savings">
            </label>
          </div>
          <div class="field-group">
            <label>Display Name
              <input name="displayName" required maxlength="96" placeholder="Family Savings">
            </label>
          </div>
          <div class="modal-actions">
            <button type="button" class="secondary" data-action="dismiss">Cancel</button>
            <button class="primary" type="submit">Create Account</button>
          </div>
        </form>
      </div>`;
  }
  if (state.modal.type === 'members') {
    return `
      <div class="modal-backdrop">
        <div class="modal large">
          <div class="modal-head">
            <div>
              <p>Access Management</p>
              <h3>Account Members</h3>
            </div>
            <button type="button" class="icon-button" data-action="dismiss">${icons.close}</button>
          </div>
          <div class="member-list">
            ${state.modal.loading 
              ? `<div class="empty-state"><div class="spinner"></div><span>Loading members…</span></div>` 
              : (state.modal.members || []).map((m) => `
                <div class="member">
                  <div class="member-info">
                    <strong>${escapeHtml(m.member_identifier)}</strong>
                    <small>${escapeHtml(m.role)}</small>
                  </div>
                  ${m.role !== 'owner' ? `<button class="danger-link" data-remove-member="${escapeHtml(m.member_identifier)}">Remove</button>` : '<span class="pill-tag">Owner</span>'}
                </div>`).join('')}
          </div>
          <form class="member-add" data-form="member">
            <input name="identifier" required maxlength="80" placeholder="Character ID">
            <select name="role">
              <option value="operator">Operator</option>
              <option value="viewer">Viewer</option>
              <option value="admin">Admin</option>
            </select>
            <button class="primary">Add Member</button>
          </form>
          <div class="management-row">
            ${selected.permissions?.rename ? '<button class="secondary" data-action="rename">Rename Account</button>' : ''}
            ${selected.permissions?.close ? '<button class="danger" data-action="close-account">Close Account</button>' : ''}
          </div>
        </div>
      </div>`;
  }
  return '';
}

async function refreshSession() {
  const result = await nui('getSession', {});
  if (!result?.ok) return fail(result);
  state.session = result.data;
  if (!state.session.accounts.some((item) => item.key === state.selectedKey)) state.selectedKey = state.session.accounts[0]?.key;
  render();
}

async function loadTransactions(append = false) {
  const selected = account();
  if (!selected) return;
  state.loading = true; state.error = null; render();
  const result = await nui('transactions', { accountKey: selected.key, cursor: append ? state.nextCursor : null, limit: 30, filters: {} });
  state.loading = false;
  if (!result?.ok) return fail(result);
  state.transactions = append ? [...state.transactions, ...result.data.items] : result.data.items;
  state.nextCursor = result.data.nextCursor; state.hasMore = result.data.hasMore; render();
}

function fail(result) {
  state.error = result?.error?.message || result?.error?.code || 'The banking request failed.';
  render();
}

function openModal(type, action) { state.modal = { type, action, requestId: uuid() }; state.error = null; render(); }
function dismiss() { state.modal = null; render(); }

root.addEventListener('click', async (event) => {
  const accountButton = event.target.closest('[data-account]');
  if (accountButton) { state.selectedKey = accountButton.dataset.account; state.transactions = []; state.nextCursor = null; render(); await loadTransactions(); return; }
  const action = event.target.closest('[data-action]')?.dataset.action;
  if (!action) {
    const remove = event.target.closest('[data-remove-member]');
    if (remove && confirm(`Remove ${remove.dataset.removeMember}?`)) {
      const result = await nui('removeMember', { accountKey: account().key, identifier: remove.dataset.removeMember, requestId: uuid() });
      if (!result.ok) return fail(result);
      await showMembers();
    }
    return;
  }
  if (action === 'close') return closeUi();
  if (action === 'dismiss') return dismiss();
  if (['deposit', 'withdraw', 'transfer'].includes(action)) return openModal('money', action);
  if (action === 'create') return openModal('create');
  if (action === 'refresh') return loadTransactions();
  if (action === 'more') return loadTransactions(true);
  if (action === 'members') return showMembers();
  if (action === 'rename') {
    const name = prompt('New display name', account().displayName);
    if (!name) return;
    const result = await nui('renameAccount', { accountKey: account().key, displayName: name, requestId: uuid() });
    if (!result.ok) return fail(result);
    await refreshSession(); await showMembers();
  }
  if (action === 'close-account' && confirm('Close this zero-balance account? This keeps its audit history.')) {
    const result = await nui('closeAccount', { accountKey: account().key, reason: 'Closed by owner', requestId: uuid() });
    if (!result.ok) return fail(result);
    dismiss(); await refreshSession(); await loadTransactions();
  }
});

root.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.target;
  const data = Object.fromEntries(new FormData(form));
  if (form.dataset.form === 'money') {
    const action = data.action;
    const payload = { requestId: state.modal?.requestId || uuid(), sourceKey: account().key, amount: data.amount, description: data.description || '' };
    if (action === 'transfer') { payload.recipientType = data.recipientType; payload.recipientKey = data.recipientKey; }
    const submit = form.querySelector('button[type="submit"]');
    submit.disabled = true;
    let result;
    try { result = await nui(action, payload); }
    catch { submit.disabled = false; return fail({ error: { code: 'SERVICE_UNAVAILABLE' } }); }
    if (!result?.ok) { submit.disabled = false; return fail(result); }
    dismiss(); await refreshSession(); await loadTransactions();
  }
  if (form.dataset.form === 'create') {
    const result = await nui('createAccount', { requestId: state.modal?.requestId || uuid(), accountKey: data.accountKey, displayName: data.displayName });
    if (!result?.ok) return fail(result);
    dismiss(); await refreshSession(); state.selectedKey = result.data.key; await loadTransactions();
  }
  if (form.dataset.form === 'member') {
    const result = await nui('addMember', { requestId: state.modal?.requestId || uuid(), accountKey: account().key, identifier: data.identifier, role: data.role });
    if (!result?.ok) return fail(result);
    await showMembers();
  }
});

async function showMembers() {
  state.modal = { type: 'members', loading: true, members: [] }; render();
  const result = await nui('listMembers', { accountKey: account().key });
  if (!result?.ok) return fail(result);
  state.modal = { type: 'members', loading: false, members: result.data }; render();
}

async function closeUi() {
  state.visible = false; state.modal = null; render();
  await nui('closeInterface', {});
}

window.addEventListener('message', async (event) => {
  const message = event.data || {};
  if (message.type === 'renewedBanking:open') {
    state.visible = true; state.session = message.payload.session; state.context = message.payload.context;
    state.selectedKey = state.session.accounts[0]?.key; state.error = null; state.modal = null; render(); await loadTransactions();
  }
  if (message.type === 'renewedBanking:close') { state.visible = false; render(); }
});

window.addEventListener('keydown', (event) => { if (event.key === 'Escape' && state.visible) state.modal ? dismiss() : closeUi(); });

if (location.hostname === 'localhost') {
  state.visible = true; state.session = demoSession(); state.context = { type: 'bank', capabilities: { deposit: true, withdraw: true, transfer: true, createSharedAccount: true } };
  state.selectedKey = state.session.accounts[0].key; state.transactions = demoTransactions(); render();
}
