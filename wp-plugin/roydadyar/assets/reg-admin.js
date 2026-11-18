/* ویرایشگر «صفحه‌ی ثبت‌نام» در پیشخوان وردپرس، در ۷ گام (بوم ۰۸-RegSetup). همان تنظیم‌های اپ مدیریت؛ هنگام ذخیره JSON می‌شود. */
(function () {
  'use strict';
  var D = window.CD_REG_EDITOR;
  var root = document.getElementById('cd-reg-editor');
  var form = document.getElementById('cd-reg-form');
  if (!D || !root || !form) return;

  var cfg = JSON.parse(JSON.stringify(D.page || D.defaults));
  cfg.messages = cfg.messages || D.defaults.messages;
  // نوع‌هایی که در پیکربندی هستند ولی هنوز در صفحه نه
  D.types.forEach(function (t) {
    if (!cfg.types.some(function (x) { return x.code === t.code; })) cfg.types.push({ code: t.code, description: '', price: 0, capacity: 0, deadline: '', visible: true });
  });
  cfg.types = cfg.types.filter(function (x) { return D.types.some(function (t) { return t.code === x.code; }); });
  var step = Math.max(1, Math.min(7, parseInt(D.step || '1', 10) || 1));
  var STEPS = ['آدرس و ورود به لیست', 'محتوا و ظاهر', 'نوع‌ها و ظرفیت', 'اطلاعات بیشتر و گزینه‌ها', 'پرداخت', 'پیام‌ها', 'پیش‌نمایش و انتشار'];

  function el(tag, attrs) {
    var n = document.createElement(tag);
    for (var k in attrs || {}) {
      if (attrs[k] == null || attrs[k] === false) continue;
      if (k === 'text') n.textContent = attrs[k];
      else if (k === 'class') n.className = attrs[k];
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
  function card(title, hint, body, pop) {
    return el('div', { class: 'cd-card' + (pop ? ' pop' : ''), style: 'display:flex;flex-direction:column;gap:12px' },
      title ? el('h2', { text: title }) : null, hint ? el('span', { class: 'cd-mu', style: 'font-size:12px', text: hint }) : null, body);
  }
  function lab(label, input, help) {
    return el('div', { class: 'ry-fl' }, el('span', { text: label }), input, help ? el('span', { class: 'cd-mu', style: 'font-size:12px', text: help }) : null);
  }
  function text(obj, key, attrs) {
    var a = { type: 'text', value: obj[key] == null ? '' : obj[key], oninput: function (e) { obj[key] = e.target.value; } };
    for (var k in attrs || {}) a[k] = attrs[k];
    return el('div', { class: 'cd-field' }, el('input', a));
  }
  function num(obj, key) {
    return el('div', { class: 'cd-field', style: 'max-width:200px' }, el('input', { type: 'number', min: '0', value: obj[key] || 0, oninput: function (e) { obj[key] = parseInt(e.target.value || '0', 10) || 0; } }));
  }
  function area(obj, key, lines, rows) {
    var v = obj[key];
    return el('textarea', { rows: rows || '3', class: 'ry-area', oninput: function (e) { obj[key] = lines ? e.target.value.split('\n').map(function (s) { return s.trim(); }).filter(Boolean) : e.target.value; } }, Array.isArray(v) ? v.join('\n') : (v || ''));
  }
  function toggle(obj, key, label, hint) {
    return el('label', { class: 'ry-tg' }, el('span', { style: 'flex-grow:1;display:flex;flex-direction:column' }, el('b', { text: label }), hint ? el('span', { class: 'cd-mu', style: 'font-size:12px', text: hint }) : null),
      el('input', { type: 'checkbox', checked: !!obj[key], onchange: function (e) { obj[key] = e.target.checked; } }));
  }
  function seg(obj, key, options, onchange) {
    return el('div', { class: 'ry-seg', role: 'radiogroup' }, options.map(function (o) {
      return el('button', { type: 'button', class: obj[key] === o[0] ? 'on' : '', 'aria-pressed': obj[key] === o[0] ? 'true' : 'false', onclick: function () { obj[key] = o[0]; if (onchange) onchange(); else render(); } }, o[1]);
    }));
  }
  function select(obj, key, options, onchange) {
    var s = el('select', { onchange: function (e) { obj[key] = e.target.value; if (onchange) onchange(); } });
    options.forEach(function (o) { s.appendChild(el('option', { value: o[0], selected: obj[key] === o[0], text: o[1] })); });
    return el('div', { class: 'cd-field' }, s);
  }
  function typeChecks(item) {
    item.types = item.types || [];
    return el('div', { style: 'display:flex;gap:12px;flex-wrap:wrap' }, el('span', { class: 'cd-mu', style: 'font-size:12px', text: 'برای نوع‌ها (هیچ = همه):' }), D.types.map(function (t) {
      return el('label', null, el('input', { type: 'checkbox', checked: item.types.indexOf(t.code) >= 0, onchange: function (e) {
        if (e.target.checked) item.types.push(t.code); else item.types = item.types.filter(function (c) { return c !== t.code; });
      } }), ' ' + t.name);
    }));
  }

  function steps() {
    return el('div', { class: 'cd-card pop', style: 'display:flex;flex-direction:column;gap:4px;padding:12px' },
      STEPS.map(function (s, i) {
        var n = i + 1;
        return el('button', { type: 'button', class: 'ry-st' + (n === step ? ' on' : ''), onclick: function () { step = n; render(); } },
          el('span', { class: 'n', text: n < step ? '✓' : String(n).replace(/\d/g, function (d) { return '۰۱۲۳۴۵۶۷۸۹'[d]; }) }), n === step ? el('b', { text: s }) : s);
      }),
      el('span', { class: 'cd-mu', style: 'font-size:12px;padding:8px 10px 4px', text: 'همین تنظیم‌ها در اپ مدیریت هم هست؛ هر کدام را عوض کنید، دیگری همان را می‌بیند.' }));
  }

  function body() {
    var c = cfg.content, t = cfg.theme, p = cfg.payment;
    switch (step) {
      case 1:
        return [
          card('آدرس صفحه‌ی ثبت‌نام', 'شرکت‌کنندگان با این آدرس وارد می‌شوند. آدرس را شما تعیین می‌کنید.', [
            el('div', { dir: 'ltr', style: 'display:flex;align-items:center;gap:8px' }, el('span', { class: 'cd-mu', text: D.home + (cfg.use_prefix ? 'register/' : '') }),
              el('div', { class: 'cd-field', style: 'flex-grow:1' }, el('input', { type: 'text', dir: 'ltr', value: cfg.path, placeholder: 'vision-1405', oninput: function (e) { cfg.path = e.target.value.toLowerCase(); } }))),
            el('span', { class: 'cd-mu', style: 'font-size:12px', text: 'فقط حروف کوچک انگلیسی، رقم و خط تیره.' }),
            toggle(cfg, 'use_prefix', 'با پیشوند register/', 'تا آدرس با برگه‌های سایت قاطی نشود.')
          ], true),
          el('div', { class: 'cd-grid cd-g2' },
            card('ورود به لیست', { direct: 'هر ثبت‌نام قطعی فوراً شرکت‌کننده می‌شود، با کارت و شماره.', approval: 'هر ثبت‌نام اول منتظر تأیید شما می‌ماند.', separate: 'ثبت‌نام‌ها فقط در فهرست و اکسل می‌مانند و وارد لیست روز اجرا نمی‌شوند.' }[cfg.list_mode],
              seg(cfg, 'list_mode', [['direct', 'مستقیم'], ['approval', 'با تأیید مدیر'], ['separate', 'جدا']])),
            card('وضعیت صفحه', 'پیش‌نویس فقط برای مدیر واردشده پیش‌نمایش دارد.', seg(cfg, 'status', [['draft', 'پیش‌نویس'], ['open', 'باز'], ['closed', 'بسته']])))
        ];
      case 2:
        return [
          card('محتوای صفحه', null, [
            lab('تیتر (خالی = نام رویداد)', text(c, 'title')), lab('زیرتیتر', text(c, 'subtitle')), lab('توضیح', area(c, 'description')),
            el('div', { class: 'cd-grid cd-g2' }, lab('روزها (هر خط یک روز)', area(c, 'days', true)), lab('مکان (هر خط یک بخش)', area(c, 'venue', true))),
            el('div', { class: 'cd-grid cd-g2' }, lab('نشانی لوگو', text(c, 'logo_url', { dir: 'ltr' })), lab('نشانی تصویر سربرگ', text(c, 'cover_url', { dir: 'ltr' }))),
            el('div', { class: 'cd-grid cd-g2' }, lab('سایت رویداد', text(c, 'site_url', { dir: 'ltr' })), lab('تماس دبیرخانه', text(c, 'contact', { dir: 'ltr' }))),
            lab('لینک‌های پایین صفحه', el('textarea', { rows: '3', class: 'ry-area', dir: 'ltr', oninput: function (e) {
              c.links = e.target.value.split('\n').map(function (l) { var x = l.split('|'); return x.length > 1 ? { label: x[0].trim(), url: x[1].trim() } : { label: '', url: l.trim() }; }).filter(function (l) { return l.url; });
            } }, (c.links || []).map(function (l) { return l.label + ' | ' + l.url; }).join('\n')), 'هر خط: «نام | نشانی»'),
            lab('متن صفحه‌ی بسته', area(c, 'closed_text'))
          ], true),
          card('ظاهر', 'رنگ برند صفحه؛ رنگ‌های معنایی (تأیید، هشدار، خطا) عوض نمی‌شوند.', [
            el('div', { style: 'display:flex;gap:10px;flex-wrap:wrap;align-items:center' }, ['#0B7A7B', '#1D5FD1', '#6B3FA0', '#B34A00'].map(function (hex) {
              return el('button', { type: 'button', class: 'ry-sw' + (t.accent.toUpperCase() === hex ? ' on' : ''), style: 'background:' + hex, 'aria-label': hex, onclick: function () { t.accent = hex; render(); } });
            }), el('input', { type: 'color', value: t.accent, oninput: function (e) { t.accent = e.target.value.toUpperCase(); } })),
            lab('رنگ دوم (قیمت‌ها و تیترها)', el('input', { type: 'color', value: t.highlight, oninput: function (e) { t.highlight = e.target.value.toUpperCase(); } })),
            lab('زمینه', seg(t, 'mode', [['light', 'روشن'], ['dark', 'تیره']])),
            toggle(t, 'maker_credit', 'خط سازنده', '«ساخته‌شده با رویدادیار» پایین صفحه')
          ])
        ];
      case 3:
        return [
          card('نوع‌ها و قیمت', 'همان نوع‌های پیکربندی رویداد. قیمت به تومان (صفر = رایگان)، ظرفیت صفر = نامحدود، مهلت به وقت تهران.',
            el('div', { class: 'ry-tbl' }, el('div', { class: 'h' }, ['نمایش', 'توضیح', 'قیمت', 'ظرفیت', 'مهلت'].map(function (h) { return el('span', { text: h }); })),
              cfg.types.map(function (x) {
                var name = (D.types.filter(function (t) { return t.code === x.code; })[0] || {}).name || x.code;
                return el('div', null, el('label', null, el('input', { type: 'checkbox', checked: x.visible, onchange: function (e) { x.visible = e.target.checked; } }), ' ' + name),
                  text(x, 'description'), num(x, 'price'), num(x, 'capacity'), text(x, 'deadline', { dir: 'ltr', placeholder: '1405-09-10 18:00' }));
              })), true),
          card('ظرفیت و مهلت کل', null, el('div', { class: 'cd-grid cd-g2' }, lab('ظرفیت کل (صفر = نامحدود)', num(cfg, 'capacity_total')), lab('مهلت کل', text(cfg, 'deadline', { dir: 'ltr', placeholder: '1405-09-10 18:00' }))))
        ];
      case 4: {
        var cf = cfg.custom_fields.map(function (f, i) {
          f.options = f.options || [];
          return el('div', { class: 'ry-sub' },
            el('div', { class: 'cd-grid cd-g2' }, lab('عنوان', text(f, 'label')), lab('نوع', select(f, 'kind', [['text', 'متن کوتاه'], ['select', 'تک‌انتخابی'], ['multi', 'چندانتخابی']], render))),
            lab('راهنما', text(f, 'help')), toggle(f, 'required', 'الزامی'),
            f.kind === 'text' ? null : lab('گزینه‌ها', el('textarea', { rows: '4', class: 'ry-area', oninput: function (e) {
              var old = f.options;
              f.options = e.target.value.split('\n').map(function (l, j) { var x = l.split('|'); var label = x[0].trim(); return label ? { id: (old[j] && old[j].label === label) ? old[j].id : rid('o'), label: label, capacity: parseInt((x[1] || '0').trim(), 10) || 0 } : null; }).filter(Boolean);
            } }, f.options.map(function (o) { return o.label + (o.capacity ? ' | ' + o.capacity : ''); }).join('\n')), 'هر خط یک گزینه؛ ظرفیت اختیاری: «کارگاه پزشکی | 30»'),
            typeChecks(f),
            el('button', { type: 'button', class: 'cd-btn danger sm', onclick: function () { cfg.custom_fields.splice(i, 1); render(); } }, 'حذف این فیلد'));
        });
        var meals = [['', 'وصل نیست']].concat(D.meals.map(function (m) { return [m.code, m.name + (m.day ? ' (' + m.day + ')' : '')]; }));
        var ad = cfg.addons.map(function (a, i) {
          return el('div', { class: 'ry-sub' },
            el('div', { class: 'cd-grid cd-g2' }, lab('عنوان', text(a, 'title')), lab('توضیح زیرش', text(a, 'description'))),
            el('div', { class: 'cd-grid cd-g2' }, lab('قیمت (تومان)', num(a, 'price')), lab('ظرفیت (صفر = نامحدود)', num(a, 'capacity'))),
            lab('پرداخت', seg(a, 'price_mode', [['online', 'روی مبلغ آنلاین'], ['onsite', 'در محل'], ['info', 'فقط اطلاع']])),
            lab('وعده‌ی پذیرایی', select(a, 'meal_code', meals), 'کسی که این گزینه را بزند، در اپ نیروها برای این وعده مجاز می‌شود.'),
            typeChecks(a),
            el('button', { type: 'button', class: 'cd-btn danger sm', onclick: function () { cfg.addons.splice(i, 1); render(); } }, 'حذف این گزینه'));
        });
        return [
          card('فیلدهای فرم', null, el('div', { class: 'cd-grid cd-g2' },
            lab('ایمیل', seg(cfg.fields, 'email', [['required', 'الزامی'], ['optional', 'اختیاری'], ['hidden', 'پنهان']])),
            lab('سازمان', seg(cfg.fields, 'organization', [['required', 'الزامی'], ['optional', 'اختیاری'], ['hidden', 'پنهان']]))), true),
          card('اطلاعات بیشتر', 'پرسش‌های دلخواه، مثل رشته یا کارگاه‌ها.', [cf, el('button', { type: 'button', class: 'cd-btn sm', onclick: function () { cfg.custom_fields.push({ id: rid('f'), label: '', kind: 'text', required: false, help: '', options: [], types: [] }); render(); } }, '+ افزودن فیلد')]),
          card('گزینه‌های اضافه', 'مثل ناهار یا شام؛ با پرداخت آنلاین، در محل، یا فقط اطلاع.', [ad, el('button', { type: 'button', class: 'cd-btn sm', onclick: function () { cfg.addons.push({ id: rid('a'), title: '', description: '', price: 0, price_mode: 'online', capacity: 0, meal_code: '', types: [] }); render(); } }, '+ افزودن گزینه')])
        ];
      }
      case 5: {
        p.gateway_settings = p.gateway_settings || {};
        var gw = D.gateways.filter(function (g) { return g.id === p.gateway; })[0];
        var inner = [lab('روش', seg(p, 'method', [['gateway', 'درگاه'], ['link', 'لینک بیرونی'], ['card', 'کارت‌به‌کارت']]), 'فقط وقتی نوع یا گزینه‌ای مبلغ آنلاین دارد.')];
        if (p.method === 'gateway') {
          inner.push(lab('درگاه', select(p, 'gateway', D.gateways.map(function (g) { return [g.id, g.name]; }), render)));
          (gw ? gw.fields : []).forEach(function (f) { inner.push(lab(f.label, text(p.gateway_settings, f.key, { dir: 'ltr' }))); });
          if (p.gateway === 'custom') inner.push(el('div', { class: 'cd-callout go' }, el('span', null, 'آدرس شروع، آدرس تأیید، هدر و بدنه‌ی «درگاه دلخواه» در ', el('a', { href: D.connect_url, text: 'اتصال درگاه و پیامک' }), ' تنظیم می‌شود.')));
          inner.push(el('div', { class: 'cd-callout wait' }, el('span', null, 'برای آزمون یک پرداخت واقعی ۱۰۰ تومانی، صفحه را ذخیره کنید و در ', el('a', { href: D.connect_url, text: 'اتصال درگاه و پیامک' }), ' «آزمون با ۱۰۰ تومان» را بزنید.')));
        } else if (p.method === 'link') {
          inner.push(lab('نشانی لینک', text(p, 'link_url', { dir: 'ltr' })), lab('توضیح', area(p, 'link_text')));
        } else {
          inner.push(el('div', { class: 'cd-grid cd-g2' }, lab('شماره کارت', text(p.card, 'number', { dir: 'ltr' })), lab('شبا', text(p.card, 'sheba', { dir: 'ltr' }))),
            el('div', { class: 'cd-grid cd-g2' }, lab('صاحب حساب', text(p.card, 'holder')), lab('بانک', text(p.card, 'bank'))),
            lab('توضیح', area(p.card, 'text')), lab('نشانی تصویر', text(p.card, 'image_url', { dir: 'ltr' })),
            lab('از فرد بخواهد', seg(p.card, 'require', [['code', 'شماره‌ی پیگیری'], ['receipt', 'تصویر رسید'], ['both', 'هر دو']])));
        }
        if (p.method !== 'gateway') inner.push(lab('نگه‌داشتن جا (ساعت)', num(p, 'hold_hours'), 'اگر تا این مدت رسید یا تأیید پرداخت نیاید، جا آزاد می‌شود.'));
        return [card('پرداخت', null, inner, true)];
      }
      case 6: {
        var m = cfg.messages;
        return [
          card('پیام به ثبت‌نام‌کننده', 'با هر تغییر وضعیت، این متن‌ها با پیامک یا ایمیل فرستاده می‌شوند. متن خالی = بدون پیام.', [
            toggle(m, 'sms', 'پیامک', D.sms_ready ? 'با سرویس پیامکی که در «اتصال درگاه و پیامک» تنظیم شده.' : 'سرویس پیامک هنوز تنظیم نشده؛ اول در «اتصال درگاه و پیامک» وصلش کنید.'),
            toggle(m, 'email', 'ایمیل', 'با ایمیل خود سایت (wp_mail).'),
            el('span', { class: 'cd-mu', style: 'font-size:12px', dir: 'ltr', text: D.variables.join(' ') })
          ], true),
          card('متن‌ها', null, Object.keys(D.triggers).map(function (k) { return lab(D.triggers[k], area(m.templates, k, false, '2')); })),
          el('a', { class: 'cd-btn', href: D.connect_url }, 'اتصال درگاه و پیامک و آخرین ارسال‌ها')
        ];
      }
      default:
        return [
          card('صفحه‌ی تأیید', null, [toggle(cfg.success, 'show_personal_link', 'لینک صفحه‌ی شخصی (QR)', 'بعد از تأیید، فرد صفحه‌ی شخصی‌اش را می‌بیند.'), lab('متن اضافه', area(cfg.success, 'text'))], true),
          card('انتشار', D.url ? 'آدرس: ' + D.url : 'اول آدرس صفحه را در گام ۱ بنویسید و ذخیره کنید.', [
            seg(cfg, 'status', [['draft', 'پیش‌نویس'], ['open', 'باز'], ['closed', 'بسته']]),
            D.url ? el('a', { class: 'cd-btn', href: D.url, target: '_blank', rel: 'noopener' }, 'پیش‌نمایش صفحه') : null
          ])
        ];
    }
  }

  function render() {
    root.textContent = '';
    var save = el('button', { type: 'submit', class: 'cd-btn pri', style: 'height:52px;padding:0 32px;border-radius:16px;font-size:15px', onclick: function () { document.getElementById('cd-reg-next').value = String(Math.min(7, step + 1)); } }, step < 7 ? 'ذخیره و بعدی' : 'ذخیره');
    var stay = el('button', { type: 'submit', class: 'cd-btn', style: 'height:52px', onclick: function () { document.getElementById('cd-reg-next').value = String(step); } }, 'فقط ذخیره');
    root.appendChild(el('div', { class: 'cd-grid', style: 'grid-template-columns:250px 1fr;align-items:start' }, steps(),
      el('div', { style: 'display:flex;flex-direction:column;gap:14px' }, body(), el('div', { style: 'display:flex;gap:10px;flex-wrap:wrap' }, save, stay,
        D.url ? el('a', { class: 'cd-btn', style: 'height:52px', href: D.url, target: '_blank', rel: 'noopener' }, 'پیش‌نمایش صفحه') : null))));
  }

  form.addEventListener('submit', function () {
    document.getElementById('cd-reg-config').value = JSON.stringify(cfg);
  });
  render();
})();
