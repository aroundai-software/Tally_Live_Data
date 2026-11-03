/// Indian FY (Apr–Mar) helpers for report period display.
///
/// Sync stores from_date/to_date. Older snapshots may span past the company's
/// FY end (to_date = sync day). Clamp display to the FY that contains from_date
/// so a 2024–25 company does not show 2026 in the period line.
library;

DateTime indianFyEndFor(DateTime start) {
  final d = DateTime(start.year, start.month, start.day);
  if (d.month >= 4) {
    return DateTime(d.year + 1, 3, 31);
  }
  return DateTime(d.year, 3, 31);
}

/// Cap [to] at the Indian FY end of [from] (never before [from]).
DateTime clampReportToDate(DateTime from, DateTime to) {
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day);
  final fyEnd = indianFyEndFor(fromDay);
  if (toDay.isAfter(fyEnd)) return fyEnd;
  if (toDay.isBefore(fromDay)) return fromDay;
  return toDay;
}

DateTime? clampReportToDateNullable(DateTime? from, DateTime? to) {
  if (from == null || to == null) return to;
  return clampReportToDate(from, to);
}

/// True when [monthStart]/[monthEnd] sit inside the clamped report window.
bool monthWithinReportPeriod({
  required DateTime reportFrom,
  required DateTime reportTo,
  required DateTime monthFrom,
  required DateTime monthTo,
}) {
  final to = clampReportToDate(reportFrom, reportTo);
  final from = DateTime(reportFrom.year, reportFrom.month, reportFrom.day);
  final mf = DateTime(monthFrom.year, monthFrom.month, monthFrom.day);
  final mt = DateTime(monthTo.year, monthTo.month, monthTo.day);
  if (mt.isBefore(from) || mf.isAfter(to)) return false;
  return true;
}

const _monthNames = <String, int>{
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

/// Map a Tally month label (e.g. "April") into the report FY window.
/// Fixes older syncs that attached the wrong calendar year to month summaries.
(DateTime, DateTime)? monthRangeInReportFy(
  String periodLabel,
  DateTime reportFrom,
  DateTime reportTo,
) {
  final monthNum = _monthNames[periodLabel.trim().toLowerCase()];
  if (monthNum == null) return null;
  final from = DateTime(reportFrom.year, reportFrom.month, reportFrom.day);
  final to = clampReportToDate(reportFrom, reportTo);
  // Indian FY: Apr–Dec use start year; Jan–Mar use start year + 1 when FY starts in Apr.
  final year = monthNum >= 4 ? from.year : (from.month >= 4 ? from.year + 1 : from.year);
  final start = DateTime(year, monthNum, 1);
  final end = DateTime(year, monthNum + 1, 0); // last day of month
  if (end.isBefore(from) || start.isAfter(to)) return null;
  final clippedStart = start.isBefore(from) ? from : start;
  final clippedEnd = end.isAfter(to) ? to : end;
  return (clippedStart, clippedEnd);
}
