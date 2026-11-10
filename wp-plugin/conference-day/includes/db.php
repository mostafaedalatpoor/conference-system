<?php
if (!defined('ABSPATH')) {
    exit;
}

/**
 * ساخت یا به‌روزرسانی جدول‌ها با dbDelta.
 * قواعد dbDelta: هر ستون در یک خط، دو فاصله بعد از PRIMARY KEY، و KEY به‌جای INDEX.
 */
function cd_install_tables() {
    global $wpdb;
    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    $c = $wpdb->get_charset_collate();

    $events = cd_table('events');
    $types = cd_table('registration_types');
    $roles = cd_table('roles');
    $meals = cd_table('meals');
    $rules = cd_table('meal_rules');
    $sessions = cd_table('sessions');
    $attendees = cd_table('attendees');
    $cards = cd_table('cards');
    $staff = cd_table('staff');
    $devices = cd_table('devices');
    $log = cd_table('event_log');
    $reg_pages = cd_table('reg_pages');
    $regs = cd_table('registrations');

    $sql = [];

    $sql[] = "CREATE TABLE $events (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  code varchar(64) NOT NULL,
  name varchar(191) NOT NULL,
  start_date date NULL,
  end_date date NULL,
  base_url varchar(255) NOT NULL DEFAULT '',
  base_url_locked tinyint(1) NOT NULL DEFAULT 0,
  config_version int(10) unsigned NOT NULL DEFAULT 1,
  settings longtext NULL,
  card_template longtext NULL,
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL,
  PRIMARY KEY  (id),
  UNIQUE KEY code (code)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $types (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  code varchar(64) NOT NULL,
  name varchar(191) NOT NULL,
  PRIMARY KEY  (id),
  UNIQUE KEY event_code (event_id,code)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $roles (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  code varchar(64) NOT NULL,
  name varchar(191) NOT NULL,
  PRIMARY KEY  (id),
  UNIQUE KEY event_code (event_id,code)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $meals (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  code varchar(64) NOT NULL,
  day date NULL,
  name varchar(191) NOT NULL,
  sort int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY  (id),
  UNIQUE KEY event_code (event_id,code)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $rules (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  meal_id bigint(20) unsigned NOT NULL,
  registration_type_id bigint(20) unsigned NULL,
  role_id bigint(20) unsigned NULL,
  PRIMARY KEY  (id),
  KEY meal_id (meal_id)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $sessions (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  day date NOT NULL,
  start_time time NOT NULL,
  end_time time NULL,
  title varchar(255) NOT NULL,
  hall varchar(191) NOT NULL DEFAULT '',
  kind varchar(32) NOT NULL DEFAULT '',
  sort int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY  (id),
  KEY event_day (event_id,day)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $attendees (
  id char(36) NOT NULL,
  event_id bigint(20) unsigned NOT NULL,
  title varchar(64) NOT NULL DEFAULT '',
  first_name varchar(191) NOT NULL,
  last_name varchar(191) NOT NULL,
  email varchar(191) NOT NULL DEFAULT '',
  mobile varchar(32) NOT NULL DEFAULT '',
  organization varchar(191) NOT NULL DEFAULT '',
  country varchar(64) NOT NULL DEFAULT '',
  registration_type_id bigint(20) unsigned NOT NULL,
  presentation_kind varchar(16) NOT NULL DEFAULT '',
  role_id bigint(20) unsigned NULL,
  source varchar(16) NOT NULL DEFAULT 'import',
  share_contact tinyint(1) NULL,
  website varchar(255) NOT NULL DEFAULT '',
  extra longtext NULL,
  extra_meals varchar(1024) NOT NULL DEFAULT '',
  onsite_due int(11) NOT NULL DEFAULT 0,
  onsite_note varchar(255) NOT NULL DEFAULT '',
  reg_code varchar(16) NOT NULL DEFAULT '',
  search_key varchar(512) NOT NULL DEFAULT '',
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL,
  PRIMARY KEY  (id),
  KEY event_id (event_id),
  KEY mobile (mobile)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $cards (
  token varchar(64) NOT NULL,
  event_id bigint(20) unsigned NOT NULL,
  attendee_id char(36) NULL,
  serial int(11) NOT NULL DEFAULT 0,
  is_reserve tinyint(1) NOT NULL DEFAULT 0,
  created_at datetime NOT NULL,
  PRIMARY KEY  (token),
  KEY event_id (event_id),
  KEY attendee_id (attendee_id)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $staff (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  name varchar(191) NOT NULL,
  pin_hash varchar(255) NOT NULL DEFAULT '',
  can_checkin tinyint(1) NOT NULL DEFAULT 1,
  can_serve tinyint(1) NOT NULL DEFAULT 1,
  is_admin tinyint(1) NOT NULL DEFAULT 0,
  active tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY  (id),
  UNIQUE KEY event_name (event_id,name)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $devices (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  staff_id bigint(20) unsigned NOT NULL,
  label varchar(191) NOT NULL DEFAULT '',
  token_hash char(64) NOT NULL,
  created_at datetime NOT NULL,
  last_sync_at datetime NULL,
  revoked tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY  (id),
  UNIQUE KEY token_hash (token_hash),
  KEY event_id (event_id)
) ENGINE=InnoDB $c;";

    $sql[] = "CREATE TABLE $log (
  seq bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  uuid char(36) NOT NULL,
  event_id bigint(20) unsigned NOT NULL,
  device_id bigint(20) unsigned NULL,
  staff_id bigint(20) unsigned NULL,
  kind varchar(32) NOT NULL,
  card_token varchar(64) NULL,
  attendee_id char(36) NULL,
  meal_id bigint(20) unsigned NULL,
  payload longtext NULL,
  flag varchar(32) NULL,
  device_time datetime NOT NULL,
  received_at datetime NOT NULL,
  PRIMARY KEY  (seq),
  UNIQUE KEY uuid (uuid),
  KEY event_seq (event_id,seq),
  KEY attendee_id (attendee_id),
  KEY card_token (card_token)
) ENGINE=InnoDB $c;";

    // صفحه‌ی ثبت‌نام هر رویداد: یک ردیف، تنظیم‌ها به JSON (cd_sanitize_reg_config).
    $sql[] = "CREATE TABLE $reg_pages (
  event_id bigint(20) unsigned NOT NULL,
  path varchar(191) NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'draft',
  config longtext NOT NULL,
  updated_at datetime NOT NULL,
  PRIMARY KEY  (event_id),
  UNIQUE KEY path (path)
) ENGINE=InnoDB $c;";

    // هر ثبت‌نام از صفحه‌ی عمومی. وضعیت‌ها: cd_reg_statuses().
    $sql[] = "CREATE TABLE $regs (
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  event_id bigint(20) unsigned NOT NULL,
  code varchar(16) NOT NULL,
  submit_id char(36) NOT NULL,
  status varchar(24) NOT NULL,
  type_code varchar(64) NOT NULL,
  first_name varchar(191) NOT NULL DEFAULT '',
  last_name varchar(191) NOT NULL DEFAULT '',
  mobile varchar(32) NOT NULL DEFAULT '',
  email varchar(191) NOT NULL DEFAULT '',
  organization varchar(191) NOT NULL DEFAULT '',
  answers longtext NULL,
  addons longtext NULL,
  amount_online int(11) NOT NULL DEFAULT 0,
  amount_onsite int(11) NOT NULL DEFAULT 0,
  pay_method varchar(16) NOT NULL DEFAULT '',
  pay_authority varchar(191) NOT NULL DEFAULT '',
  pay_ref varchar(191) NOT NULL DEFAULT '',
  pay_tracking varchar(191) NOT NULL DEFAULT '',
  receipt_file varchar(191) NOT NULL DEFAULT '',
  reject_reason varchar(500) NOT NULL DEFAULT '',
  attendee_id char(36) NULL,
  hold_until datetime NULL,
  ip varchar(64) NOT NULL DEFAULT '',
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL,
  PRIMARY KEY  (id),
  UNIQUE KEY code (code),
  UNIQUE KEY submit_id (submit_id),
  KEY event_status (event_id,status),
  KEY mobile (mobile)
) ENGINE=InnoDB $c;";

    foreach ($sql as $s) {
        dbDelta($s);
    }
    update_option('cd_db_version', CD_DB_VERSION, false);
}
