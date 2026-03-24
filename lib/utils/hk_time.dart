/// Hong Kong wall clock (UTC+8, no DST). Use for timestamps stored as HK local time with +08:00.
class HkTime {
  HkTime._();

  /// Current instant expressed as Hong Kong local components (UTC+8 from [DateTime.now]).
  static DateTime get wallClockNow {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  /// ISO8601 string with explicit +08:00 offset for Postgres `timestamptz` / Supabase.
  static String timestampForDb() {
    final n = wallClockNow;
    String p2(int v) => v.toString().padLeft(2, '0');
    final y = n.year.toString().padLeft(4, '0');
    return '$y-${p2(n.month)}-${p2(n.day)}T${p2(n.hour)}:${p2(n.minute)}:${p2(n.second)}+08:00';
  }

  /// `yyyy-MM-dd` for PostgreSQL **`date`** columns (`task.start_date`, `task.due_date`).
  static String dateOnlyHkMidnightForDb(DateTime d) {
    String p2(int v) => v.toString().padLeft(2, '0');
    final y = d.year.toString().padLeft(4, '0');
    return '$y-${p2(d.month)}-${p2(d.day)}';
  }

  /// Today’s date in Hong Kong (UTC+8) as `yyyy-MM-dd` for PostgreSQL **`date`** columns.
  static String todayDateOnlyForDb() {
    final hk = DateTime.now().toUtc().add(const Duration(hours: 8));
    return dateOnlyHkMidnightForDb(DateTime(hk.year, hk.month, hk.day));
  }

  /// Local [DateTime] for newly created tasks (Hong Kong civil date/time, UTC+8, no DST).
  static DateTime localCreatedAtForTask() {
    final utc = DateTime.now().toUtc();
    final hk = utc.add(const Duration(hours: 8));
    return DateTime(
      hk.year,
      hk.month,
      hk.day,
      hk.hour,
      hk.minute,
      hk.second,
      hk.millisecond,
      hk.microsecond,
    );
  }
}
