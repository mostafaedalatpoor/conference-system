/* ویرایشگر «صفحه‌ی ثبت‌نام» در پیشخوان وردپرس. همان تنظیم‌های اپ مدیریت؛ هنگام ذخیره JSON می‌شود. */
(function () {
  'use strict';
  var D = window.CD_REG_EDITOR;
  var root = document.getElementById('cd-reg-editor');
  var form = document.getElementById('cd-reg-form');
  if (!D || !root || !form) return;

  var def = {
    path: '', use_prefix: false, status: 'draft', list_mode: 'direct',
    content: { title: '', subtitle: '', description: '', logo_url: '', cover_url: '', days: [], venue: [], site_url: '', contact: '', links: [], closed_text: '' },
    theme: { accent: '#2A42D4', highlight: '#B7791F', mode: 'light', maker_credit: true },
    capacity_total: 0, deadline: '', types: [], fields: { email: 'optional', organization: 'required' },
    custom_fields: [], addons: [],
    payment: { method: 'gateway', gateway: 'zarinpal', gateway_settings: {}, link_url: '', link_text: '', card: { number: '', sheba: '', holder: '', bank: '', text: '', image_url: '', require: 'code' }, hold_hours: 48 },
    success: { show_personal_link: true, text: '' }
  };
  var cfg = JSON.parse(JSON.stringify(D.page || def));
  // نوع‌هایی که در پیکربندی هستند ولی هنوز در صفحه نه
  D.types.forEach(function (t) {
    if (!cfg.types.some(function (x) { return x.code === t.code; })) cfg.types.push({ code: t.code, description: '', price: 0, capacity: 0, deadline: '', visible: true });
  });
  cfg.types = cfg.types.filter(function (x) { return D.types.some(function (t) { return t.code === x.code; }); });

  function el(tag, attrs) {
    var n = document.createElement(tag);
    for (var k in attrs || {}) {
      if (attrs[k] == null || attrs[k] === false) continue;
      if (k === 'text') n.textContent = attrs[k];
      else if (k.indexOf('on') === 0) n.addEventListener(k.slice(2), attrs[k]);
      else n.setAttribute(k, attrs[k] === true ? '' : attrs[k]);
    }
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null || c === false) continue;
      (Array.isArray(c) ? c : [c]).forEach(function (x) { if (x) n.appendChild(typeof x === 'string' ? document.createTextNode(x) : x); });
    }
    return n;
  }
  function rid(p) { return p + Math.random().toString(36).slice(2, 8); }
  function row(label, input, help) {
    return el('tr', null, el('th', { scope: 'row' }, el('label', { text: label })), el('td', null, input, help ? el('p', { class: 'description', text: help }) : null));
  }
  function text(obj, key, attrs) {
    var a = { type: 'text', class: 'regular-text', value: obj[key] == null ? '' : obj[key], oninput: function (e) { obj[key] = e.target.value; } };
    for (var k in attrs || {}) a[k] = attrs[k];
    return el('input', a);
  }
  function num(obj, key) {
    return el('input', { type: 'number', min: '0', class: 'small-text', value: obj[key] || 0, oninput: function (e) { obj[key] = parseInt(e.target.value || '0', 10) || 0; } });
  }
  function area(obj, key, lines) {
    var v = obj[key];
    return el('textarea', { rows: '3', class: 'large-text', oninput: function (e) { obj[key] = lines ? e.target.value.split('\n').map(function (s) { return s.trim(); }).filter(Boolean) : e.target.value; } }, Array.isArray(v) ? v.join('\n') : (v || ''));
  }
  function check(obj, key, label) {
    return el('label', null, el('input', { type: 'checkbox', checked: !!obj[key], onchange: function (e) { obj[key] = e.target.checked; } }), ' ' + label);
  }
  function select(obj, key, options, onchange) {
    var s = el('select', { onchange: function (e) { obj[key] = e.target.value; if (onchange) onchange(); } });
    options.forEach(function (o) { s.appendChild(el('option', { value: o[0], selected: obj[key] === o[0], text: o[1] })); });
    return s;
  }
  function typeChecks(item) {
    item.types = item.types || [];
    return el('span', null, D.types.map(function (t) {
      return el('label', { style: 'margin-left:12px' }, el('input', { type: 'checkbox', checked: item.types.indexOf(t.code) >= 0, onchange: function (e) {
        if (e.target.checked) item.types.push(t.code); else item.types = item.types.filter(function (c) { return c !== t.code; });
      } }), ' ' + t.name);
    }), el('span', { class: 'description', text: ' (هیچ = همه)' }));
  }
  function section(title, rows) {
    return [el('h2', { text: title }), el('table', { class: 'form-table', role: 'presentation' }, el('tbody', null, rows))];
  }

  function render() {
    root.textContent = '';
    var c = cfg.content, t = cfg.theme, p = cfg.payment;
    var add = function (nodes) { nodes.forEach(function (n) { root.appendChild(n); }); };

    add(section('آدرس و وضعیت', [
      row('آدرس', el('span', { dir: 'ltr' }, D.home + (cfg.use_prefix ? 'register/' : ''), text(cfg, 'path', { dir: 'ltr', placeholder: 'mvip2026' })), 'فقط حروف کوچک انگلیسی، رقم و خط تیره.'),
      row('پیشوند', check(cfg, 'use_prefix', 'آدرس با register/ (تا با برگه‌های سایت قاطی نشود)')),
      row('وضعیت', select(cfg, 'status', [['draft', 'پیش‌نویس (فقط پیش‌نمایش مدیر)'], ['open', 'باز'], ['closed', 'بسته']])),
      row('ورود به لیست', select(cfg, 'list_mode', [['direct', 'مستقیم'], ['approval', 'بعد از تأیید مدیر'], ['separate', 'جدا (فقط فهرست و اکسل)']]))
    ]));

    add(section('محتوا', [
      row('تیتر', text(c, 'title')), row('زیرتیتر', text(c, 'subtitle')), row('توضیح', area(c, 'description')),
      row('نشانی لوگو', text(c, 'logo_url', { dir: 'ltr' })), row('نشانی تصویر سربرگ', text(c, 'cover_url', { dir: 'ltr' })),
      row('روزها', area(c, 'days', true), 'هر روز یک خط، مثلاً «چهارشنبه ۲۰ آبان ۱۴۰۵».'),
      row('مکان', area(c, 'venue', true), 'هر خط یک بخش، مثلاً «دانشگاه کاشان، تالار آزادی».'),
      row('سایت رویداد', text(c, 'site_url', { dir: 'ltr' })), row('تماس دبیرخانه', text(c, 'contact', { dir: 'ltr' })),
      row('لینک‌های پایین صفحه', el('textarea', { rows: '3', class: 'large-text', dir: 'ltr', oninput: function (e) {
        c.links = e.target.value.split('\n').map(function (l) { var x = l.split('|'); return x.length > 1 ? { label: x[0].trim(), url: x[1].trim() } : { label: '', url: l.trim() }; }).filter(function (l) { return l.url; });
      } }, (c.links || []).map(function (l) { return l.label + ' | ' + l.url; }).join('\n')), 'هر خط: «نام | نشانی»'),
      row('متن صفحه‌ی بسته', area(c, 'closed_text'))
    ]));

    add(section('تم', [
      row('رنگ اصلی', el('input', { type: 'color', value: t.accent, oninput: function (e) { t.accent = e.target.value.toUpperCase(); } })),
      row('رنگ دوم', el('input', { type: 'color', value: t.highlight, oninput: function (e) { t.highlight = e.target.value.toUpperCase(); } }), 'برای تیتر و قیمت‌ها.'),
      row('زمینه', select(t, 'mode', [['light', 'روشن'], ['dark', 'تیره']])),
      row('خط سازنده', check(t, 'maker_credit', '«ساخته‌شده با رویدادیار» پایین صفحه'))
    ]));

    var typeRows = cfg.types.map(function (x) {
      var name = (D.types.filter(function (t) { return t.code === x.code; })[0] || {}).name || x.code;
      return el('tr', null, el('td', null, check(x, 'visible', name)), el('td', null, text(x, 'description')), el('td', null, num(x, 'price')), el('td', null, num(x, 'capacity')), el('td', null, text(x, 'deadline', { dir: 'ltr', class: '', placeholder: '1405-08-15 18:00' })));
    });
    add([el('h2', { text: 'نوع‌های ثبت‌نام' }), el('p', { class: 'description', text: 'همان نوع‌های پیکربندی رویداد. قیمت به تومان (صفر = رایگان)، ظرفیت صفر = نامحدود، مهلت به وقت تهران (شمسی یا میلادی).' }),
      el('table', { class: 'widefat striped' }, el('thead', null, el('tr', null, ['نمایش', 'توضیح', 'قیمت', 'ظرفیت', 'مهلت'].map(function (h) { return el('th', { text: h }); }))), el('tbody', null, typeRows))]);
    add(section('ظرفیت و فیلدها', [
      row('ظرفیت کل', num(cfg, 'capacity_total'), 'صفر = نامحدود.'),
      row('مهلت کل', text(cfg, 'deadline', { dir: 'ltr', placeholder: '1405-08-15 18:00' })),
      row('ایمیل', select(cfg.fields, 'email', [['required', 'الزامی'], ['optional', 'اختیاری'], ['hidden', 'پنهان']])),
      row('سازمان', select(cfg.fields, 'organization', [['required', 'الزامی'], ['optional', 'اختیاری'], ['hidden', 'پنهان']]))
    ]));

    // فیلدهای دلخواه
    var cf = el('div');
    cfg.custom_fields.forEach(function (f, i) {
      f.options = f.options || [];
      cf.appendChild(el('div', { class: 'card', style: 'max-width:none' }, el('table', { class: 'form-table' }, el('tbody', null, [
        row('عنوان', text(f, 'label')),
        row('نوع', select(f, 'kind', [['text', 'متن کوتاه'], ['select', 'تک‌انتخابی'], ['multi', 'چندانتخابی']], render)),
        row('', check(f, 'required', 'الزامی')), row('راهنما', text(f, 'help')),
        f.kind === 'text' ? null : row('گزینه‌ها', el('textarea', { rows: '4', class: 'large-text', oninput: function (e) {
          var old = f.options;
          f.options = e.target.value.split('\n').map(function (l, j) { var x = l.split('|'); var label = x[0].trim(); return label ? { id: (old[j] && old[j].label === label) ? old[j].id : rid('o'), label: label, capacity: parseInt((x[1] || '0').trim(), 10) || 0 } : null; }).filter(Boolean);
        } }, f.options.map(function (o) { return o.label + (o.capacity ? ' | ' + o.capacity : ''); }).join('\n')), 'هر خط یک گزینه؛ ظرفیت اختیاری: «کارگاه پزشکی | 30»'),
        row('برای نوع‌ها', typeChecks(f)),
        row('', el('button', { type: 'button', class: 'button-link-delete', onclick: function () { cfg.custom_fields.splice(i, 1); render(); } }, 'حذف این فیلد'))
      ]))));
    });
    add([el('h2', { text: 'فیلدهای دلخواه' }), cf, el('button', { type: 'button', class: 'button', onclick: function () { cfg.custom_fields.push({ id: rid('f'), label: '', kind: 'text', required: false, help: '', options: [], types: [] }); render(); } }, 'افزودن فیلد')]);

    // گزینه‌های اضافه
    var ad = el('div');
    cfg.addons.forEach(function (a, i) {
      var meals = [['', 'وصل نیست']].concat(D.meals.map(function (m) { return [m.code, m.name + (m.day ? ' (' + m.day + ')' : '')]; }));
      ad.appendChild(el('div', { class: 'card', style: 'max-width:none' }, el('table', { class: 'form-table' }, el('tbody', null, [
        row('عنوان', text(a, 'title')), row('توضیح زیرش', text(a, 'description'), 'مثلاً «تسویه در روز اجرا».'),
        row('قیمت (تومان)', num(a, 'price')),
        row('پرداخت', select(a, 'price_mode', [['online', 'روی مبلغ آنلاین'], ['onsite', 'تسویه در روز اجرا'], ['info', 'فقط اطلاع (بدون قیمت)']])),
        row('ظرفیت', num(a, 'capacity'), 'صفر = نامحدود.'),
        row('وعده‌ی پذیرایی', select(a, 'meal_code', meals), 'کسی که این گزینه را بزند، در اپ نیروها برای این وعده مجاز می‌شود.'),
        row('برای نوع‌ها', typeChecks(a)),
        row('', el('button', { type: 'button', class: 'button-link-delete', onclick: function () { cfg.addons.splice(i, 1); render(); } }, 'حذف این گزینه'))
      ]))));
    });
    add([el('h2', { text: 'گزینه‌های اضافه' }), ad, el('button', { type: 'button', class: 'button', onclick: function () { cfg.addons.push({ id: rid('a'), title: '', description: '', price: 0, price_mode: 'online', capacity: 0, meal_code: '', types: [] }); render(); } }, 'افزودن گزینه')]);

    // پرداخت
    var gw = D.gateways.filter(function (g) { return g.id === p.gateway; })[0];
    p.gateway_settings = p.gateway_settings || {};
    var payRows = [row('روش', select(p, 'method', [['gateway', 'درگاه'], ['link', 'لینک بیرونی'], ['card', 'کارت‌به‌کارت / صفحه‌ی توضیح']], render), 'فقط وقتی نوع یا گزینه‌ای مبلغ آنلاین دارد.')];
    if (p.method === 'gateway') {
      payRows.push(row('درگاه', select(p, 'gateway', D.gateways.map(function (g) { return [g.id, g.name]; }), render), 'درگاه دیگر را با قلاب roydadyar_payment_gateways اضافه کنید (راهنما در README).'));
      (gw ? gw.fields : []).forEach(function (f) { payRows.push(row(f.label, text(p.gateway_settings, f.key, { dir: 'ltr' }))); });
    } else if (p.method === 'link') {
      payRows.push(row('نشانی لینک', text(p, 'link_url', { dir: 'ltr' })), row('توضیح', area(p, 'link_text')));
    } else {
      payRows.push(row('شماره کارت', text(p.card, 'number', { dir: 'ltr' })), row('شبا', text(p.card, 'sheba', { dir: 'ltr' })),
        row('صاحب حساب', text(p.card, 'holder')), row('بانک', text(p.card, 'bank')), row('توضیح', area(p.card, 'text')),
        row('نشانی تصویر', text(p.card, 'image_url', { dir: 'ltr' })),
        row('از فرد بخواهد', select(p.card, 'require', [['code', 'شماره‌ی پیگیری'], ['receipt', 'تصویر رسید'], ['both', 'هر دو']])));
    }
    if (p.method !== 'gateway') payRows.push(row('نگه‌داشتن جا (ساعت)', num(p, 'hold_hours'), 'اگر تا این مدت رسید یا تأیید پرداخت نیاید، جا آزاد می‌شود.'));
    add(section('پرداخت', payRows));

    add(section('صفحه‌ی تأیید', [
      row('', check(cfg.success, 'show_personal_link', 'لینک صفحه‌ی شخصی (QR) نشان داده شود')),
      row('متن اضافه', area(cfg.success, 'text'))
    ]));
  }

  form.addEventListener('submit', function () {
    document.getElementById('cd-reg-config').value = JSON.stringify(cfg);
  });
  render();
})();
