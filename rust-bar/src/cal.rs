//! Dates for the calendar card, and the names Qt's QLocale gives for
//! LC_TIME (its CLDR data): standalone month names, short day names, the
//! first day of the week.

extern "C" {
    fn tzset();
}

/// (year, month 1-12, day) today, local time. CLOCK_REALTIME, as JS's new
/// Date() reads it: time() is the kernel's coarse clock, a tick behind, and
/// just past midnight it still gave yesterday (services::local_now's fix).
pub fn today() -> (i32, u32, u32) {
    unsafe { tzset() };
    let mut now = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_REALTIME, &mut now) };
    let t: libc::time_t = now.tv_sec;
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

/// The LC_TIME locale's name, as Qt's unix system locale reads it (the
/// bar's environment does not change while it runs).
fn lc_time() -> &'static str {
    static NAME: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    NAME.get_or_init(|| {
        for v in ["LC_ALL", "LC_TIME", "LANG"] {
            if let Ok(s) = std::env::var(v) {
                if !s.is_empty() {
                    return s;
                }
            }
        }
        "C".into()
    })
}

fn lang() -> &'static str {
    lc_time().split(['_', '.', '@']).next().unwrap_or("C")
}

/// QLocale::firstDayOfWeek for the LC_TIME locale, as 0 = Sunday. Qt takes
/// it from CLDR's week data by territory; these are the territories Qt
/// 6.12 starts on another day than Monday (asked of Qt itself). C and
/// POSIX start on Monday; a bare language goes by its likely territory.
pub fn first_weekday() -> u32 {
    const SUNDAY: [&str; 56] = [
        "AG", "AS", "BD", "BR", "BS", "BT", "BW", "BZ", "CA", "CO", "DM", "DO", "ET", "GT", "GU", "HK", "HN", "ID", "IL", "IN", "IS", "JM", "JP", "KE", "KH", "KR", "LA", "MH", "MM", "MO", "MT", "MX", "MZ", "NI", "NP", "PA", "PE", "PH", "PK", "PR", "PT", "PY", "SA", "SG", "SV", "TH", "TT", "TW", "UM", "US", "VE", "VI", "WS", "YE", "ZA", "ZW",
    ];
    const SATURDAY: [&str; 14] = ["AF", "BH", "DJ", "DZ", "EG", "IQ", "IR", "JO", "KW", "LY", "OM", "QA", "SD", "SY"];
    let name = lc_time().split(['.', '@']).next().unwrap_or("");
    let territory = match name.rsplit_once('_') {
        Some((_, t)) => t,
        None => match name {
            "en" => "US",
            "ja" => "JP",
            "he" => "IL",
            "ar" => "EG",
            "pt" => "BR",
            "fa" => "IR",
            "ko" => "KR",
            "th" => "TH",
            "hi" => "IN",
            _ => "",
        },
    };
    if SUNDAY.contains(&territory) {
        0
    } else if SATURDAY.contains(&territory) {
        6
    } else if territory == "MV" {
        5
    } else {
        1
    }
}

/// QLocale::standaloneMonthName(month, LongFormat). Russian and Spanish as
/// Qt has them; any other language gets the English (C) names.
pub fn month_name(m: u32) -> String {
    let i = (m as usize).clamp(1, 12) - 1;
    match lang() {
        "ru" => ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"][i].into(),
        "es" => ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"][i].into(),
        _ => ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][i].into(),
    }
}

/// QLocale::dayName(day, ShortFormat), 0 = Sunday.
pub fn day_name_short(d: u32) -> String {
    let i = (d % 7) as usize;
    match lang() {
        "ru" => ["вс", "пн", "вт", "ср", "чт", "пт", "сб"][i].into(),
        "es" => ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"][i].into(),
        _ => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][i].into(),
    }
}

/// The format-context abbreviated month (QLocale "MMM"): CLDR's "сент.".
pub fn month_abbr(m: u32) -> String {
    let i = (m as usize).clamp(1, 12) - 1;
    match lang() {
        "ru" => ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."][i].into(),
        "es" => ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"][i].into(),
        _ => ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][i].into(),
    }
}

/// QLocale "ddd" of a YYYY-MM-DD date.
pub fn day_name_of_iso(day: &str) -> String {
    let mut p = day.split('-').map(|x| x.parse::<i64>().unwrap_or(1));
    let (y, m, d) = (p.next().unwrap_or(1970), p.next().unwrap_or(1), p.next().unwrap_or(1));
    let days = days_from_civil(y as i32, m as u32, d as u32);
    day_name_short(weekday(days))
}
