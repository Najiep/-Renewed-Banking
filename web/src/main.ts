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
    framework: 'standalone-preview', currency: { code: 'USD', symbol: '$', precision: 0 },
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
  return `<span class="status status-${escapeHtml(status)}"><span></span>${escapeHtml(status.replaceAll('_', ' '))}</span>`;
}

function render() {
  root.classList.toggle('visible', state.visible);
  if (!state.visible || !state.session) { root.innerHTML = ''; return; }
  const selected = account();
  if (!selected) { root.innerHTML = `<div class="empty">No accessible accounts.</div>`; return; }
  const caps = capabilities();
  root.innerHTML = `
    <div class="shell" role="dialog" aria-label="Renewed Banking">
      <aside class="sidebar">
        <div class="brand"><div class="brand-icon">RB</div><div><strong>Renewed Banking</strong><small>Secure financial services</small></div></div>
        <div class="account-label">Accounts</div>
        <nav class="account-list">
          ${state.session.accounts.map((item) => `
            <button class="account-item ${item.key === selected.key ? 'active' : ''}" data-account="${escapeHtml(item.key)}">
              <span class="account-symbol">${item.accountType === 'personal' ? 'P' : item.accountType === 'shared' ? 'S' : 'O'}</span>
              <span><strong>${escapeHtml(item.displayName)}</strong><small>${escapeHtml(item.accountType)} · ${escapeHtml(item.role || '')}</small></span>
              <b>${money(item.balance)}</b>
            </button>`).join('')}
        </nav>
        ${caps.create ? '<button class="secondary wide" data-action="create">+ Create shared account</button>' : ''}
        <div class="sidebar-footer"><span>${escapeHtml(state.session.framework)}</span><span>v3</span></div>
      </aside>
      <main class="content">
        <header class="topbar"><div><p>${escapeHtml(selected.accountType)} account</p><h1>${escapeHtml(selected.displayName)}</h1></div><button class="icon-button" data-action="close" aria-label="Close">×</button></header>
        ${state.session.migrationRequired ? '<div class="alert warning">Legacy balances were detected. Database-owned operations remain locked until an administrator completes the v3 migration.</div>' : ''}
        ${state.error ? `<div class="alert error">${escapeHtml(state.error)}</div>` : ''}
        <section class="balance-card">
          <div><span>Available balance</span><strong>${money(selected.balance)}</strong>${statusBadge(selected)}</div>
          ${selected.kind === 'personal' ? `<div class="cash"><span>Cash on hand</span><b>${money(selected.cash)}</b></div>` : `<div class="account-key"><span>Account key</span><b>${escapeHtml(selected.key)}</b></div>`}
        </section>
        <section class="actions">
          ${caps.deposit ? '<button class="action-card" data-action="deposit"><i>↓</i><span><b>Deposit</b><small>Add funds to this account</small></span></button>' : ''}
          ${caps.withdraw ? '<button class="action-card" data-action="withdraw"><i>↑</i><span><b>Withdraw</b><small>Receive cash from this account</small></span></button>' : ''}
          ${caps.transfer ? '<button class="action-card" data-action="transfer"><i>↗</i><span><b>Transfer</b><small>Send funds securely</small></span></button>' : ''}
          ${selected.permissions?.members ? '<button class="action-card" data-action="members"><i>◎</i><span><b>Members</b><small>Manage account access</small></span></button>' : ''}
        </section>
        <section class="statement">
          <div class="section-heading"><div><p>Account activity</p><h2>Recent transactions</h2></div><button class="secondary" data-action="refresh">Refresh</button></div>
          <div class="transactions">
            ${state.loading ? '<div class="empty">Loading statement…</div>' : state.transactions.length ? state.transactions.map(transactionRow).join('') : '<div class="empty">No transactions found.</div>'}
          </div>
          ${state.hasMore ? '<button class="secondary wide" data-action="more">Load older transactions</button>' : ''}
        </section>
      </main>
      ${renderModal(selected)}
    </div>`;
}

function transactionRow(tx) {
  const positive = tx.direction === 'credit';
  return `<article class="transaction"><div class="transaction-icon ${positive ? 'positive' : 'negative'}">${positive ? '↓' : '↑'}</div><div class="transaction-copy"><strong>${escapeHtml(tx.description || tx.transaction_type)}</strong><small>${escapeHtml(tx.counterparty_ref || '—')} · ${date(tx.created_at)}</small></div><div class="transaction-amount ${positive ? 'positive' : 'negative'}">${positive ? '+' : '−'}${money(tx.amount)}<small>${escapeHtml(tx.transaction_type)}</small></div></article>`;
}

function renderModal(selected) {
  if (!state.modal) return '';
  if (state.modal.type === 'money') {
    const transfer = state.modal.action === 'transfer';
    return `<div class="modal-backdrop"><form class="modal" data-form="money"><div class="modal-head"><div><p>Secure operation</p><h3>${escapeHtml(state.modal.action)}</h3></div><button type="button" class="icon-button" data-action="dismiss">×</button></div>
      <input type="hidden" name="action" value="${escapeHtml(state.modal.action)}">
      <label>From account<input value="${escapeHtml(selected.displayName)}" disabled></label>
      ${transfer ? '<div class="split"><label>Recipient type<select name="recipientType"><option value="account">Account key</option><option value="personal">Character ID</option></select></label><label>Recipient<input name="recipientKey" maxlength="80" required placeholder="police or ABC123"></label></div>' : ''}
      <label>Amount<input name="amount" inputmode="decimal" autocomplete="off" required placeholder="0"></label>
      <label>Description<textarea name="description" maxlength="160" placeholder="Optional transaction note"></textarea></label>
      <div class="modal-actions"><button type="button" class="secondary" data-action="dismiss">Cancel</button><button class="primary" type="submit">Confirm ${escapeHtml(state.modal.action)}</button></div>
    </form></div>`;
  }
  if (state.modal.type === 'create') {
    return `<div class="modal-backdrop"><form class="modal" data-form="create"><div class="modal-head"><div><p>Shared banking</p><h3>Create account</h3></div><button type="button" class="icon-button" data-action="dismiss">×</button></div>
      <label>Account key<input name="accountKey" required minlength="3" maxlength="50" pattern="[a-z0-9][a-z0-9_-]*" placeholder="family_savings"></label>
      <label>Display name<input name="displayName" required maxlength="96" placeholder="Family Savings"></label>
      <div class="modal-actions"><button type="button" class="secondary" data-action="dismiss">Cancel</button><button class="primary" type="submit">Create account</button></div>
    </form></div>`;
  }
  if (state.modal.type === 'members') {
    return `<div class="modal-backdrop"><div class="modal large"><div class="modal-head"><div><p>Shared account</p><h3>Members</h3></div><button type="button" class="icon-button" data-action="dismiss">×</button></div>
      <div class="member-list">${state.modal.loading ? '<div class="empty">Loading members…</div>' : (state.modal.members || []).map((m) => `<div class="member"><div><strong>${escapeHtml(m.member_identifier)}</strong><small>${escapeHtml(m.role)}</small></div>${m.role !== 'owner' ? `<button class="danger-link" data-remove-member="${escapeHtml(m.member_identifier)}">Remove</button>` : ''}</div>`).join('')}</div>
      <form class="member-add" data-form="member"><input name="identifier" required maxlength="80" placeholder="Character identifier"><select name="role"><option value="operator">Operator</option><option value="viewer">Viewer</option><option value="admin">Admin</option></select><button class="primary">Add member</button></form>
      <div class="management-row">${selected.permissions?.rename ? '<button class="secondary" data-action="rename">Rename display name</button>' : ''}${selected.permissions?.close ? '<button class="danger" data-action="close-account">Close account</button>' : ''}</div>
    </div></div>`;
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
