/* رویدادیار — منطق صفحه‌ی ثبت‌نام. بدون کتابخانه؛ همه‌ی متن‌ها با textContent گذاشته می‌شوند. */
(function () {
  'use strict';
  var C = window.RY_REG;
  var view = document.getElementById('view');
  var trackLink = document.getElementById('track-link');
  if (!C || !view) return;

  // ------------------------------------------------------------ کمکی‌ها
  function el(tag, attrs) {
    var n = document.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, k) || attrs[k] == null || attrs[k] === false) continue;
        if (k === 'text') n.textContent = attrs[k];
        else if (k === 'class') n.className = attrs[k];
        else if (k.indexOf('on') === 0) n.addEventListener(k.slice(2), attrs[k]);
        else n.setAttribute(k, attrs[k] === true ? '' : attrs[k]);
      }
    }
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null || c === false) continue;
      if (Array.isArray(c)) c.forEach(function (x) { if (x) n.appendChild(typeof x === 'string' ? document.createTextNode(x) : x); });
      else n.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return n;
  }
  var FA = '۰۱۲۳۴۵۶۷۸۹';
  function fa(s) { return String(s).replace(/\d/g, function (d) { return FA[d]; }); }
  function latin(s) {
    return String(s || '').replace(/[۰-۹]/g, function (d) { return FA.indexOf(d); })
      .replace(/[٠-٩]/g, function (d) { return '٠١٢٣٤٥٦٧٨٩'.indexOf(d); });
  }
  function money(n) { return n > 0 ? fa(Number(n).toLocaleString('en-US').replace(/,/g, '٬')) + ' تومان' : 'رایگان'; }
  function mobileNorm(s) {
    var d = latin(s).replace(/\D+/g, '');
    if (d.indexOf('0098') === 0) d = '0' + d.slice(4);
    else if (d.indexOf('98') === 0 && d.length === 12) d = '0' + d.slice(2);
    else if (d.length === 10 && d[0] === '9') d = '0' + d;
    return d;
  }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    (window.crypto || window.msCrypto).getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function icon(kind) {
    var paths = {
      ok: 'M5 12.5l4.5 4.5L19 7.5', wait: 'M12 7v5l3 2M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18z',
      stop: 'M12 7v6M12 16.5v.5M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18z', card: 'M3 6h18v12H3zM3 10h18M7 15h4'
    };
    var colors = { ok: 'var(--go)', wait: 'var(--wait)', stop: 'var(--stop)', card: 'var(--accent-text)' };
    var bg = { ok: 'var(--go-soft)', wait: 'var(--wait-soft)', stop: 'var(--stop-soft)', card: 'var(--accent-soft)' };
    var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    s.setAttribute('width', '36'); s.setAttribute('height', '36'); s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('fill', 'none'); s.setAttribute('stroke', colors[kind]); s.setAttribute('stroke-width', '2.2');
    s.setAttribute('stroke-linecap', 'round'); s.setAttribute('aria-hidden', 'true');
    var p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', paths[kind]); s.appendChild(p);
    var span = el('span', { class: 'ic' }, s);
    span.style.background = bg[kind];
    return span;
  }
  var started = false;
  function show(nodes) {
    view.textContent = '';
    (Array.isArray(nodes) ? nodes : [nodes]).forEach(function (n) { if (n) view.appendChild(n); });
    if (started) view.scrollIntoView({ block: 'start' });
    started = true;
  }
  function post(path, body) {
    var isForm = body instanceof FormData;
    return fetch(C.api + path, {
      method: 'POST',
      credentials: 'omit',
      headers: isForm ? {} : { 'Content-Type': 'application/json' },
      body: isForm ? body : JSON.stringify(body)
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) { return { status: r.status, body: j }; });
    });
  }
  function typeName(code) {
    for (var i = 0; i < C.types.length; i++) if (C.types[i].code === code) return C.types[i].name;
    return code;
  }
  function addonTitle(id) {
    for (var i = 0; i < C.addons.length; i++) if (C.addons[i].id === id) return C.addons[i].title;
    return id;
  }
  function setUrl(code, key) {
    try {
      var u = new URL(location.href);
      u.search = '';
      if (code) { u.searchParams.set('code', code); u.searchParams.set('k', key); }
      u.hash = '';
      history.replaceState(null, '', u.toString());
    } catch (e) { /* مرورگر قدیمی */ }
  }

  // ------------------------------------------------------------ فرم
  var draft = null; // اطلاعات فرم تا ارسال موفق نگه داشته می‌شود
  var submitId = uuid();

  function field(id, label, input, opts) {
    opts = opts || {};
    return el('div', { class: 'field', id: 'f-' + id },
      el('label', { for: id }, label, opts.optional ? el('span', { class: 'opt', text: ' (اختیاری)' }) : null),
      input,
      opts.help ? el('span', { class: 'help', text: opts.help }) : null,
      el('span', { class: 'err', id: 'e-' + id, role: 'alert' }));
  }
  function textInput(id, attrs) {
    var a = { id: id, name: id, type: 'text' };
    for (var k in attrs) a[k] = attrs[k];
    var i = el('input', a);
    if (draft && draft[id] != null) i.value = draft[id];
    return i;
  }

  function buildForm() {
    var form = el('form', { novalidate: true, class: 'group', style: 'gap:26px' });
    form.appendChild(el('div', { class: 'steps' }, el('div', { class: 'on' }, el('span'), '۱. اطلاعات'), el('div', null, el('span'), '۲. تأیید')));
    var summary = el('div', { id: 'summary', class: 'alert', role: 'alert', tabindex: '-1', hidden: true });
    form.appendChild(summary);

    // نوع ثبت‌نام
    var types = el('div', { class: 'group', id: 'f-type' }, el('h2', { text: 'نوع حضور' }));
    var anyOpen = C.types.filter(function (t) { return !t.closed; });
    C.types.forEach(function (t) {
      var checked = draft ? draft.type === t.code : (anyOpen.length === 1 && anyOpen[0].code === t.code);
      var inp = el('input', { type: 'radio', name: 'type', value: t.code, disabled: t.closed, checked: checked && !t.closed });
      types.appendChild(el('label', { class: 'choice' + (t.closed ? ' closed' : '') }, inp,
        el('span', { class: 'body' }, el('span', { class: 't' }, t.name, t.closed ? el('span', { class: 'pill', text: 'بسته شد' }) : null),
          t.description ? el('span', { class: 'd', text: t.description }) : null),
        el('span', { class: 'p', text: money(t.price) })));
    });
    types.appendChild(el('span', { class: 'err', id: 'e-type', role: 'alert' }));
    form.appendChild(types);

    // مشخصات
    var me = el('div', { class: 'group' }, el('h2', { text: 'مشخصات شما' }));
    me.appendChild(field('first_name', 'نام', textInput('first_name', { autocomplete: 'given-name' })));
    me.appendChild(field('last_name', 'نام خانوادگی', textInput('last_name', { autocomplete: 'family-name' }), { help: 'همان‌طور که روی کارت ورود چاپ شود.' }));
    me.appendChild(field('mobile', 'شماره موبایل', textInput('mobile', { type: 'tel', inputmode: 'tel', autocomplete: 'tel', dir: 'ltr', class: 'ltr', placeholder: '09xx xxx xxxx' })));
    if (C.fields.email !== 'hidden') me.appendChild(field('email', 'ایمیل', textInput('email', { type: 'email', inputmode: 'email', autocomplete: 'email', dir: 'ltr', class: 'ltr', placeholder: 'name@example.com' }), { optional: C.fields.email === 'optional' }));
    if (C.fields.organization !== 'hidden') me.appendChild(field('organization', 'دانشگاه یا سازمان', textInput('organization', { autocomplete: 'organization' }), { optional: C.fields.organization === 'optional' }));
    form.appendChild(me);

    // فیلدهای دلخواه
    var custom = el('div', { class: 'group', id: 'custom' });
    form.appendChild(custom);
    // گزینه‌های اضافه
    var addons = el('div', { class: 'group', id: 'addons' });
    form.appendChild(addons);

    form.appendChild(el('div', { class: 'hp', 'aria-hidden': 'true' }, el('label', { for: 'website', text: 'وب‌سایت' }), el('input', { id: 'website', name: 'website', tabindex: '-1', autocomplete: 'off' })));

    var total = el('div', { class: 'total', id: 'total' });
    form.appendChild(total);
    var btn = el('button', { type: 'submit', class: 'btn', id: 'submit' }, 'تأیید و ثبت‌نام');
    form.appendChild(btn);
    if (C.contact) form.appendChild(el('p', { class: 'track', style: 'margin:0' }, 'پرسشی دارید؟ دبیرخانه: ', el('span', { class: 'ltr', dir: 'ltr', text: C.contact })));

    function currentType() {
      var r = form.querySelector('input[name=type]:checked');
      return r ? r.value : '';
    }
    function applies(item, type) { return !item.types || !item.types.length || item.types.indexOf(type) >= 0; }

    function renderDynamic() {
      var type = currentType();
      // مقدارهای فعلی پیش از ساختن دوباره نگه داشته می‌شوند
      var keep = collect(form);
      custom.textContent = '';
      var fs = C.custom.filter(function (f) { return applies(f, type); });
      if (fs.length) custom.appendChild(el('h2', { text: 'اطلاعات بیشتر' }));
      fs.forEach(function (f) {
        var id = 'q_' + f.id;
        var prev = (keep.answers && keep.answers[f.id] != null) ? keep.answers[f.id] : (draft && draft.answers ? draft.answers[f.id] : null);
        if (f.kind === 'text') {
          var inp = textInput(id, {});
          if (prev != null) inp.value = prev;
          custom.appendChild(field(id, f.label, inp, { optional: !f.required, help: f.help }));
        } else if (f.kind === 'select') {
          var sel = el('select', { id: id, name: id }, el('option', { value: '', text: 'انتخاب کنید' }));
          f.options.forEach(function (o) {
            sel.appendChild(el('option', { value: o.id, disabled: o.full, selected: prev === o.id, text: o.label + (o.full ? ' (تکمیل)' : '') }));
          });
          custom.appendChild(field(id, f.label, sel, { optional: !f.required, help: f.help }));
        } else {
          var box = el('div', { class: 'group', id: 'f-' + id, style: 'gap:10px' },
            el('div', { style: 'font-weight:800;font-size:14px' }, f.label, f.required ? null : el('span', { class: 'opt', style: 'font-weight:400;color:var(--muted)', text: ' (اختیاری)' })),
            f.help ? el('span', { class: 'help', style: 'font-size:13px;color:var(--muted)', text: f.help }) : null);
          f.options.forEach(function (o) {
            var on = Array.isArray(prev) && prev.indexOf(o.id) >= 0;
            box.appendChild(el('label', { class: 'choice' + (o.full ? ' closed' : '') },
              el('input', { type: 'checkbox', name: id, value: o.id, disabled: o.full, checked: on && !o.full }),
              el('span', { class: 'body' }, el('span', null, o.label, o.full ? el('span', { class: 'pill', text: 'تکمیل' }) : null))));
          });
          box.appendChild(el('span', { class: 'err', id: 'e-' + id, role: 'alert' }));
          custom.appendChild(box);
        }
      });

      addons.textContent = '';
      var as = C.addons.filter(function (a) { return applies(a, type); });
      if (as.length) addons.appendChild(el('h2', { text: 'گزینه‌های اضافه' }));
      as.forEach(function (a) {
        var on = (keep.addons || (draft && draft.addons) || []).indexOf(a.id) >= 0;
        var price = a.price_mode === 'info' ? '' : (a.price_mode === 'onsite' ? money(a.price) + '، در روز اجرا' : money(a.price));
        addons.appendChild(el('label', { class: 'choice' + (a.full ? ' closed' : '') },
          el('input', { type: 'checkbox', name: 'addon', value: a.id, disabled: a.full, checked: on && !a.full }),
          el('span', { class: 'body' }, el('span', { class: 't' }, a.title, a.full ? el('span', { class: 'pill', text: 'تکمیل' }) : null),
            a.description ? el('span', { class: 'd', text: a.description }) : null),
          price ? el('span', { class: 'p', text: price }) : null));
      });
      addons.appendChild(el('span', { class: 'err', id: 'e-addons', role: 'alert' }));
      addons.hidden = !as.length;
      custom.hidden = !fs.length;
      renderTotal();
    }

    function renderTotal() {
      var d = collect(form);
      var online = 0, onsite = 0;
      C.types.forEach(function (t) { if (t.code === d.type) online += t.price; });
      C.addons.forEach(function (a) {
        if (d.addons.indexOf(a.id) < 0 || !applies(a, d.type)) return;
        if (a.price_mode === 'online') online += a.price; else if (a.price_mode === 'onsite') onsite += a.price;
      });
      total.textContent = '';
      total.appendChild(el('div', { class: 'row' }, el('span', { text: 'مبلغ قابل پرداخت' }), el('span', { class: 'sum', text: money(online) })));
      if (onsite > 0) total.appendChild(el('div', { class: 'row' }, el('span', { text: 'تسویه در روز اجرا' }), el('span', { text: money(onsite) })));
      var how = '';
      if (online > 0) {
        how = { gateway: 'پرداخت از درگاه بانکی، بعد از ثبت.', link: 'بعد از ثبت، لینک پرداخت نشان داده می‌شود.', card: 'بعد از ثبت، شماره‌کارت برای واریز نشان داده می‌شود.' }[C.payment.method];
      }
      if (how) total.appendChild(el('span', { style: 'font-size:13px;color:var(--muted)', text: how }));
      btn.textContent = online > 0 ? (C.payment.method === 'gateway' ? 'ثبت و پرداخت' : 'ثبت و ادامه') : 'تأیید و ثبت‌نام';
    }

    form.addEventListener('change', function (e) {
      if (e.target.name === 'type') renderDynamic(); else renderTotal();
      var f = e.target.closest('.field, .group');
      if (f) f.classList.remove('bad');
    });
    form.addEventListener('input', function (e) {
      var f = e.target.closest('.field');
      if (f) f.classList.remove('bad');
    });
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      submit(form, btn, summary);
    });
    renderDynamic();
    return form;
  }

  function collect(form) {
    var get = function (n) { var i = form.querySelector('[name="' + n + '"]'); return i ? i.value.trim() : ''; };
    var t = form.querySelector('input[name=type]:checked');
    var d = {
      type: t ? t.value : '', first_name: get('first_name'), last_name: get('last_name'), mobile: get('mobile'),
      email: get('email'), organization: get('organization'), website: get('website'), answers: {}, addons: []
    };
    C.custom.forEach(function (f) {
      var id = 'q_' + f.id;
      if (f.kind === 'multi') {
        var vals = Array.prototype.map.call(form.querySelectorAll('input[name="' + id + '"]:checked'), function (i) { return i.value; });
        if (form.querySelector('input[name="' + id + '"]')) d.answers[f.id] = vals;
      } else {
        var i = form.querySelector('[name="' + id + '"]');
        if (i) d.answers[f.id] = i.value.trim();
      }
    });
    form.querySelectorAll('input[name=addon]:checked').forEach(function (i) { d.addons.push(i.value); });
    return d;
  }

  function validate(form, d) {
    var e = {};
    if (!d.type) e.type = 'نوع حضور را انتخاب کنید.';
    if (d.first_name.length < 2) e.first_name = 'نام را وارد کنید.';
    if (d.last_name.length < 2) e.last_name = 'نام خانوادگی را وارد کنید.';
    if (!/^09\d{9}$/.test(mobileNorm(d.mobile))) e.mobile = 'شماره موبایل باید ۱۱ رقم باشد و با ۰۹ شروع شود.';
    if (C.fields.email !== 'hidden') {
      if (!d.email && C.fields.email === 'required') e.email = 'ایمیل را وارد کنید.';
      else if (d.email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(latin(d.email))) e.email = 'قالب ایمیل درست نیست.';
    }
    if (C.fields.organization === 'required' && !d.organization) e.organization = 'دانشگاه یا سازمان را وارد کنید.';
    C.custom.forEach(function (f) {
      if (!f.required || !form.querySelector('[name="q_' + f.id + '"]')) return;
      var v = d.answers[f.id];
      if (!v || (Array.isArray(v) && !v.length)) {
        e['f_' + f.id] = f.kind === 'text' ? '«' + f.label + '» را وارد کنید.' : (f.kind === 'select' ? 'یکی از گزینه‌ها را انتخاب کنید.' : 'دست‌کم یک گزینه را انتخاب کنید.');
      }
    });
    return e;
  }

  var labels = { type: 'نوع حضور', first_name: 'نام', last_name: 'نام خانوادگی', mobile: 'شماره موبایل', email: 'ایمیل', organization: 'دانشگاه یا سازمان', addons: 'گزینه‌های اضافه', form: 'فرم' };

  function showErrors(form, summary, errors) {
    form.querySelectorAll('.bad').forEach(function (n) { n.classList.remove('bad'); });
    var keys = Object.keys(errors);
    summary.textContent = '';
    if (!keys.length) { summary.hidden = true; return; }
    var list = el('span', null, el('b', { text: fa(keys.length) + ' مورد نیاز به اصلاح دارد' }));
    keys.forEach(function (k) {
      var id = k.indexOf('f_') === 0 ? 'q_' + k.slice(2) : k;
      var box = document.getElementById('f-' + id) || document.getElementById(id === 'addons' ? 'addons' : 'f-' + id);
      var msg = document.getElementById('e-' + id);
      if (box) box.classList.add('bad');
      if (msg) msg.textContent = errors[k];
      var a = el('a', { href: '#' + id, text: errors[k] });
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        var target = document.getElementById(id) || (box && box.querySelector('input'));
        if (target) target.focus();
      });
      list.appendChild(el('br'));
      list.appendChild(a);
    });
    summary.appendChild(list);
    summary.hidden = false;
    summary.focus();
  }

  function submit(form, btn, summary) {
    var d = collect(form);
    var errors = validate(form, d);
    showErrors(form, summary, errors);
    if (Object.keys(errors).length) return;
    draft = d;
    btn.disabled = true;
    var label = btn.textContent;
    btn.textContent = 'در حال ثبت…';
    var body = Object.assign({}, d, { page: C.page, submit_id: submitId, mobile: mobileNorm(d.mobile), email: latin(d.email) });
    var failed = function (text) {
      // اطلاعات فرم حفظ می‌شود؛ همان submit_id دوباره فرستاده می‌شود تا ثبت تکراری نسازد.
      summary.textContent = '';
      summary.appendChild(el('span', null, el('b', { text: 'ثبت انجام نشد' }),
        text || 'اینترنت قطع است یا سرور در دسترس نیست. اطلاعات شما حفظ شده؛ دوباره «' + label + '» را بزنید.'));
      summary.hidden = false;
      summary.focus();
    };
    var restore = function () {
      if (document.body.contains(btn)) { btn.disabled = false; btn.textContent = label; }
    };
    post('submit', body).then(function (r) {
      restore();
      var j = r.body || {};
      if (r.status === 429) return failed(j.message || 'تلاش زیاد بود. ده دقیقه بعد دوباره امتحان کنید.');
      if (r.status >= 500 || !j.state) return failed('سرور جواب درستی نداد. اطلاعات شما حفظ شده؛ دوباره امتحان کنید.');
      if (j.state === 'invalid') return showErrors(form, summary, j.errors || {});
      if (j.state === 'duplicate') return showDuplicate(j.masked);
      if (j.state === 'closed') return showClosed();
      // ثبت انجام شده؛ از اینجا به بعد خطای نمایش نباید «ثبت انجام نشد» نشان دهد.
      submitId = uuid();
      draft = null;
      setUrl(j.code, j.key);
      j.fresh = true; // بعد از ثبت، رفتن خودکار به درگاه بدون کلیک دوم
      try {
        showResult(j);
      } catch (e) {
        if (window.console) console.error(e);
        show(el('div', { class: 'state' }, icon('ok'), el('h1', { text: 'ثبت شد' }), codeBox(j),
          el('p', { text: 'برای دیدن وضعیت، صفحه را دوباره باز کنید.' })));
      }
    }, function () {
      restore();
      failed();
    });
  }

  // ------------------------------------------------------------ حالت‌ها
  function backButton(text) {
    return el('button', { type: 'button', class: 'btn outline', onclick: function () { setUrl(); show(buildForm()); } }, text || 'بازگشت به فرم');
  }
  function contactLine() {
    return C.contact ? el('p', { style: 'margin:0;font-size:13px;color:var(--muted)' }, 'دبیرخانه: ', el('span', { dir: 'ltr', text: C.contact })) : null;
  }

  function showDuplicate(masked) {
    show(el('div', { class: 'state', role: 'alert' }, icon('card'),
      el('h1', { text: 'با این شماره قبلاً ثبت‌نام شده است' }),
      el('b', { dir: 'ltr', style: 'font-size:18px;color:var(--highlight)', text: masked || '' }),
      el('p', { text: 'ثبت‌نام قبلی شما معتبر است و نیازی به ثبت دوباره نیست. اگر برای نفر دیگری ثبت‌نام می‌کنید، موبایل خود او را وارد کنید.' }),
      el('button', { type: 'button', class: 'btn', onclick: function () { show(buildForm()); var m = document.getElementById('mobile'); if (m) m.focus(); } }, 'ویرایش شماره موبایل'),
      el('button', { type: 'button', class: 'btn outline', onclick: showTrack }, 'پیگیری ثبت‌نام قبلی'),
      contactLine()));
  }

  function showClosed() {
    show(el('div', { class: 'state' }, icon('wait'),
      el('h1', { text: 'ثبت‌نام آنلاین بسته شد' }),
      el('p', { text: 'ظرفیت یا مهلت این ثبت‌نام همین حالا تمام شد. اگر جا باشد، روز رویداد در میز پذیرش ثبت‌نام می‌شوید.' }),
      contactLine()));
  }

  function rows(j) {
    var r = el('div', { class: 'rows' });
    function add(k, v, ltr) { if (v) r.appendChild(el('div', null, el('span', { text: k }), el('span', { dir: ltr ? 'ltr' : null, style: 'font-weight:800;text-align:left', text: v }))); }
    add('نوع حضور', typeName(j.type));
    add('شماره موبایل', j.mobile, true);
    add('گزینه‌ها', (j.addons || []).map(addonTitle).join('، '));
    if (j.amount_online > 0) add('مبلغ', money(j.amount_online));
    if (j.amount_onsite > 0) add('تسویه در روز اجرا', money(j.amount_onsite));
    add('زمان', C.when);
    add('مکان', C.where);
    return r;
  }
  function codeBox(j) {
    return el('div', { class: 'code' }, el('span', { style: 'font-size:13px;color:var(--muted)', text: 'کد ثبت‌نام' }), el('b', { text: j.code }));
  }

  function proofForm(j, method) {
    var need = method === 'card' ? (C.payment.card.require || 'code') : 'any';
    var form = el('form', { class: 'group', novalidate: true, style: 'text-align:right' });
    var summary = el('div', { class: 'alert', role: 'alert', hidden: true });
    form.appendChild(summary);
    if (need !== 'receipt') form.appendChild(field('tracking', 'شماره‌ی پیگیری واریز', el('input', { id: 'tracking', name: 'tracking', type: 'text', inputmode: 'numeric', dir: 'ltr', class: 'ltr' }), { optional: need === 'any' }));
    if (need !== 'code') form.appendChild(field('receipt', 'تصویر رسید (JPG، PNG یا PDF تا ۵ مگابایت)', el('input', { id: 'receipt', name: 'receipt', type: 'file', accept: 'image/jpeg,image/png,application/pdf' }), { optional: need === 'any' }));
    var btn = el('button', { type: 'submit', class: 'btn' }, 'ثبت رسید');
    form.appendChild(btn);
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var fd = new FormData();
      fd.append('page', C.page); fd.append('code', j.code); fd.append('k', j.key);
      var t = form.querySelector('[name=tracking]'); if (t) fd.append('tracking', latin(t.value.trim()));
      var f = form.querySelector('[name=receipt]');
      var errors = {};
      if (f && f.files[0]) {
        if (f.files[0].size > 5 * 1024 * 1024) errors.receipt = 'فایل رسید بزرگ‌تر از ۵ مگابایت است.';
        fd.append('receipt', f.files[0]);
      }
      if ((need === 'code' || need === 'both') && t && !t.value.trim()) errors.tracking = 'شماره‌ی پیگیری واریز را وارد کنید.';
      if ((need === 'receipt' || need === 'both') && f && !f.files[0]) errors.receipt = 'تصویر رسید را انتخاب کنید.';
      if (need === 'any' && t && !t.value.trim() && !(f && f.files[0])) errors.tracking = 'شماره‌ی پیگیری یا تصویر رسید را بدهید.';
      showErrors(form, summary, errors);
      if (Object.keys(errors).length) return;
      btn.disabled = true; btn.textContent = 'در حال ارسال…';
      post('proof', fd).then(function (r) {
        var b = r.body || {};
        if (b.state === 'invalid') return showErrors(form, summary, b.errors || {});
        if (!b.status) throw b;
        showResult(b);
      }).catch(function (b) {
        summary.textContent = '';
        summary.appendChild(el('span', null, el('b', { text: 'ارسال نشد' }), (b && b.message) || 'اینترنت یا سرور در دسترس نیست؛ دوباره امتحان کنید.'));
        summary.hidden = false;
      }).then(function () { btn.disabled = false; btn.textContent = 'ثبت رسید'; });
    });
    return form;
  }

  function copyBtn(text) {
    var b = el('button', { type: 'button', class: 'copy' }, 'کپی');
    b.addEventListener('click', function () {
      var done = function () { b.textContent = 'کپی شد'; setTimeout(function () { b.textContent = 'کپی'; }, 1500); };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
    });
    return b;
  }

  function goPay(j, msgNode) {
    post('pay', { page: C.page, code: j.code, k: j.key }).then(function (r) {
      if (r.body && r.body.url) { location.href = r.body.url; return; }
      throw r.body;
    }).catch(function (b) {
      msgNode.textContent = (b && b.message) || 'رفتن به درگاه ممکن نشد؛ دوباره امتحان کنید.';
      msgNode.parentNode.hidden = false;
    });
  }

  function showResult(j) {
    var s = j.status;
    if (trackLink) trackLink.hidden = true;
    var holdNote = j.hold_until ? 'جای شما تا ' + fa(new Date(j.hold_until).toLocaleString('fa-IR-u-nu-latn', { dateStyle: 'medium', timeStyle: 'short' })) + ' نگه داشته می‌شود.' : '';
    if (s === 'confirmed') {
      show(el('div', { class: 'state', role: 'status' }, icon('ok'),
        el('h1', { text: 'ثبت‌نام شما تأیید شد' }),
        el('p', { text: (j.name ? j.name + ' عزیز، ' : '') + 'منتظر دیدنتان هستیم.' }),
        codeBox(j),
        el('p', { style: 'font-size:13px;color:var(--muted);margin:0', text: 'روز رویداد در میز پذیرش، نام یا همین کد را بگویید.' }),
        rows(j),
        C.success_text ? el('div', { class: 'alert info' }, el('span', { text: C.success_text })) : null,
        j.personal_url ? el('a', { class: 'btn', href: j.personal_url }, 'صفحه‌ی شخصی شما') : null,
        el('div', { class: 'alert info' }, el('span', { text: 'از این صفحه اسکرین‌شات بگیرید.' })),
        backButton('ثبت‌نام نفر دیگر'), contactLine()));
      return;
    }
    if (s === 'pending_payment' && j.pay_method === 'gateway') {
      var errBox = el('div', { class: 'alert', role: 'alert', hidden: !j.pay_message }, el('span', null, el('b', { text: 'پرداخت انجام نشد' }), el('span', { text: j.pay_message || '' })));
      var payBtn = el('button', { type: 'button', class: 'btn' }, 'پرداخت ' + money(j.amount_online));
      payBtn.addEventListener('click', function () { payBtn.disabled = true; payBtn.textContent = 'در حال رفتن به درگاه…'; goPay(j, errBox.querySelector('span span')); });
      show(el('div', { class: 'state' }, icon('card'),
        el('h1', { text: j.pay_message ? 'پرداخت انجام نشد' : 'پرداخت' }),
        errBox, codeBox(j), rows(j), payBtn,
        el('p', { style: 'font-size:13px;color:var(--muted);margin:0', text: holdNote + ' اگر پولی کم شده ولی پرداخت ثبت نشده، تا ۷۲ ساعت به حسابتان برمی‌گردد.' }),
        contactLine()));
      if (!j.pay_message && j.fresh) payBtn.click();
      return;
    }
    if (s === 'pending_payment' && j.pay_method === 'link') {
      show(el('div', { class: 'state' }, icon('card'),
        el('h1', { text: 'پرداخت از لینک' }),
        codeBox(j),
        el('p', { style: 'white-space:pre-line', text: C.payment.link_text || 'مبلغ را از لینک زیر پرداخت کنید و بعد شماره‌ی پیگیری یا رسید را همین‌جا ثبت کنید.' }),
        el('div', { class: 'total' }, el('div', { class: 'row' }, el('span', { text: 'مبلغ' }), el('span', { class: 'sum', text: money(j.amount_online) }))),
        C.payment.link_url ? el('a', { class: 'btn', href: C.payment.link_url, target: '_blank', rel: 'noopener' }, 'رفتن به صفحه‌ی پرداخت') : null,
        el('h2', { text: 'بعد از پرداخت' }), proofForm(j, 'link'),
        el('p', { style: 'font-size:13px;color:var(--muted);margin:0', text: holdNote }), contactLine()));
      return;
    }
    if (s === 'pending_payment' && j.pay_method === 'card') {
      var c = C.payment.card;
      var bank = el('div', { class: 'bank' });
      if (c.number) bank.appendChild(el('div', null, el('span', { style: 'font-size:13px;color:var(--muted)', text: 'شماره کارت' }), el('div', { class: 'num', text: c.number.replace(/(\d{4})(?=\d)/g, '$1 ') }), copyBtn(c.number)));
      if (c.sheba) bank.appendChild(el('div', null, el('span', { style: 'font-size:13px;color:var(--muted)', text: 'شبا' }), el('div', { class: 'num', style: 'font-size:15px', text: c.sheba }), copyBtn(c.sheba)));
      if (c.holder || c.bank) bank.appendChild(el('span', { text: [c.holder, c.bank].filter(Boolean).join('، ') }));
      show(el('div', { class: 'state' }, icon('card'),
        el('h1', { text: 'کارت‌به‌کارت' }),
        codeBox(j),
        el('div', { class: 'total' }, el('div', { class: 'row' }, el('span', { text: 'مبلغ واریز' }), el('span', { class: 'sum', text: money(j.amount_online) }))),
        bank,
        c.text ? el('p', { style: 'white-space:pre-line;text-align:right', text: c.text }) : null,
        c.image_url ? el('img', { src: c.image_url, alt: '', style: 'max-width:100%;border-radius:12px' }) : null,
        el('h2', { text: 'بعد از واریز' }), proofForm(j, 'card'),
        el('p', { style: 'font-size:13px;color:var(--muted);margin:0', text: holdNote }), contactLine()));
      return;
    }
    var texts = {
      pending_review: ['wait', 'رسید شما رسید', 'پس از بررسی دبیرخانه، ثبت‌نام شما قطعی می‌شود. وضعیت را با «پیگیری ثبت‌نام» ببینید.'],
      pending_approval: ['wait', 'ثبت‌نام شما ثبت شد', 'پس از تأیید دبیرخانه قطعی می‌شود. وضعیت را با «پیگیری ثبت‌نام» ببینید.'],
      rejected: ['stop', 'ثبت‌نام تأیید نشد', j.reject_reason || 'برای جزئیات با دبیرخانه تماس بگیرید.'],
      expired: ['stop', 'مهلت پرداخت تمام شد', 'جای نگه‌داشته‌شده آزاد شد. اگر هنوز جا هست، دوباره ثبت‌نام کنید.']
    }[s] || ['wait', j.status_label || s, ''];
    var extra = null;
    if (s === 'expired' && j.pay_method === 'gateway') {
      var eb = el('div', { class: 'alert', role: 'alert', hidden: true }, el('span', null, el('b', { text: 'ممکن نشد' }), el('span')));
      var pb = el('button', { type: 'button', class: 'btn' }, 'پرداخت دوباره');
      pb.addEventListener('click', function () { pb.disabled = true; goPay(j, eb.querySelector('span span')); });
      extra = [eb, pb];
    }
    show(el('div', { class: 'state' }, icon(texts[0]), el('h1', { text: texts[1] }), el('p', { text: texts[2] }), codeBox(j), rows(j), extra,
      s === 'rejected' || s === 'expired' ? backButton('ثبت‌نام دوباره') : null, contactLine()));
  }

  function showTrack() {
    if (trackLink) trackLink.hidden = true;
    var form = el('form', { class: 'group', novalidate: true });
    var summary = el('div', { class: 'alert', role: 'alert', hidden: true });
    form.appendChild(el('h2', { text: 'پیگیری ثبت‌نام' }));
    form.appendChild(summary);
    form.appendChild(field('t_code', 'کد ثبت‌نام', el('input', { id: 't_code', name: 't_code', type: 'text', dir: 'ltr', class: 'ltr', placeholder: 'RY-XXXXXX', autocomplete: 'off' })));
    form.appendChild(field('t_mobile', 'شماره موبایل', el('input', { id: 't_mobile', name: 't_mobile', type: 'tel', dir: 'ltr', class: 'ltr', placeholder: '09xx xxx xxxx' })));
    var btn = el('button', { type: 'submit', class: 'btn' }, 'نمایش وضعیت');
    form.appendChild(btn);
    if (C.open) form.appendChild(backButton());
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var code = latin(form.t_code.value).trim().toUpperCase();
      if (code && code.indexOf('RY-') !== 0) code = 'RY-' + code;
      var errors = {};
      if (!/^RY-[A-Z0-9]{6}$/.test(code)) errors.t_code = 'کد ثبت‌نام را درست وارد کنید (مثل RY-7K2M9P).';
      if (!/^09\d{9}$/.test(mobileNorm(form.t_mobile.value))) errors.t_mobile = 'شماره موبایل باید ۱۱ رقم باشد و با ۰۹ شروع شود.';
      showErrors(form, summary, errors);
      if (Object.keys(errors).length) return;
      btn.disabled = true;
      post('status', { page: C.page, code: code, mobile: mobileNorm(form.t_mobile.value) }).then(function (r) {
        if (r.body && r.body.status) { setUrl(r.body.code, r.body.key); return showResult(r.body); }
        showErrors(form, summary, { form: (r.body && r.body.message) || 'ثبت‌نامی با این کد و موبایل پیدا نشد.' });
      }).catch(function () {
        showErrors(form, summary, { form: 'اینترنت یا سرور در دسترس نیست؛ دوباره امتحان کنید.' });
      }).then(function () { btn.disabled = false; });
    });
    show(form);
  }

  // ------------------------------------------------------------ شروع
  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-go="track"]');
    if (t) { e.preventDefault(); showTrack(); }
  });

  var q = new URLSearchParams(location.search);
  if (q.get('code') && q.get('k')) {
    show(el('p', { text: 'در حال خواندن وضعیت ثبت‌نام…' }));
    post('status', { page: C.page, code: q.get('code'), k: q.get('k') }).then(function (r) {
      if (r.body && r.body.status) {
        // برگشت ناموفق از درگاه: اگر پیام سرور نبود، پیام پیش‌فرض.
        if (q.get('pay') === 'fail' && r.body.status === 'pending_payment' && !r.body.pay_message) r.body.pay_message = 'پرداخت انجام نشد یا لغو شد. اگر پولی کم شده، تا ۷۲ ساعت برمی‌گردد.';
        showResult(r.body);
      } else if (C.open) show(buildForm()); else showTrack();
    }).catch(function () {
      show(el('div', { class: 'alert', role: 'alert' }, el('span', null, el('b', { text: 'وضعیت خوانده نشد' }), 'اینترنت یا سرور در دسترس نیست. صفحه را دوباره باز کنید.')));
    });
  } else if (location.hash === '#track') {
    showTrack();
  } else if (C.open) {
    show(buildForm());
  }

})();
