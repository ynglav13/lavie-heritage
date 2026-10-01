const hud = document.getElementById('casino-hud')
const status = document.getElementById('status')
const statusTitle = document.getElementById('status-title')
const statusState = document.getElementById('status-state')
const statusText = document.getElementById('status-text')
const statusItems = document.getElementById('status-items')
const controls = document.getElementById('controls')
const controlsHint = document.getElementById('controls-hint')
const controlsActions = document.getElementById('controls-actions')

let statusVisible = false
let controlsVisible = false
let lastStatus = ''
let lastControls = ''

function text(value) {
    return value === undefined || value === null ? '' : String(value)
}

function syncHud() {
    hud.classList.toggle('visible', statusVisible || controlsVisible)
}

function setVisible(element, visible) {
    element.classList.toggle('visible', visible)
    element.setAttribute('aria-hidden', visible ? 'false' : 'true')
}

function renderStatus(payload) {
    const signature = JSON.stringify(payload || {})
    if (signature === lastStatus) return
    lastStatus = signature
    statusTitle.textContent = text(payload.title)
    statusState.textContent = text(payload.state)
    statusText.textContent = text(payload.text)
    statusItems.replaceChildren()

    const items = Array.isArray(payload.items) ? payload.items : []
    for (const item of items) {
        const row = document.createElement('div')
        const label = document.createElement('span')
        const value = document.createElement('span')
        row.className = 'status-item'
        label.className = 'status-label'
        value.className = 'status-value'
        label.textContent = text(item.label)
        value.textContent = text(item.value)
        row.append(label, value)
        statusItems.append(row)
    }
}

function renderControls(payload) {
    const signature = JSON.stringify(payload || {})
    if (signature === lastControls) return
    lastControls = signature
    controlsHint.textContent = text(payload.hint)
    controlsActions.replaceChildren()

    const actions = Array.isArray(payload.actions) ? payload.actions : []
    for (const action of actions) {
        const row = document.createElement('div')
        const key = document.createElement('span')
        const label = document.createElement('span')
        row.className = 'control-action'
        key.className = 'control-key'
        label.className = 'control-label'
        key.textContent = text(action.key)
        label.textContent = text(action.label)
        row.append(key, label)
        controlsActions.append(row)
    }
}

window.addEventListener('message', (event) => {
    const data = event.data || {}
    if (data.action === 'status') {
        statusVisible = data.visible === true
        if (statusVisible) renderStatus(data.payload || {})
        else lastStatus = ''
        setVisible(status, statusVisible)
        syncHud()
    } else if (data.action === 'controls') {
        controlsVisible = data.visible === true
        if (controlsVisible) renderControls(data.payload || {})
        else lastControls = ''
        setVisible(controls, controlsVisible)
        syncHud()
    }
})
