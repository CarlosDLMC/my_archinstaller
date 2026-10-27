//! Dates for the calendar card, and the names Qt's QLocale gives for
//! LC_TIME (its CLDR data): standalone month names, short day names, the
//! first day of the week.

extern "C" {
    fn tzset();
}

/// (year, month 1-12, day) today, local time.
pub fn today() -> (i32, u32, u32) {
    unsafe { tzset() };
    let t = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&t, &mut tm) };
    (tm.tm_year + 1900, tm.tm_mon as u32 + 1, tm.tm_mday as u32)
}

fn days_from_civil(y: i32, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y } as i64;
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z: i64) -> (i32, u32, u32) {
    let z = z + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    ((if m <= 2 { y + 1 } else { y }) as i32, m, d)
}

/// 0 = Sunday .. 6 = Saturday (JS getDay()).
fn weekday(days: i64) -> u32 {
    (days + 4).rem_euclid(7) as u32
}

/// The first cell of the month's 6-week grid: startOfWeek(the 1st).
pub fn grid_start(y: i32, m: u32, first_weekday: u32) -> i64 {
    let d1 = days_from_civil(y, m, 1);
    let diff = (weekday(d1) + 7 - first_weekday) % 7;
    d1 - diff as i64
}

pub fn add_days(start: i64, n: i64) -> (i32, u32, u32) {
    civil_from_days(start + n)
}

fn lc_time() -> String {
    for v in ["LC_ALL", "LC_TIME", "LANG"] {
        if let Ok(s) = std::env::var(v) {
            if !s.is_empty() {
                return s;
            }
        }
    }
    "C".into()
}

fn lang() -> String {
    lc_time().split(['_', '.', '@']).next().unwrap_or("C").to_string()
}

/// QLocale::firstDayOfWeek for the LC_TIME locale, as 0 = Sunday.
pub fn first_weekday() -> u32 {
    let l = lc_time();
    // CLDR: Sunday-first territories among the likely ones; Monday elsewhere.
    if l.starts_with("en_US") || l.starts_with("en_CA") || l == "C" || l.starts_with("ja") || l.starts_with("he") || l.starts_with("pt_BR") {
        0
    } else {
        1
    }
}

/// QLocale::standaloneMonthName(month, LongFormat).
pub fn month_name(m: u32) -> String {
    let i = (m as usize).clamp(1, 12) - 1;
    match lang().as_str() {
        "ru" => ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"][i].into(),
        "es" => ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"][i].into(),
        _ => ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][i].into(),
    }
}

/// QLocale::dayName(day, ShortFormat), 0 = Sunday.
pub fn day_name_short(d: u32) -> String {
    let i = (d % 7) as usize;
    match lang().as_str() {
        "ru" => ["вс", "пн", "вт", "ср", "чт", "пт", "сб"][i].into(),
        "es" => ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"][i].into(),
        _ => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][i].into(),
    }
}
