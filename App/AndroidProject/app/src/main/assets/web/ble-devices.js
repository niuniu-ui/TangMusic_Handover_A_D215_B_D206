/* Show instrument modules; native discovery also recognizes the saved address. */
(() => {
  'use strict';
  function cleanName(value, address = '') {
    const name = String(value ?? '').replace(/[\u0000-\u001f\u007f\u200b-\u200f\ufeff]/g, '').trim();
    if (!name || /^(未命名(?:\s*BLE)?(?:\s*设备)?|未知(?:\s*BLE)?(?:\s*设备)?|(?:unknown|unnamed)(?:\s*ble)?(?:\s*device)?|null|undefined|n\/a)$/i.test(name)) return '';
    if (name.toLowerCase() === address.toLowerCase() || /^(?:[\da-f]{2}[:-]){5}[\da-f]{2}$/i.test(name)) return '';
    return name;
  }
  class DeviceList {
    constructor({root, connect, disabled, scanning, connected}) {
      Object.assign(this, {root, connect, disabled, scanning, connected});
      this.items = new Map(); this.rows = new Map(); this.timer = null;
      this.query = ''; this.hasScanned = false; this.dirty = true;
      this.count = root.querySelector('[data-device-count]');
      this.list = root.querySelector('[data-device-list]');
      this.empty = root.querySelector('[data-device-empty]');
      this.search = root.querySelector('input');
      this.search.addEventListener('input', () => {this.query = this.search.value.trim().toLowerCase(); this.schedule();});
      window.addEventListener('tang:page', () => this.schedule());
      window.addEventListener('tang:connection-open', () => this.schedule());
      document.addEventListener('visibilitychange', () => {if (!document.hidden) this.schedule();});
    }
    clear() {
      this.items.clear(); this.rows.clear(); this.list.replaceChildren();
      this.query = ''; this.search.value = ''; this.hasScanned = true; this.schedule();
    }
    visible() {
      return !document.hidden && (!document.getElementById('device').hidden || Boolean(this.root.closest('dialog[open]')));
    }
    accept(data) {
      const address = String(data.address || '').trim().toUpperCase();
      if (!address) return;
      if (!data.instrument && !/^(?:E104|Tang[ _-]?Music)(?:$|[-_ ].*)/i.test(cleanName(data.name, address)) && !this.items.has(address)) return;
      const old = this.items.get(address), name = cleanName(data.name, address) || old?.name || '';
      const rssi = Number.isFinite(data.rssi) ? data.rssi : old?.rssi;
      if (old && old.name === name && old.rssi === rssi) return;
      this.items.set(address, {address, name, rssi}); this.schedule();
    }
    schedule() {
      this.dirty = true;
      if (this.timer !== null || !this.visible()) return;
      this.timer = setTimeout(() => {this.timer = null; this.render();}, 250);
    }
    render() {
      if (!this.visible()) return;
      this.dirty = false; this.root.hidden = this.connected();
      let visible = 0;
      for (const item of this.items.values()) {
        let row = this.rows.get(item.address);
        if (!row) {
          row = document.createElement('button'); row.type = 'button'; row.className = 'device-result';
          const icon = document.createElement('span'); icon.className = 'ble-device-icon'; icon.textContent = '↔'; icon.setAttribute('aria-hidden', 'true');
          const group = document.createElement('span'); group.className = 'grow';
          row.labelNode = document.createElement('strong'); row.detailNode = document.createElement('small');
          const action = document.createElement('span'); action.className = 'connect-label'; action.textContent = '连接 ›';
          group.append(row.labelNode, row.detailNode); row.append(icon, group, action);
          row.addEventListener('click', () => {if (!this.disabled()) this.connect(item.address);});
          this.rows.set(item.address, row); this.list.append(row);
        }
        const detail = item.address + (item.rssi === undefined ? '' : ' · ' + item.rssi + ' dBm');
        const label = item.name || '我的乐器';
        if (row.labelNode.textContent !== label) row.labelNode.textContent = label;
        if (row.detailNode.textContent !== detail) row.detailNode.textContent = detail;
        const disabled = this.disabled(), hidden = Boolean(this.query && !`${label} ${item.address}`.toLowerCase().includes(this.query));
        if (row.disabled !== disabled) row.disabled = disabled;
        if (row.hidden !== hidden) row.hidden = hidden;
        if (!row.hidden) visible++;
      }
      const summary = this.scanning() ? '正在寻找乐器模块…' : this.hasScanned ? '发现 ' + this.items.size + ' 个乐器模块' : '扫描后选择你的乐器模块';
      if (this.count.textContent !== summary) this.count.textContent = summary;
      this.empty.hidden = visible > 0;
      const empty = this.query ? '没有匹配的乐器，试试名称或地址。' : this.scanning() ? '请靠近乐器，保持模块正在广播。' : this.hasScanned ? '未发现乐器，请确认模块供电且未连接其他手机，再重新扫描。' : '点击上方扫描，你的乐器会自动出现在这里。';
      if (this.empty.textContent !== empty) this.empty.textContent = empty;
    }
  }
  window.TangBleDevices = {cleanName, DeviceList};
})();
