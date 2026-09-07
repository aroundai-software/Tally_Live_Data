void main() { 
  print(DateTime.tryParse('2026-09-03T00:00:00+05:30')); 
  print(DateTime.tryParse('2026-09-03 00:00:00+05:30')); 
  print(DateTime.tryParse('2026-09-03T00:00:00+0530')); 
}
