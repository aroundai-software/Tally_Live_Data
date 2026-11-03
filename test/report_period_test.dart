import 'package:flutter_test/flutter_test.dart';
import 'package:tallylive/utils/report_period.dart';

void main() {
  test('clamps past FY report end to 31 Mar', () {
    final from = DateTime(2024, 4, 1);
    final to = DateTime(2026, 11, 2);
    expect(clampReportToDate(from, to), DateTime(2025, 3, 31));
  });

  test('keeps open FY end as today', () {
    final from = DateTime(2026, 4, 1);
    final to = DateTime(2026, 11, 2);
    expect(clampReportToDate(from, to), DateTime(2026, 11, 2));
  });

  test('filters months outside report FY', () {
    final reportFrom = DateTime(2024, 4, 1);
    final reportTo = DateTime(2026, 11, 2);
    expect(
      monthWithinReportPeriod(
        reportFrom: reportFrom,
        reportTo: reportTo,
        monthFrom: DateTime(2024, 10, 1),
        monthTo: DateTime(2024, 10, 31),
      ),
      isTrue,
    );
    expect(
      monthWithinReportPeriod(
        reportFrom: reportFrom,
        reportTo: reportTo,
        monthFrom: DateTime(2026, 10, 1),
        monthTo: DateTime(2026, 10, 31),
      ),
      isFalse,
    );
  });

  test('remaps April/January into books_from FY', () {
    final from = DateTime(2024, 4, 1);
    final to = DateTime(2026, 11, 2);
    final april = monthRangeInReportFy('April', from, to);
    expect(april?.$1, DateTime(2024, 4, 1));
    expect(april?.$2, DateTime(2024, 4, 30));
    final jan = monthRangeInReportFy('January', from, to);
    expect(jan?.$1, DateTime(2025, 1, 1));
    expect(jan?.$2, DateTime(2025, 1, 31));
    expect(monthRangeInReportFy('October', from, to)?.$1, DateTime(2024, 10, 1));
  });
}
