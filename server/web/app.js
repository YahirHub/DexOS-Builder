(() => {
  'use strict';

  const steps = [
    ['Inicio', 'Preparar instalación'],
    ['Destino', 'Elegir almacenamiento'],
    ['Sistema', 'Configurar DexOS'],
    ['Revisar', 'Confirmar cambios'],
    ['Instalar', 'Instalando DexOS Server']
  ];

  const state = {
    step: 0,
    mode: 'coexist',
    disks: [],
    parts: [],
    freeSpaces: [],
    disk: '',
    rootPart: '',
    rootFreeStart: '',
    rootFreeSectors: '',
    efiPart: '',
    wifiSsid: '',
    wifiPassword: '',
    wifiHasPassword: false,
    installing: false
  };

  const $ = (id) => document.getElementById(id);
  const panels = [...document.querySelectorAll('[data-step-panel]')];
  const indicators = [...document.querySelectorAll('[data-step-indicator]')];
  const modeCards = [...document.querySelectorAll('[data-mode]')];

  function refreshIcons() {
    if (window.lucide) window.lucide.createIcons();
  }

  function setError(message = '') {
    const box = $('global-error');
    box.hidden = !message;
    box.textContent = message;
    if (message) box.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  function diskByPath(path) {
    return state.disks.find((d) => d.path === path);
  }

  function selectedDisk() {
    return diskByPath(state.disk);
  }

  function selectedRoot() {
    if (state.rootPart) return state.parts.find((p) => p.path === state.rootPart);
    if (state.rootFreeStart) return state.freeSpaces.find((f) => f.disk === state.disk && f.start === state.rootFreeStart && f.sectors === state.rootFreeSectors);
    return undefined;
  }

  function node(tag, className, text) {
    const n = document.createElement(tag);
    if (className) n.className = className;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function icon(name, className = 'h-4 w-4') {
    const i = document.createElement('i');
    i.dataset.lucide = name;
    i.className = className;
    return i;
  }

  function badge(text, tone = 'neutral') {
    const tones = {
      neutral: 'border-white/10 bg-white/5 text-zinc-400',
      red: 'border-dex-600/30 bg-dex-950/50 text-dex-200',
      green: 'border-emerald-500/20 bg-emerald-500/10 text-emerald-300',
      amber: 'border-amber-400/20 bg-amber-400/10 text-amber-200'
    };
    return node('span', `inline-flex rounded-full border px-2 py-0.5 text-[11px] font-medium ${tones[tone] || tones.neutral}`, text);
  }

  function updateStepper() {
    indicators.forEach((li, index) => {
      const active = index === state.step;
      const done = index < state.step;
      li.className = 'min-w-0';
      li.textContent = '';
      const wrap = node('div', `flex min-w-0 items-center justify-center gap-1 rounded-xl px-1 py-2 transition sm:gap-2 lg:justify-start lg:px-3 ${active ? 'bg-dex-950/65 text-white ring-1 ring-dex-700/40' : 'text-zinc-500'}`);
      const bubble = node('span', `grid h-7 w-7 shrink-0 place-items-center rounded-lg text-[11px] font-semibold sm:h-8 sm:w-8 sm:rounded-xl sm:text-xs ${active ? 'bg-dex-700 text-white' : done ? 'bg-emerald-500/15 text-emerald-300' : 'bg-white/5 text-zinc-500'}`);
      if (done) bubble.append(icon('check', 'h-4 w-4'));
      else bubble.textContent = String(index + 1);
      const copy = node('span', 'hidden min-w-0 lg:block');
      copy.append(node('span', `block text-xs font-semibold ${active ? 'text-white' : done ? 'text-zinc-300' : 'text-zinc-500'}`, steps[index][0]));
      copy.append(node('span', 'mt-0.5 block truncate text-[11px] text-zinc-600', steps[index][1]));
      wrap.append(bubble, copy);
      li.append(wrap);
    });
    refreshIcons();
  }

  function showStep(step) {
    state.step = Math.max(0, Math.min(4, step));
    panels.forEach((panel) => { panel.hidden = Number(panel.dataset.stepPanel) !== state.step; });
    $('step-kicker').textContent = `Paso ${state.step + 1} de 5`;
    $('step-title').textContent = steps[state.step][1];
    $('back-btn').disabled = state.step === 0 || state.installing;
    $('next-btn').hidden = state.step === 4;
    $('wizard-footer').hidden = state.step === 4;
    if (state.step === 3) renderSummary();
    updateStepper();
    setError('');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function parseInventory(text) {
    const disks = [];
    const parts = [];
    const freeSpaces = [];
    text.split(/\r?\n/).filter(Boolean).forEach((line) => {
      const f = line.split('\t');
      if (f[0] === 'DISK') {
        disks.push({
          path: f[1], sizeBytes: Number(f[2] || 0), size: f[3] || '', model: f[4] || '', transport: f[5] || '',
          bios: f[6] === 'yes', liveUefi: f[7] === 'yes'
        });
      } else if (f[0] === 'PART') {
        parts.push({
          kind: 'partition', path: f[1], disk: f[2], sizeBytes: Number(f[3] || 0), size: f[4] || '', fs: f[5] || 'sin-formato',
          label: f[6] || '', partLabel: f[7] || '', partType: f[8] || '', mount: f[9] || '',
          eligible: f[10] === 'yes', reason: f[11] || '', efi: f[12] === 'yes'
        });
      } else if (f[0] === 'FREE') {
        freeSpaces.push({
          kind: 'free', disk: f[1], start: f[2] || '', sectors: f[3] || '',
          sizeBytes: Number(f[4] || 0), size: f[5] || '', scheme: f[6] || '', eligible: true,
          fs: 'no-asignado'
        });
      }
    });
    state.disks = disks;
    state.parts = parts;
    state.freeSpaces = freeSpaces;
    if (!diskByPath(state.disk)) {
      state.disk = disks[0]?.path || '';
      state.rootPart = '';
      state.rootFreeStart = '';
      state.rootFreeSectors = '';
      state.efiPart = '';
    }
    if (state.rootFreeStart && !selectedRoot()) {
      state.rootFreeStart = '';
      state.rootFreeSectors = '';
    }
  }

  function reasonText(reason) {
    return ({
      'particion-efi': 'Reservada para EFI',
      'bios-boot': 'Partición BIOS Boot',
      'reservada-windows': 'Reservada por Windows; no debe usarse',
      'montada': 'Está montada',
      'solo-lectura': 'Sólo lectura',
      'menor-1GiB': 'Menor de 1 GiB',
      'otro-disco': 'Pertenece a otro disco',
      'no-es-particion': 'No es una partición'
    })[reason] || reason || 'No disponible';
  }

  function renderDisks() {
    const list = $('disk-list');
    list.textContent = '';
    $('disk-count').textContent = `${state.disks.length} disco${state.disks.length === 1 ? '' : 's'}`;
    if (!state.disks.length) {
      const empty = node('div', 'rounded-2xl border border-amber-400/20 bg-amber-400/5 p-4 text-sm text-amber-100', 'No se detectaron discos instalables. El medio Live se excluye automáticamente.');
      list.append(empty);
      return;
    }
    state.disks.forEach((disk) => {
      const active = state.disk === disk.path;
      const btn = node('button', `flex w-full min-w-0 flex-col items-stretch justify-between gap-3 rounded-2xl border p-4 text-left transition sm:flex-row sm:items-center sm:gap-4 ${active ? 'border-dex-500/50 bg-dex-950/40 ring-1 ring-dex-600/30' : 'border-white/10 bg-black/20 hover:border-white/20'}`);
      btn.type = 'button';
      btn.addEventListener('click', () => {
        state.disk = disk.path;
        state.rootPart = '';
        state.rootFreeStart = '';
        state.rootFreeSectors = '';
        state.efiPart = '';
        renderStorage();
      });
      const left = node('div', 'flex w-full min-w-0 items-center gap-3 sm:w-auto');
      const ico = node('div', `grid h-10 w-10 shrink-0 place-items-center rounded-xl ${active ? 'bg-dex-900 text-dex-200' : 'bg-white/5 text-zinc-500'}`);
      ico.append(icon('hard-drive', 'h-5 w-5'));
      const copy = node('div', 'min-w-0');
      copy.append(node('div', 'break-all text-sm font-semibold text-white', disk.path));
      copy.append(node('div', 'mt-1 break-words text-xs text-zinc-500', [disk.model, disk.transport].filter(Boolean).join(' · ') || 'Disco local'));
      left.append(ico, copy);
      const right = node('div', 'flex w-full shrink-0 items-center justify-between gap-3 text-left sm:block sm:w-auto sm:text-right');
      right.append(node('div', 'text-sm font-medium text-zinc-200', disk.size || `${disk.sizeBytes} B`));
      const caps = node('div', 'flex flex-wrap justify-end gap-1 sm:mt-1');
      if (disk.bios) caps.append(badge('BIOS', 'neutral'));
      if (disk.liveUefi) caps.append(badge('Live UEFI', 'red'));
      right.append(caps);
      btn.append(left, right);
      list.append(btn);
    });
  }

  function renderPartitions() {
    const section = $('partition-section');
    const list = $('partition-list');
    section.hidden = state.mode !== 'coexist';
    list.textContent = '';
    if (state.mode !== 'coexist') return;

    const parts = state.parts.filter((p) => p.disk === state.disk);
    const freeSpaces = state.freeSpaces.filter((f) => f.disk === state.disk);
    if (!parts.length && !freeSpaces.length) {
      list.append(node('div', 'rounded-2xl border border-amber-400/20 bg-amber-400/5 p-4 text-sm leading-6 text-amber-100', 'Este disco no contiene una partición utilizable ni al menos 1 GiB de espacio no asignado. Puedes usar “disco completo” o liberar espacio desde otro sistema.'));
      return;
    }

    parts.forEach((part) => {
      const active = state.rootPart === part.path;
      const btn = node('button', `flex w-full min-w-0 flex-col items-stretch justify-between gap-3 rounded-2xl border p-4 text-left transition sm:flex-row sm:items-center sm:gap-4 ${active ? 'border-dex-500/50 bg-dex-950/40 ring-1 ring-dex-600/30' : part.eligible ? 'border-white/10 bg-black/20 hover:border-white/20' : 'cursor-not-allowed border-white/5 bg-black/10 opacity-55'}`);
      btn.type = 'button';
      btn.disabled = !part.eligible;
      if (part.eligible) btn.addEventListener('click', () => {
        state.rootPart = part.path;
        state.rootFreeStart = '';
        state.rootFreeSectors = '';
        if (state.efiPart === part.path) state.efiPart = '';
        renderStorage();
      });
      const left = node('div', 'flex w-full min-w-0 items-center gap-3 sm:w-auto');
      const ico = node('div', `grid h-10 w-10 shrink-0 place-items-center rounded-xl ${part.fs === 'sin-formato' ? 'bg-dex-950 text-dex-300' : 'bg-white/5 text-zinc-500'}`);
      ico.append(icon(part.fs === 'sin-formato' ? 'square-dashed' : 'database', 'h-5 w-5'));
      const copy = node('div', 'min-w-0');
      const title = node('div', 'flex flex-wrap items-center gap-2');
      title.append(node('span', 'break-all text-sm font-semibold text-white', part.path));
      if (part.fs === 'sin-formato') title.append(badge('Sin formato', 'red'));
      else title.append(badge(part.fs, 'neutral'));
      if (part.efi) title.append(badge('EFI', 'amber'));
      copy.append(title);
      const subtitle = [part.label, part.partLabel].filter(Boolean).join(' · ') || (part.eligible ? 'Partición existente disponible para DexOS' : reasonText(part.reason));
      copy.append(node('div', 'mt-1 break-words text-xs text-zinc-500', subtitle));
      left.append(ico, copy);
      const right = node('div', 'flex w-full shrink-0 items-center justify-between gap-3 text-left sm:block sm:w-auto sm:text-right');
      right.append(node('div', 'text-sm font-medium text-zinc-200', part.size));
      if (!part.eligible) right.append(node('div', 'break-words text-[11px] text-zinc-600 sm:mt-1', reasonText(part.reason)));
      btn.append(left, right);
      list.append(btn);
    });

    freeSpaces.forEach((space) => {
      const active = !state.rootPart && state.rootFreeStart === space.start && state.rootFreeSectors === space.sectors;
      const btn = node('button', `flex w-full min-w-0 flex-col items-stretch justify-between gap-3 rounded-2xl border p-4 text-left transition sm:flex-row sm:items-center sm:gap-4 ${active ? 'border-dex-500/50 bg-dex-950/40 ring-1 ring-dex-600/30' : 'border-emerald-400/20 bg-emerald-500/[.04] hover:border-emerald-400/35'}`);
      btn.type = 'button';
      btn.addEventListener('click', () => {
        state.rootPart = '';
        state.rootFreeStart = space.start;
        state.rootFreeSectors = space.sectors;
        renderStorage();
      });
      const left = node('div', 'flex w-full min-w-0 items-center gap-3 sm:w-auto');
      const ico = node('div', 'grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-emerald-500/10 text-emerald-300');
      ico.append(icon('square-dashed', 'h-5 w-5'));
      const copy = node('div', 'min-w-0');
      const title = node('div', 'flex flex-wrap items-center gap-2');
      title.append(node('span', 'text-sm font-semibold text-white', 'Espacio no asignado'));
      title.append(badge('Sin partición', 'green'));
      copy.append(title);
      copy.append(node('div', 'mt-1 break-words text-xs leading-5 text-zinc-500', `DexOS creará una nueva partición aquí sólo al confirmar${space.scheme ? ` · tabla ${space.scheme.toUpperCase()}` : ''}.`));
      left.append(ico, copy);
      const right = node('div', 'flex w-full shrink-0 items-center justify-between gap-3 text-left sm:block sm:w-auto sm:text-right');
      right.append(node('div', 'text-sm font-medium text-emerald-200', space.size || `${space.sizeBytes} B`));
      right.append(node('div', 'mt-1 text-[11px] text-zinc-600', `sector ${space.start}`));
      btn.append(left, right);
      list.append(btn);
    });
  }

  function renderEfi() {
    const section = $('efi-section');
    section.hidden = state.mode !== 'coexist';
    if (section.hidden) return;
    const select = $('efi-select');
    const disk = selectedDisk();
    select.textContent = '';
    const none = document.createElement('option');
    none.value = '';
    none.textContent = disk?.bios ? 'Ninguna — usar GRUB BIOS' : 'Ninguna — sólo válida si el firmware/tabla permiten BIOS';
    select.append(none);
    state.parts.filter((p) => p.disk === state.disk && p.efi && p.path !== state.rootPart).forEach((p) => {
      const opt = document.createElement('option');
      opt.value = p.path;
      opt.textContent = `${p.path} · ${p.size} · ${p.fs}${p.label ? ` · ${p.label}` : ''}`;
      select.append(opt);
    });
    if (![...select.options].some((o) => o.value === state.efiPart)) state.efiPart = '';
    select.value = state.efiPart;
  }

  function renderModes() {
    modeCards.forEach((card) => {
      const active = card.dataset.mode === state.mode;
      card.className = `mode-card rounded-2xl border p-5 text-left transition ${active ? 'border-dex-500/50 bg-dex-950/40 ring-1 ring-dex-600/30' : 'border-white/10 bg-black/20 hover:border-white/20'}`;
      const ico = card.querySelector('i');
      if (ico) ico.className = `h-5 w-5 ${active ? 'text-dex-300' : 'text-zinc-400'}`;
    });
  }

  function renderStorage() {
    renderModes();
    renderDisks();
    renderPartitions();
    renderEfi();
    refreshIcons();
  }

  async function loadInventory() {
    const btn = $('refresh-btn');
    btn.disabled = true;
    btn.classList.add('opacity-50');
    try {
      const response = await fetch('/cgi-bin/inventory.cgi', { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      parseInventory(await response.text());
      renderStorage();
    } catch (error) {
      setError(`No se pudo leer el almacenamiento: ${error.message}`);
    } finally {
      btn.disabled = false;
      btn.classList.remove('opacity-50');
    }
  }

  async function loadLiveStatus() {
    const dl = $('live-status');
    try {
      const response = await fetch('/cgi-bin/status.cgi', { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const rows = (await response.text()).split(/\r?\n/).filter(Boolean).map((l) => l.split('\t'));
      const live = {};
      const net = {};
      const ips = [];
      rows.forEach((r) => {
        if (r[0] === 'LIVE') {
          const pos = (r[1] || '').indexOf('=');
          if (pos > 0) live[r[1].slice(0, pos)] = r[1].slice(pos + 1);
        } else if (r[0] === 'NET') {
          net[r[1] || ''] = r[2] || '';
        } else if (r[0] === 'IP') ips.push({ dev: r[1], ip: r[2] });
      });
      dl.textContent = '';
      const add = (name, value, tone = '') => {
        const row = node('div', 'flex min-w-0 flex-col gap-1 sm:flex-row sm:items-start sm:justify-between sm:gap-4');
        row.append(node('dt', 'shrink-0 text-zinc-500', name), node('dd', `break-anywhere min-w-0 sm:text-right ${tone || 'text-zinc-300'}`, value));
        dl.append(row);
      };
      add('Web', 'Activo', 'text-emerald-300');
      add('mDNS', 'dex.local');
      if (live.HOTSPOT === 'active') {
        add('Hotspot', `${live.SSID || 'Dex-Installer'} · ${live.AP_IP || '10.42.0.1'}`, 'text-dex-200');
        if (live.WIFI_DEVICE) add('Adaptador', live.WIFI_DEVICE);
      } else if (live.HOTSPOT === 'unsupported') {
        add('Hotspot', 'Adaptador detectado sin modo AP', 'text-amber-200');
        if (live.WIFI_DEVICE) add('Adaptador', live.WIFI_DEVICE);
      } else if (live.HOTSPOT === 'error') {
        add('Hotspot', `Error: ${live.REASON || 'servicio incompleto'}`, 'text-red-300');
      } else {
        add('Hotspot', 'Buscando tarjeta Wi-Fi/USB…', 'text-amber-200');
        if (live.WIFI_DEVICE) add('Adaptador', live.WIFI_DEVICE);
      }
      const internetLabel = ({ full: 'Disponible', limited: 'Limitada', portal: 'Portal cautivo', none: 'Sin conexión', unknown: 'Desconocida' })[net.connectivity] || net.connectivity;
      if (internetLabel) add('Internet', internetLabel, net.connectivity === 'full' ? 'text-emerald-300' : 'text-zinc-300');
      ips.filter((x) => x.ip !== '10.42.0.1').forEach((x) => add(`IPv4 · ${x.dev}`, x.ip));
      add('SSH Live', 'root / root');
      $('live-chip').innerHTML = '<span class="h-2 w-2 rounded-full bg-emerald-400"></span> Live listo';
    } catch (error) {
      dl.textContent = '';
      const row = node('div', 'text-sm text-amber-200', `No se pudo leer el estado: ${error.message}`);
      dl.append(row);
      $('live-chip').textContent = 'Live sin estado';
    }
  }

  function validateStorage() {
    if (!state.disk) return 'Selecciona un disco de destino.';
    if (state.mode === 'whole') return '';
    if (!state.rootPart && !state.rootFreeStart) return 'Selecciona una partición existente o un espacio no asignado para DexOS.';
    const root = selectedRoot();
    if (!root?.eligible) return 'El destino elegido ya no es válido. Pulsa actualizar y vuelve a seleccionarlo.';
    const disk = selectedDisk();
    const efiCandidates = state.parts.filter((p) => p.disk === state.disk && p.efi && p.path !== state.rootPart);
    if (disk?.liveUefi && !state.efiPart) return 'El Live arrancó en UEFI: selecciona una partición EFI existente. No se formateará.';
    if (!disk?.bios && !state.efiPart && efiCandidates.length) return 'Este disco no tiene BIOS Boot: selecciona una partición EFI existente.';
    return '';
  }

  function identityValues() {
    return {
      hostname: $('hostname').value.trim(),
      adminUser: $('admin-user').value.trim(),
      timezone: $('timezone').value.trim(),
      adminPassword: $('admin-password').value,
      adminRepeat: $('admin-password-repeat').value,
      rootPassword: $('same-root-password').checked ? '' : $('root-password').value,
      rootSsh: $('root-ssh').checked ? 'yes' : 'no',
      wifiSsid: $('install-wifi-ssid').value.trim(),
      wifiPassword: $('install-wifi-password').value
    };
  }

  function validateWifiSetup() {
    const v = identityValues();
    if (!v.wifiSsid) {
      if (v.wifiPassword) return 'Escribe el nombre de la red Wi-Fi o borra la contraseña.';
      return '';
    }
    if (new TextEncoder().encode(v.wifiSsid).length > 32) return 'El SSID Wi-Fi no puede superar 32 bytes.';
    if (v.wifiPassword && (v.wifiPassword.length < 8 || v.wifiPassword.length > 64)) return 'La contraseña Wi-Fi debe tener entre 8 y 64 caracteres, o quedar vacía para una red abierta.';
    if (v.wifiPassword.length === 64 && !/^[0-9a-fA-F]{64}$/.test(v.wifiPassword)) return 'Una contraseña Wi-Fi de 64 caracteres debe ser una clave hexadecimal.';
    return '';
  }

  function captureWifiSetup() {
    const v = identityValues();
    state.wifiSsid = v.wifiSsid;
    state.wifiPassword = v.wifiPassword;
    state.wifiHasPassword = v.wifiPassword.length > 0;
  }

  function validateIdentity() {
    const v = identityValues();
    const host = v.hostname.toLowerCase().replace(/\.$/, '').replace(/\.local$/, '');
    if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(host)) return 'El nombre del servidor no es válido.';
    if (!/^[a-z_][a-z0-9_-]{0,30}$/.test(v.adminUser) || v.adminUser === 'root') return 'El usuario administrador no es válido.';
    if (v.adminPassword.length < 8 || v.adminPassword.includes(':')) return 'La contraseña del administrador necesita al menos 8 caracteres y no puede contener “:”.';
    if (v.adminPassword !== v.adminRepeat) return 'Las contraseñas del administrador no coinciden.';
    if (!$('same-root-password').checked && (v.rootPassword.length < 8 || v.rootPassword.includes(':'))) return 'La contraseña root necesita al menos 8 caracteres y no puede contener “:”.';
    if (!v.timezone || v.timezone.startsWith('/') || v.timezone.includes('..')) return 'La zona horaria no es válida.';
    return '';
  }

  function addSummaryRow(term, detail, highlight = false) {
    const row = node('div', 'flex flex-col gap-1 py-3 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between sm:gap-5');
    row.append(node('dt', 'text-zinc-500', term), node('dd', `break-all font-medium ${highlight ? 'text-dex-200' : 'text-zinc-200'}`, detail));
    $('summary').append(row);
  }

  function renderSummary() {
    const v = identityValues();
    const disk = selectedDisk();
    const root = selectedRoot();
    $('summary').textContent = '';
    addSummaryRow('Servidor', v.hostname || 'dexos-server.local');
    addSummaryRow('Administrador', v.adminUser || 'admin');
    addSummaryRow('Zona horaria', v.timezone || 'UTC');
    addSummaryRow('Wi-Fi tras reiniciar', state.wifiSsid || 'No preconfigurado');
    addSummaryRow('Root por SSH', v.rootSsh === 'yes' ? 'Sí' : 'No');
    addSummaryRow('Modo', state.mode === 'whole' ? 'Disco completo' : 'Coexistencia');
    addSummaryRow('Disco', `${state.disk}${disk?.size ? ` · ${disk.size}` : ''}`, true);
    if (state.mode === 'coexist') {
      if (root?.kind === 'free') {
        addSummaryRow('Raíz DexOS', `Espacio no asignado · ${root.size} · se creará una partición nueva`, true);
        $('destructive-copy').textContent = `Se creará una nueva partición DexOS únicamente dentro del espacio no asignado seleccionado en ${state.disk}. Las particiones existentes se conservarán${state.efiPart ? `, incluida la ESP ${state.efiPart}` : ''}.`;
      } else {
        addSummaryRow('Raíz DexOS', `${state.rootPart}${root?.fs === 'sin-formato' ? ' · sin formato' : root?.fs ? ` · ${root.fs}` : ''}`, true);
        $('destructive-copy').textContent = `Se formateará únicamente ${state.rootPart} como ext4. Las demás particiones se conservarán${state.efiPart ? `, incluida ${state.efiPart}` : ''}.`;
      }
      addSummaryRow('ESP', state.efiPart || 'Ninguna');
    } else {
      $('destructive-copy').textContent = `Se borrará todo el contenido de ${state.disk} y se crearán nuevas particiones para DexOS Server.`;
    }
  }

  function validateStep() {
    if (state.step === 0) return validateWifiSetup();
    if (state.step === 1) return validateStorage();
    if (state.step === 2) return validateIdentity();
    if (state.step === 3 && !$('final-confirm').checked) return 'Marca la confirmación final para comenzar.';
    return '';
  }

  function formBody() {
    const v = identityValues();
    return new URLSearchParams({
      hostname: v.hostname,
      admin_user: v.adminUser,
      admin_password: v.adminPassword,
      root_password: v.rootPassword,
      ssh_root_login: v.rootSsh,
      timezone: v.timezone,
      wifi_ssid: state.wifiSsid,
      wifi_password: state.wifiPassword,
      wifi_has_password: state.wifiHasPassword ? 'yes' : 'no',
      install_mode: state.mode,
      disk: state.disk,
      root_part: state.mode === 'coexist' ? state.rootPart : '',
      root_free_start: state.mode === 'coexist' ? state.rootFreeStart : '',
      root_free_sectors: state.mode === 'coexist' ? state.rootFreeSectors : '',
      efi_part: state.mode === 'coexist' ? (state.efiPart || 'none') : '',
      confirm: 'INSTALLAR'
    });
  }

  async function startInstall() {
    state.installing = true;
    $('wizard-footer').hidden = true;
    $('install-log').textContent = '';
    $('install-running').hidden = false;
    $('install-done').hidden = true;
    try {
      const response = await fetch('/cgi-bin/install.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
        body: formBody().toString()
      });
      if (!response.ok) throw new Error(await response.text() || `HTTP ${response.status}`);
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let full = '';
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        const chunk = decoder.decode(value, { stream: true });
        full += chunk;
        $('install-log').textContent += chunk;
        $('install-log').scrollTop = $('install-log').scrollHeight;
      }
      full += decoder.decode();
      if (!full.includes('DexOS Server se instaló correctamente.')) {
        throw new Error('La instalación terminó sin confirmación de éxito. Revisa el registro.');
      }
      $('install-running').hidden = true;
      $('install-done').hidden = false;
      refreshIcons();
    } catch (error) {
      state.installing = false;
      $('install-log').textContent += `\n\nERROR WEB: ${error.message}\n`;
      $('install-log').scrollTop = $('install-log').scrollHeight;
      const retry = node('button', 'mt-4 inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-sm text-zinc-200 hover:border-dex-500/40', 'Volver a revisar');
      retry.type = 'button';
      retry.addEventListener('click', () => {
        retry.remove();
        $('wizard-footer').hidden = false;
        showStep(3);
      });
      $('install-running').append(retry);
    }
  }

  async function rebootSystem() {
    const button = $('reboot-btn');
    const status = $('reboot-status');
    button.disabled = true;
    status.hidden = false;
    status.textContent = 'Solicitando reinicio…';
    try {
      const response = await fetch('/cgi-bin/reboot.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
        body: 'confirm=REBOOT'
      });
      const text = await response.text();
      if (!response.ok || !text.includes('REBOOTING')) throw new Error(text.trim() || `HTTP ${response.status}`);
      button.textContent = 'Reiniciando…';
      status.textContent = 'El Live se está apagando. La conexión con esta página se cerrará en unos segundos.';
    } catch (error) {
      button.disabled = false;
      status.textContent = `No se pudo reiniciar: ${error.message}`;
    }
  }

  modeCards.forEach((card) => card.addEventListener('click', () => {
    state.mode = card.dataset.mode;
    state.rootPart = '';
    state.rootFreeStart = '';
    state.rootFreeSectors = '';
    state.efiPart = '';
    renderStorage();
  }));

  $('efi-select').addEventListener('change', (event) => { state.efiPart = event.target.value; });
  $('same-root-password').addEventListener('change', () => { $('root-password-wrap').hidden = $('same-root-password').checked; });
  $('refresh-btn').addEventListener('click', loadInventory);
  $('reboot-btn').addEventListener('click', rebootSystem);
  $('back-btn').addEventListener('click', () => showStep(state.step - 1));
  $('next-btn').addEventListener('click', async () => {
    const error = validateStep();
    if (error) { setError(error); return; }
    if (state.step === 3) {
      showStep(4);
      await startInstall();
      return;
    }
    if (state.step === 0) captureWifiSetup();
    showStep(state.step + 1);
  });

  document.addEventListener('DOMContentLoaded', () => {
    refreshIcons();
    showStep(0);
    loadLiveStatus();
    loadInventory();
    window.setInterval(loadLiveStatus, 3000);
  });
})();
