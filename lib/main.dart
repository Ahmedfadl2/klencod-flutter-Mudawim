import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.load();
  app.refreshPrayersIfNeeded();
  runApp(const MuntahiApp());
}

// ====================== الألوان ======================

const Color kPrimary = Color(0xFF6C5CE7);
const Color kPrimary2 = Color(0xFF8E7CFF);
const Color kMuted = Color(0xFF9A9AB5);

Color cBg() => app.dark ? const Color(0xFF14141F) : const Color(0xFFF4F5FB);
Color cCard() => app.dark ? const Color(0xFF1F1F2E) : Colors.white;
Color cText() => app.dark ? const Color(0xFFEDEBFF) : const Color(0xFF2D2A4A);
Color cSoft() => app.dark ? const Color(0xFF2E2A52) : const Color(0xFFE6E2FF);
Color cField() => app.dark ? const Color(0xFF2A2A3C) : const Color(0xFFF1F2F8);
Color cBorder() => app.dark ? const Color(0xFF3A3A50) : const Color(0xFFD5D6E5);

// ====================== ثوابت ======================

const List<List<String>> kCategories = [
  ['🕌', 'الفجر'],
  ['☀️', 'الظهر'],
  ['🌇', 'العصر'],
  ['🌆', 'المغرب'],
  ['🌙', 'العشاء'],
  ['💪', 'تمرين'],
  ['📚', 'مذاكرة'],
  ['📖', 'قرآن'],
  ['🎧', 'بودكاست'],
  ['📅', 'موعد'],
  ['💊', 'دواء'],
  ['📕', 'قراءة'],
];

const List<String> kRepeats = ['كل يوم', 'مرة واحدة', 'أيام العمل'];
const List<String> kPrayerNames = ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'];
const Map<String, String> kDefaultPrayers = {
  'الفجر': '04:52',
  'الظهر': '11:41',
  'العصر': '14:40',
  'المغرب': '17:00',
  'العشاء': '18:20',
};
const Map<int, String> kMethods = {
  5: 'الهيئة المصرية',
  4: 'أم القرى',
  3: 'رابطة العالم الإسلامي',
  2: 'أمريكا الشمالية (ISNA)',
  1: 'جامعة كراتشي',
};
const List<String> kDays = [
  'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'
];
const List<String> kDaysShort = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
const List<String> kMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];
const List<String> kLevelTitles = [
  'مبتدئ', 'مثابر', 'ملتزم', 'متقدم', 'محترف', 'خبير', 'أسطورة'
];

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayLabel() {
  final n = DateTime.now();
  return '${kDays[n.weekday - 1]}، ${n.day} ${kMonths[n.month - 1]}';
}

String formatTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final p = t.period == DayPeriod.am ? 'ص' : 'م';
  return '$h:$m $p';
}

// ====================== النماذج ======================

class Alarm {
  final int id;
  final int category;
  final String title;
  final TimeOfDay time;
  final String repeat;
  final String created;
  const Alarm({
    required this.id,
    required this.category,
    required this.title,
    required this.time,
    required this.repeat,
    required this.created,
  });

  bool isToday(DateTime now) {
    if (repeat == 'كل يوم') return true;
    if (repeat == 'أيام العمل') return now.weekday != 5 && now.weekday != 6;
    return created == dateKey(now);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'hour': time.hour,
        'minute': time.minute,
        'repeat': repeat,
        'created': created,
      };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        id: j['id'] as int,
        category: j['category'] as int,
        title: j['title'] as String,
        time: TimeOfDay(hour: j['hour'] as int, minute: j['minute'] as int),
        repeat: j['repeat'] as String,
        created: (j['created'] as String?) ?? dateKey(DateTime.now()),
      );
}

class Challenge {
  final int id;
  final String title;
  final int days;
  int progress;
  String lastCheck;
  bool completed;
  Challenge({
    required this.id,
    required this.title,
    required this.days,
    this.progress = 0,
    this.lastCheck = '',
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'days': days,
        'progress': progress,
        'lastCheck': lastCheck,
        'completed': completed,
      };

  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
        id: j['id'] as int,
        title: j['title'] as String,
        days: j['days'] as int,
        progress: (j['progress'] as int?) ?? 0,
        lastCheck: (j['lastCheck'] as String?) ?? '',
        completed: (j['completed'] as bool?) ?? false,
      );
}

class Medal {
  final String emoji;
  final String name;
  final String desc;
  final bool Function(AppState) test;
  Medal(this.emoji, this.name, this.desc, this.test);
}

final List<Medal> kMedals = [
  Medal('🌱', 'البداية', 'أول نقاط', (s) => s.points > 0),
  Medal('🔥', '3 أيام', '3 أيام متواصلة', (s) => s.longestStreak >= 3),
  Medal('🌙', 'أسبوع', '7 أيام متواصلة', (s) => s.longestStreak >= 7),
  Medal('⭐', 'شهر', '30 يوم متواصل', (s) => s.longestStreak >= 30),
  Medal('🎯', '100 نقطة', 'اجمع 100 نقطة', (s) => s.points >= 100),
  Medal('🥈', '500 نقطة', 'اجمع 500 نقطة', (s) => s.points >= 500),
  Medal('🏆', '1000 نقطة', 'اجمع 1000 نقطة', (s) => s.points >= 1000),
  Medal('🛡️', 'محارب', 'أكمل تحديًا', (s) => s.challengesDone >= 1),
  Medal('🕌', 'حافظ الفجر', '7 مرات فجر', (s) => (s.catCount['0'] ?? 0) >= 7),
  Medal('📖', 'قارئ', '7 مرات قرآن أو قراءة',
      (s) => (s.catCount['7'] ?? 0) + (s.catCount['11'] ?? 0) >= 7),
  Medal('🏋️', 'رياضي', '7 مرات تمرين', (s) => (s.catCount['5'] ?? 0) >= 7),
  Medal('📅', 'منظم', '50 إنجازًا', (s) => s.totalDone >= 50),
];

// ====================== حالة التطبيق ======================

final AppState app = AppState();

class AppState extends ChangeNotifier {
  List<Alarm> alarms = [];
  List<Challenge> challenges = [];
  Set<String> done = {};
  Set<String> activeDates = {};
  int points = 0;
  int totalDone = 0;
  int challengesDone = 0;
  Map<String, int> dailyPoints = {};
  Map<String, int> catPoints = {};
  Map<String, int> catCount = {};
  List<Map<String, String>> history = [];
  bool dark = false;
  int method = 5;
  String city = 'Cairo';
  String country = 'Egypt';
  Map<String, String> prayers = Map<String, String>.from(kDefaultPrayers);
  String prayersDate = '';

  // ---- مستويات وسلاسل ----
  int get level => points ~/ 100 + 1;
  int get levelProgress => points % 100;
  String get levelTitle => kLevelTitles[min(level - 1, kLevelTitles.length - 1)];

  int get currentStreak {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!activeDates.contains(dateKey(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var n = 0;
    while (activeDates.contains(dateKey(day))) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  int get longestStreak {
    if (activeDates.isEmpty) return 0;
    final days = activeDates.map((k) => DateTime.parse(k)).toList();
    days.sort();
    var run = 1;
    var best = 1;
    for (var i = 1; i < days.length; i++) {
      final p = days[i - 1];
      if (days[i] == DateTime(p.year, p.month, p.day + 1)) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
    }
    return best;
  }

  int get unlockedCount => kMedals.where((m) => m.test(this)).length;

  Set<String> _unlockedNames() =>
      kMedals.where((m) => m.test(this)).map((m) => m.name).toSet();

  // ---- أدوات داخلية ----
  void _addPoints(int amount, String catKey) {
    points += amount;
    final k = dateKey(DateTime.now());
    dailyPoints[k] = (dailyPoints[k] ?? 0) + amount;
    catPoints[catKey] = (catPoints[catKey] ?? 0) + amount;
    activeDates.add(k);
  }

  void _log(String text) {
    history.insert(0, {'t': text, 'd': dateKey(DateTime.now())});
    if (history.length > 30) history.removeRange(30, history.length);
  }

  void _after(Set<String> medalsBefore, int levelBefore) {
    if (level > levelBefore) _log('⬆️ وصلت إلى المستوى $level');
    for (final m in kMedals) {
      if (m.test(this) && !medalsBefore.contains(m.name)) {
        _log('🏅 شارة جديدة: ${m.name}');
      }
    }
  }

  // ---- التنبيهات ----
  void addAlarm(Alarm a) {
    alarms.add(a);
    alarms.sort((x, y) => (x.time.hour * 60 + x.time.minute)
        .compareTo(y.time.hour * 60 + y.time.minute));
    changed();
  }

  void deleteAlarm(int id) {
    alarms.removeWhere((a) => a.id == id);
    changed();
  }

  bool isDone(Alarm a) => done.contains('${dateKey(DateTime.now())}:${a.id}');

  void completeAlarm(Alarm a) {
    if (isDone(a)) return;
    final mb = _unlockedNames();
    final lb = level;
    done.add('${dateKey(DateTime.now())}:${a.id}');
    totalDone++;
    catCount['${a.category}'] = (catCount['${a.category}'] ?? 0) + 1;
    _addPoints(10, '${a.category}');
    _log('✅ ${a.title} (+10)');
    _after(mb, lb);
    changed();
  }

  // ---- التحديات ----
  void addChallenge(Challenge c) {
    challenges.add(c);
    changed();
  }

  void deleteChallenge(int id) {
    challenges.removeWhere((c) => c.id == id);
    changed();
  }

  bool canCheck(Challenge c) =>
      !c.completed && c.lastCheck != dateKey(DateTime.now());

  void checkChallenge(Challenge c) {
    if (!canCheck(c)) return;
    final mb = _unlockedNames();
    final lb = level;
    c.progress++;
    c.lastCheck = dateKey(DateTime.now());
    _addPoints(20, 'c');
    _log('🎯 ${c.title}: يوم ${c.progress} من ${c.days} (+20)');
    if (c.progress >= c.days) {
      c.completed = true;
      challengesDone++;
      _addPoints(100, 'c');
      _log('🏆 أكملت تحدي ${c.title} (+100)');
    }
    _after(mb, lb);
    changed();
  }

  // ---- مواقيت الصلاة ----
  void refreshPrayersIfNeeded() {
    if (prayersDate.isNotEmpty && prayersDate != dateKey(DateTime.now())) {
      fetchPrayers();
    }
  }

  Future<String> fetchPrayers() async {
    try {
      final uri = Uri.https('api.aladhan.com', '/v1/timingsByCity', {
        'city': city,
        'country': country,
        'method': '$method',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return 'تعذّر الجلب (${res.statusCode})';
      final t = jsonDecode(res.body)['data']['timings'] as Map<String, dynamic>;
      String clean(String k) => (t[k] as String).substring(0, 5);
      prayers = {
        'الفجر': clean('Fajr'),
        'الظهر': clean('Dhuhr'),
        'العصر': clean('Asr'),
        'المغرب': clean('Maghrib'),
        'العشاء': clean('Isha'),
      };
      prayersDate = dateKey(DateTime.now());
      changed();
      return 'تم جلب المواقيت ✅';
    } catch (_) {
      return 'تعذّر الجلب، تأكد من الإنترنت واسم المدينة والدولة';
    }
  }

  // ---- الحفظ ----
  void changed() {
    notifyListeners();
    save();
  }

  Map<String, dynamic> toJson() => {
        'alarms': alarms.map((a) => a.toJson()).toList(),
        'challenges': challenges.map((c) => c.toJson()).toList(),
        'done': done.toList(),
        'activeDates': activeDates.toList(),
        'points': points,
        'totalDone': totalDone,
        'challengesDone': challengesDone,
        'dailyPoints': dailyPoints,
        'catPoints': catPoints,
        'catCount': catCount,
        'history': history,
        'dark': dark,
        'method': method,
        'city': city,
        'country': country,
        'prayers': prayers,
        'prayersDate': prayersDate,
      };

  void apply(Map<String, dynamic> j) {
    alarms = (j['alarms'] as List? ?? [])
        .map((e) => Alarm.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    challenges = (j['challenges'] as List? ?? [])
        .map((e) => Challenge.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    done = Set<String>.from(j['done'] as List? ?? []);
    activeDates = Set<String>.from(j['activeDates'] as List? ?? []);
    points = (j['points'] as int?) ?? 0;
    totalDone = (j['totalDone'] as int?) ?? 0;
    challengesDone = (j['challengesDone'] as int?) ?? 0;
    dailyPoints = Map<String, int>.from(j['dailyPoints'] as Map? ?? {});
    catPoints = Map<String, int>.from(j['catPoints'] as Map? ?? {});
    catCount = Map<String, int>.from(j['catCount'] as Map? ?? {});
    history = (j['history'] as List? ?? [])
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
    dark = (j['dark'] as bool?) ?? false;
    method = (j['method'] as int?) ?? 5;
    city = (j['city'] as String?) ?? 'Cairo';
    country = (j['country'] as String?) ?? 'Egypt';
    prayers = Map<String, String>.from(j['prayers'] as Map? ?? kDefaultPrayers);
    prayersDate = (j['prayersDate'] as String?) ?? '';
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('muntahi_v2');
      if (raw != null) {
        apply(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        return;
      }
      // ترحيل تنبيهات المرحلة السابقة إن وجدت
      final old = prefs.getString('alarms');
      if (old != null) {
        apply({'alarms': jsonDecode(old)});
      }
    } catch (_) {
      apply({});
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('muntahi_v2', jsonEncode(toJson()));
    } catch (_) {}
  }

  void clearAll() {
    final d = dark;
    apply({'dark': d});
    changed();
  }
}

// ====================== التطبيق ======================

class MuntahiApp extends StatelessWidget {
  const MuntahiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مداوم',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: kPrimary,
              brightness: app.dark ? Brightness.dark : Brightness.light,
            ),
            scaffoldBackgroundColor: cBg(),
          ),
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox(),
            );
          },
          home: const MainShell(),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    HomePage(),
    AlarmsPage(),
    ChallengesPage(),
    StatsPage(),
    SettingsPage(),
  ];

  void _openSheet(Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cCard(),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => sheet,
    );
  }

  Widget _chip(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cCard(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: cBg(),
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text(
              'مداوم',
              style: TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            actions: [
              _chip(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text('${app.points}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              )),
              _chip(Text('مستوى ${app.level}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
              const SizedBox(width: 8),
            ],
          ),
          body: IndexedStack(index: _index, children: _pages),
          floatingActionButton: (_index == 1 || _index == 2)
              ? FloatingActionButton(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  onPressed: () => _openSheet(
                    _index == 1
                        ? const AddAlarmSheet()
                        : const AddChallengeSheet(),
                  ),
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            backgroundColor: cCard(),
            indicatorColor: cSoft(),
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: kPrimary),
                label: 'الرئيسية',
              ),
              NavigationDestination(
                icon: Icon(Icons.alarm),
                selectedIcon: Icon(Icons.alarm, color: kPrimary),
                label: 'التنبيهات',
              ),
              NavigationDestination(
                icon: Icon(Icons.track_changes),
                selectedIcon: Icon(Icons.track_changes, color: kPrimary),
                label: 'التحديات',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart),
                selectedIcon: Icon(Icons.bar_chart, color: kPrimary),
                label: 'الإحصائيات',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: kPrimary),
                label: 'الإعدادات',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ====================== مكونات مشتركة ======================

Widget sectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: cText(),
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const EmptyCard({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cCard(),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: kMuted)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class AlarmTile extends StatelessWidget {
  final Alarm alarm;
  final bool home;
  const AlarmTile({super.key, required this.alarm, required this.home});

  @override
  Widget build(BuildContext context) {
    final isDone = app.isDone(alarm);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cCard(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(kCategories[alarm.category][0],
              style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cText(),
                    decoration: (home && isDone)
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatTime(alarm.time)} · ${alarm.repeat}',
                  style: const TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (home)
            IconButton(
              onPressed: isDone
                  ? null
                  : () {
                      app.completeAlarm(alarm);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('+10 نقاط 🎉'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
              icon: Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isDone ? Colors.green : kPrimary,
                size: 30,
              ),
            )
          else
            IconButton(
              onPressed: () => app.deleteAlarm(alarm.id),
              icon: const Icon(Icons.delete_outline, color: kMuted),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

// ====================== الرئيسية ======================

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final now = DateTime.now();
        final today = app.alarms.where((a) => a.isToday(now)).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimary, kPrimary2],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todayLabel(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(value: '${app.points}', label: 'نقطة'),
                      _Stat(value: '${app.currentStreak}', label: 'يوم متواصل'),
                      _Stat(value: '${app.longestStreak}', label: 'أطول سلسلة'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'المستوى ${app.level} · ${app.levelTitle}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: app.levelProgress / 100,
                      minHeight: 8,
                      backgroundColor: const Color(0x33FFFFFF),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            sectionTitle('🕌 مواقيت الصلاة'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cSoft(),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: kPrayerNames.map((n) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Text(n, style: TextStyle(color: cText())),
                        const Spacer(),
                        Text(
                          app.prayers[n] ?? '--:--',
                          style: const TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            sectionTitle('⏰ تنبيهات اليوم'),
            if (today.isEmpty)
              const EmptyCard(
                title: 'لا توجد تنبيهات اليوم',
                subtitle: 'من تبويب التنبيهات اضغط + لإضافة تنبيه',
              )
            else
              Column(
                children:
                    today.map((a) => AlarmTile(alarm: a, home: true)).toList(),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ====================== التنبيهات ======================

class AlarmsPage extends StatelessWidget {
  const AlarmsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (app.alarms.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              EmptyCard(
                title: 'لسه مفيش تنبيهات',
                subtitle: 'اضغط + وإضافة أول تنبيه',
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children:
              app.alarms.map((a) => AlarmTile(alarm: a, home: false)).toList(),
        );
      },
    );
  }
}

Widget sheetLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.bold, color: cText()),
    ),
  );
}

class AddAlarmSheet extends StatefulWidget {
  const AddAlarmSheet({super.key});

  @override
  State<AddAlarmSheet> createState() => _AddAlarmSheetState();
}

class _AddAlarmSheetState extends State<AddAlarmSheet> {
  int _cat = 0;
  final TextEditingController _titleCtrl = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  String _repeat = kRepeats[0];

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  void _fromPrayers() {
    final raw = app.prayers[kCategories[_cat][1]];
    if (raw == null) return;
    final parts = raw.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;
    setState(() => _time = TimeOfDay(hour: h, minute: m));
  }

  void _save() {
    final typed = _titleCtrl.text.trim();
    app.addAlarm(Alarm(
      id: DateTime.now().millisecondsSinceEpoch,
      category: _cat,
      title: typed.isEmpty ? kCategories[_cat][1] : typed,
      time: _time,
      repeat: _repeat,
      created: dateKey(DateTime.now()),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '⏰ تنبيه جديد',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cText(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            sheetLabel('التصنيف'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: List.generate(kCategories.length, (i) {
                final selected = i == _cat;
                return GestureDetector(
                  onTap: () => setState(() => _cat = i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? cSoft() : cField(),
                      border: Border.all(
                        color: selected ? kPrimary : Colors.transparent,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(kCategories[i][0],
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 2),
                        Text(kCategories[i][1],
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }),
            ),
            sheetLabel('العنوان (اختياري)'),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: 'مثال: صلاة الفجر',
                filled: true,
                fillColor: cField(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            sheetLabel('الوقت'),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: cBorder()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(formatTime(_time)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cat <= 4 ? _fromPrayers : null,
                child: const Text('🕌 جلب من مواقيت الصلاة'),
              ),
            ),
            sheetLabel('التكرار'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: cBorder()),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: _repeat,
                isExpanded: true,
                underline: const SizedBox(),
                items: kRepeats
                    .map((r) => DropdownMenuItem<String>(
                          value: r,
                          child: Text(r),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _repeat = v);
                },
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'حفظ التنبيه',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ====================== التحديات ======================

class ChallengesPage extends StatelessWidget {
  const ChallengesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (app.challenges.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              EmptyCard(
                title: 'لسه مفيش تحديات',
                subtitle: 'اضغط + وأنشئ أول تحدي',
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: app.challenges.map((c) => _card(c)).toList(),
        );
      },
    );
  }

  Widget _card(Challenge c) {
    final can = app.canCheck(c);
    final label = c.completed
        ? 'مكتمل 🏆'
        : (can ? 'تم اليوم ✅' : 'أنجزت اليوم 👏');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cCard(),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '🎯 ${c.title}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cText(),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => app.deleteChallenge(c.id),
                icon: const Icon(Icons.delete_outline, color: kMuted),
              ),
            ],
          ),
          Text(
            'يوم ${c.progress} من ${c.days}',
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.progress / c.days,
              minHeight: 8,
              backgroundColor: cField(),
              valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: can ? () => app.checkChallenge(c) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

class AddChallengeSheet extends StatefulWidget {
  const AddChallengeSheet({super.key});

  @override
  State<AddChallengeSheet> createState() => _AddChallengeSheetState();
}

class _AddChallengeSheetState extends State<AddChallengeSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  int _days = 7;
  bool _error = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final t = _titleCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _error = true);
      return;
    }
    app.addChallenge(Challenge(
      id: DateTime.now().millisecondsSinceEpoch,
      title: t,
      days: _days,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '🎯 تحدي جديد',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cText(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            sheetLabel('اسم التحدي'),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: 'مثال: اقرأ 10 صفحات يوميًا',
                errorText: _error ? 'اكتب اسم التحدي' : null,
                filled: true,
                fillColor: cField(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            sheetLabel('المدة'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [7, 14, 21, 30, 60, 90].map((d) {
                return ChoiceChip(
                  label: Text('$d يوم'),
                  selected: _days == d,
                  onSelected: (_) => setState(() => _days = d),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'ابدأ التحدي',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ====================== الإحصائيات ======================

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  String _catName(String k) {
    if (k == 'c') return '🎯 التحديات';
    final i = int.tryParse(k);
    if (i == null || i < 0 || i >= kCategories.length) return k;
    return '${kCategories[i][0]} ${kCategories[i][1]}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final now = DateTime.now();
        final days = List.generate(7, (i) {
          return DateTime(now.year, now.month, now.day - (6 - i));
        });
        final values = days.map((d) => app.dailyPoints[dateKey(d)] ?? 0).toList();
        final maxV = max(values.reduce(max), 1);
        final dist = app.catPoints.entries.where((e) => e.value > 0).toList();
        dist.sort((a, b) => b.value.compareTo(a.value));
        final totalPts = dist.fold<int>(0, (s, e) => s + e.value);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            sectionTitle('📅 آخر 7 أيام'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cCard(),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final v = values[i];
                  final h = v == 0 ? 4.0 : 8.0 + 80.0 * v / maxV;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$v',
                          style: const TextStyle(fontSize: 10, color: kMuted)),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: h,
                        decoration: BoxDecoration(
                          color: v == 0 ? cField() : kPrimary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(kDaysShort[days[i].weekday - 1],
                          style: const TextStyle(fontSize: 10, color: kMuted)),
                    ],
                  );
                }),
              ),
            ),
            sectionTitle('📊 توزيع النقاط حسب النشاط'),
            if (dist.isEmpty)
              const EmptyCard(title: 'لا توجد بيانات بعد', subtitle: '')
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cCard(),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: dist.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(_catName(e.key),
                                  style: TextStyle(color: cText())),
                              const Spacer(),
                              Text('${e.value}',
                                  style: const TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: e.value / totalPts,
                              minHeight: 6,
                              backgroundColor: cField(),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  kPrimary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            sectionTitle('🏅 الشارات (${app.unlockedCount}/${kMedals.length})'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: kMedals.map((m) {
                final on = m.test(app);
                return Opacity(
                  opacity: on ? 1 : 0.4,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: on ? cSoft() : cCard(),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(m.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(m.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: cText())),
                        Text(m.desc,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            sectionTitle('🧾 آخر الإنجازات'),
            if (app.history.isEmpty)
              const EmptyCard(title: 'لسه مفيش إنجازات', subtitle: '')
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: cCard(),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: app.history.take(8).map((h) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(h['t'] ?? '',
                                style: TextStyle(color: cText())),
                          ),
                          Text(h['d'] ?? '',
                              style: const TextStyle(
                                  color: kMuted, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ====================== الإعدادات ======================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _city;
  late final TextEditingController _country;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: app.city);
    _country = TextEditingController(text: app.country);
  }

  @override
  void dispose() {
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _fetch() async {
    final messenger = ScaffoldMessenger.of(context);
    app.city = _city.text.trim().isEmpty ? 'Cairo' : _city.text.trim();
    app.country = _country.text.trim().isEmpty ? 'Egypt' : _country.text.trim();
    setState(() => _loading = true);
    final msg = await app.fetchPrayers();
    if (!mounted) return;
    setState(() => _loading = false);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: jsonEncode(app.toJson())));
    messenger.showSnackBar(const SnackBar(
      content: Text('تم نسخ النسخة الاحتياطية، الصقها في ملاحظة لحفظها'),
    ));
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await Clipboard.getData('text/plain');
      final j = Map<String, dynamic>.from(jsonDecode(data?.text ?? '') as Map);
      app.apply(j);
      app.changed();
      messenger.showSnackBar(const SnackBar(content: Text('تم الاستيراد ✅')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('النص المنسوخ ليس نسخة صحيحة')),
      );
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل البيانات؟'),
        content: const Text('سيتم حذف التنبيهات والتحديات والنقاط نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) app.clearAll();
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cCard(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: cField(),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            sectionTitle('🌙 المظهر'),
            _card([
              Row(
                children: [
                  Text('الوضع الليلي', style: TextStyle(color: cText())),
                  const Spacer(),
                  Switch(
                    value: app.dark,
                    onChanged: (v) {
                      app.dark = v;
                      app.changed();
                    },
                  ),
                ],
              ),
            ]),
            sectionTitle('🔔 الإشعارات'),
            _card([
              Row(
                children: [
                  Text('تجربة إشعار', style: TextStyle(color: cText())),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => _snack(
                        'الإشعارات الفعلية تُضاف في الخطوة التالية'),
                    child: const Text('تجربة'),
                  ),
                ],
              ),
            ]),
            sectionTitle('🕌 مواقيت الصلاة'),
            _card([
              Text('طريقة الحساب', style: TextStyle(color: cText())),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: cBorder()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<int>(
                  value: app.method,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: kMethods.entries
                      .map((e) => DropdownMenuItem<int>(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      app.method = v;
                      app.changed();
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _city,
                decoration: _dec('المدينة (بالإنجليزية) مثل Cairo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _country,
                decoration: _dec('الدولة (بالإنجليزية) مثل Egypt'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _fetch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_loading ? 'جاري الجلب...' : 'جلب المواقيت'),
                ),
              ),
              if (app.prayersDate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'آخر تحديث: ${app.prayersDate}',
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                ),
            ]),
            sectionTitle('☁️ المزامنة السحابية'),
            _card([
              Row(
                children: [
                  Text('ربط Firebase', style: TextStyle(color: cText())),
                  const Spacer(),
                  const OutlinedButton(
                    onPressed: null,
                    child: Text('قريبًا'),
                  ),
                ],
              ),
            ]),
            sectionTitle('💾 البيانات'),
            _card([
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _export,
                      child: const Text('📤 تصدير نسخة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _import,
                      child: const Text('📥 استيراد نسخة'),
                    ),
                  ),
                ],
              ),
            ]),
            sectionTitle('⚠️ منطقة الخطر'),
            _card([
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _clear,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE3E3),
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('🗑️ مسح كل البيانات'),
                ),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
