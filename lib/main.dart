// ignore_for_file: deprecated_member_use
// Grove – focus app onboarding (single file, no assets, no packages needed)
// Copy this into lib/main.dart of a new Flutter project:  flutter create grove
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // flutter pub add url_launcher
import 'package:http/http.dart' as http; // flutter pub add http
import 'package:shared_preferences/shared_preferences.dart'; // flutter pub add shared_preferences

// ════════════════════════ BACKEND (your Node / Express / MongoDB API) ════════════════════════
// Browser / DartPad on the same laptop : http://localhost:5000
// Android emulator                     : http://10.0.2.2:5000
// Real phone on the same Wi-Fi         : http://<laptop-ip>:5000
// After you deploy (live)              : https://your-app.onrender.com
const String kApiBase =  'https://grove-api-qcm.vercel.app';

// Set to true ONLY after Google login is fully set up on the backend (Google Cloud + Vercel env vars).
// While false, the "Continue with Google" buttons are hidden, so nobody sees a broken button.
const bool kShowGoogle = true;

abstract class AuthService {
  /// every method returns an error message, or null when it worked
  Future<String?> signInWithGoogle();
  Future<String?> login(String email, String password);
  Future<String?> register(String name, String email, String password);
}

class ApiAuthService implements AuthService {
  static String? token;
  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static int lastStatus = 0;

  static Future<void> saveToken() async {
    final sp = await SharedPreferences.getInstance();
    if (token == null) {
      await sp.remove('token');
    } else {
      await sp.setString('token', token!);
    }
  }

  /// loads name / coins / unlocked trees of the logged-in user
  static Future<bool> loadMe() async {
    try {
      final r = await http.get(Uri.parse('$kApiBase/api/auth/me'), headers: headers);
      lastStatus = r.statusCode;
      if (r.statusCode != 200) return false;
      final u = (jsonDecode(r.body) as Map<String, dynamic>)['user'] as Map<String, dynamic>;
      AppUser.name = u['name'] as String;
      AppUser.email = u['email'] as String;
      AppUser.coins = (u['coins'] as num).toInt();
      AppUser.unlocked = List<String>.from(u['unlockedTrees'] as List);
      AppUser.selected = (u['selectedTree'] ?? 'teal') as String;
      AppUser.unread = ((u['unread'] ?? 0) as num).toInt();
      AppUser.notifOn = u['notificationsEnabled'] != false;
      return true;
    } catch (_) {
      lastStatus = 0;
      return false;
    }
  }

  /// Google login (website): backend redirects back with ?ticket=...; swap it for a real token
  static Future<String?> exchangeTicket(String ticket) async {
    try {
      final r = await http.post(Uri.parse('$kApiBase/api/auth/exchange'), headers: headers, body: jsonEncode({'ticket': ticket}));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) return (j['message'] ?? 'Google login failed').toString();
      token = j['token'] as String;
      await saveToken();
      await loadMe();
      repo = ApiSessionRepo();
      return null;
    } catch (_) {
      return 'Cannot reach the server.';
    }
  }

  static Future<void> logout() async {
    token = null;
    repo = InMemoryRepo();
    AppUser.name = '';
    AppUser.email = '';
    AppUser.coins = 0;
    AppUser.unlocked = ['teal'];
    AppUser.selected = 'teal';
    AppUser.unread = 0;
    await saveToken();
  }

  @override
  Future<String?> signInWithGoogle() async {
    if (!kIsWeb) return 'Google login works on the website version. Please use email in the mobile app for now.';
    final ok = await launchUrl(Uri.parse('$kApiBase/api/auth/google'), webOnlyWindowName: '_self');
    return ok ? null : 'Could not open Google sign-in.';
  }

  @override
  Future<String?> login(String email, String password) async {
    try {
      final r = await http.post(Uri.parse('$kApiBase/api/auth/login'), headers: headers, body: jsonEncode({'email': email, 'password': password}));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) return (j['message'] ?? 'Login failed').toString();
      token = j['token'] as String;
      await saveToken();
      await loadMe();
      repo = ApiSessionRepo(); // from now on sessions are saved on the server
      return null;
    } catch (_) {
      return 'Cannot reach the server. Is the backend running?';
    }
  }

  @override
  Future<String?> register(String name, String email, String password) async {
    try {
      final r = await http.post(Uri.parse('$kApiBase/api/auth/register'), headers: headers, body: jsonEncode({'name': name, 'email': email, 'password': password}));
      if (r.statusCode != 201) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return (j['message'] ?? 'Registration failed').toString();
      }
      return login(email, password);
    } catch (_) {
      return 'Cannot reach the server. Is the backend running?';
    }
  }
}

AuthService authService = ApiAuthService();
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool logged = false;
  String? notice;
  try {
    final q = Uri.base.queryParameters;
    if (q['ticket'] != null) {
      // we just came back from "Continue with Google"
      final err = await ApiAuthService.exchangeTicket(q['ticket']!);
      logged = err == null;
      notice = err;
    } else if (q['google_error'] != null) {
      notice = 'Google login failed. Please try again.';
    } else {
      final sp = await SharedPreferences.getInstance();
      final t = sp.getString('token');
      if (t != null) {
        ApiAuthService.token = t; // auto-login: reuse the saved token
        logged = await ApiAuthService.loadMe();
        if (logged) {
          repo = ApiSessionRepo();
        } else if (ApiAuthService.lastStatus == 401) {
          ApiAuthService.token = null; // token expired -> forget it
          await ApiAuthService.saveToken();
        }
      }
    }
  } catch (_) {}
  runApp(GroveApp(startHome: logged, notice: notice));
}

const kDark = Color(0xFF00535F);
const _shadow = [Shadow(color: Color(0x40003C3C), blurRadius: 10)];

class GroveApp extends StatelessWidget {
  const GroveApp({super.key, this.startHome = false, this.notice});
  final bool startHome;
  final String? notice;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Grove',
        theme: ThemeData(useMaterial3: false, fontFamily: 'Roboto'),
        home: startHome ? const HomeScreen() : Onboarding(notice: notice),
      );
}

// ═══════════ DATA LAYER – swap InMemoryRepo with your backend (Firebase / API) ═══════════
class Session {
  final DateTime start;
  final int minutes;
  final bool success;
  final int hue;
  Session(this.start, this.minutes, this.success, this.hue);
}

abstract class SessionRepo {
  Future<void> add(Session s);
  Future<List<Session>> all();
}

class InMemoryRepo implements SessionRepo {
  final _l = <Session>[];
  @override
  Future<void> add(Session s) async => _l.add(s); // TODO: save to your backend
  @override
  Future<List<Session>> all() async => List.of(_l); // TODO: load from your backend
}

class ApiSessionRepo implements SessionRepo {
  @override
  Future<void> add(Session s) async {
    final r = await http.post(Uri.parse('$kApiBase/api/sessions'),
        headers: ApiAuthService.headers, body: jsonEncode({'durationMinutes': s.minutes, 'status': s.success ? 'completed' : 'withered', 'treeId': idOfHue(s.hue)}));
    if (r.statusCode != 201) throw Exception('save failed');
  }

  @override
  Future<List<Session>> all() async {
    final r = await http.get(Uri.parse('$kApiBase/api/sessions'), headers: ApiAuthService.headers);
    if (r.statusCode != 200) return [];
    final list = (jsonDecode(r.body)['sessions'] as List).cast<Map<String, dynamic>>();
    // server sends newest first; the UI expects oldest first
    return list.reversed
        .map((m) => Session(DateTime.parse(m['startedAt'] as String).toLocal(), m['durationMinutes'] as int, m['status'] == 'completed',
            hueOf((m['treeId'] ?? 'teal') as String)))
        .toList();
  }
}

SessionRepo repo = InMemoryRepo();

// ═══════════════════════════ HOME (Focus / Forest / Stats) ═══════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0, refresh = 0;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF52A688), Color(0xFF63C9A3), Color(0xFF74E8BD)]),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: IndexedStack(index: tab, children: [
            FocusTab(onDone: () => setState(() => refresh++)),
            ForestTab(key: ValueKey('f$refresh')),
            StatsTab(key: ValueKey('s$refresh')),
            ShopTab(key: ValueKey('h$refresh')),
            ProfileTab(key: ValueKey('p$refresh')),
          ]),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: tab,
            onTap: (i) => setState(() => tab = i),
            backgroundColor: kDark,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white54,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.park), label: 'Focus'),
              BottomNavigationBarItem(icon: Icon(Icons.forest), label: 'Forest'),
              BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
              BottomNavigationBarItem(icon: Icon(Icons.storefront), label: 'Shop'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      );
}

class FocusTab extends StatefulWidget {
  final VoidCallback onDone;
  const FocusTab({super.key, required this.onDone});
  @override
  State<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<FocusTab> with WidgetsBindingObserver {
  int minutes = 25, remaining = 0, hue = 175;
  bool running = false, withered = false;
  double p = 0;
  DateTime? start;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  void startSession() {
    start = DateTime.now();
    hue = AppUser.hue; // tree style chosen in the Shop
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() {
      running = true;
      withered = false;
      p = 0;
      remaining = minutes * 60;
    });
  }

  void _tick() {
    final total = minutes * 60, el = DateTime.now().difference(start!).inSeconds;
    if (el >= total) {
      _finish(true);
    } else {
      setState(() {
        p = el / total;
        remaining = total - el;
      });
    }
  }

  Future<void> _finish(bool ok) async {
    if (!running) return;
    timer?.cancel();
    setState(() {
      running = false;
      withered = !ok;
      if (ok) p = 1;
    });
    try {
      await repo.add(Session(start!, minutes, ok, hue));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save to the server')));
    }
    if (ApiAuthService.token != null) await ApiAuthService.loadMe();
    widget.onDone();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Great! +$minutes coins 🌳' : 'Your tree withered 🥀')));
    }
  }

  // leaving the app while a session runs = the tree withers
  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (running && (st == AppLifecycleState.paused || st.name == 'hidden')) _finish(false);
  }

  @override
  Widget build(BuildContext context) {
    final t = '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}';
    final msg = running
        ? 'Stay focused… leaving the app will wither your tree'
        : withered
            ? 'Your tree withered. Try again!'
            : p >= 1
                ? 'Well done! Your tree is fully grown.'
                : 'Pick a time and plant a seed.';
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 22, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                await ApiAuthService.loadMe();
                if (mounted) setState(() {});
              },
              icon: Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.notifications, color: Colors.white, size: 30),
                if (AppUser.unread > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text(AppUser.unread > 9 ? '9+' : '${AppUser.unread}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ]),
            ),
            Text('🪙 ${AppUser.coins}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, shadows: _shadow)),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 26), child: _Title(msg, size: 20)),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AspectRatio(aspectRatio: 300 / 330, child: CustomPaint(painter: GrowPainter(p, running, withered, hue))),
            ),
          ),
        ),
        if (running) Text(t, style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w300, shadows: _shadow)),
        const SizedBox(height: 10),
        if (!running)
          Wrap(spacing: 8, children: [
            for (final m in const [1, 10, 25, 45, 60])
              ChoiceChip(
                label: Text(m == 1 ? '1 min (test)' : '$m min'),
                selected: minutes == m,
                onSelected: (_) => setState(() => minutes = m),
                selectedColor: kDark,
                backgroundColor: const Color(0x80FFFFFF),
                labelStyle: TextStyle(color: minutes == m ? Colors.white : kDark),
              ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 18),
          child: running
              ? GestureDetector(
                  onTap: () => _finish(false),
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(18)),
                    child: const Text('Give up', style: TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                )
              : _Cta('Plant', startSession),
        ),
      ]),
    );
  }
}

class GrowPainter extends CustomPainter {
  final double p;
  final bool running, withered;
  final int hue;
  GrowPainter(this.p, this.running, this.withered, this.hue);

  void _scaled(Canvas c, double k, VoidCallback f) {
    c.save();
    c.translate(150, 206);
    c.scale(k);
    c.translate(-150, -206);
    f();
    c.restore();
  }

  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _bowl(c);
    if (withered) {
      _withered(c, .3);
      return;
    }
    if (!running && p == 0) {
      _scaled(c, .55, () => _sapling(c));
      return;
    }
    if (p < .2) {
      _scaled(c, .5 + p * 1.5, () => _sapling(c));
      return;
    }
    _scaled(c, .6 + .4 * p, () => _tiered(c, bx: 150, by: 206, tiers: math.max(1, (p * 4).ceil()), sc: 1, hue: hue.toDouble(), lb: .2, flowers: (p * 34).floor(), sprout: p >= 1, roots: p > .5));
  }

  @override
  bool shouldRepaint(_) => true;
}

class MiniPainter extends CustomPainter {
  final Session s;
  MiniPainter(this.s);
  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 300);
    c.drawOval(Rect.fromCenter(center: const Offset(150, 268), width: 190, height: 36), Paint()..color = const Color(0x55003C30));
    if (s.success) {
      final tiers = s.minutes >= 45 ? 4 : (s.minutes >= 25 ? 3 : 2);
      _tiered(c, bx: 150, by: 266, tiers: tiers, sc: .95, hue: s.hue.toDouble(), lb: .2, flowers: 8);
    } else {
      c.save();
      c.translate(0, 60);
      _withered(c, .5);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class ForestTab extends StatelessWidget {
  const ForestTab({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: FutureBuilder<List<Session>>(
          future: repo.all(),
          builder: (ctx, snap) {
            final l = (snap.data ?? <Session>[]).reversed.toList();
            if (l.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(30), child: _Title('Your forest is empty.\nPlant your first tree!', size: 22)));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .8),
              itemCount: l.length,
              itemBuilder: (_, i) {
                final s = l[i];
                return Container(
                  decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    Expanded(child: CustomPaint(painter: MiniPainter(s), size: Size.infinite)),
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s.success ? '${s.minutes} min' : 'withered', style: const TextStyle(color: kDark, fontSize: 12))),
                  ]),
                );
              },
            );
          },
        ),
      );
}

Widget _stat(String label, String value) => Expanded(
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(color: const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Text(value, style: const TextStyle(color: kDark, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: kDark, fontSize: 14)),
        ]),
      ),
    );

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});
  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: FutureBuilder<List<Session>>(
          future: repo.all(),
          builder: (ctx, snap) {
            final l = snap.data ?? <Session>[];
            final ok = l.where((s) => s.success).toList();
            final mins = ok.fold<int>(0, (a, s) => a + s.minutes);
            final now = DateTime.now();
            final today = ok.where((s) => _same(s.start, now)).fold<int>(0, (a, s) => a + s.minutes);
            final days = List.generate(7, (i) {
              final d = now.subtract(Duration(days: 6 - i));
              return MapEntry(d, ok.where((s) => _same(s.start, d)).fold<int>(0, (a, s) => a + s.minutes));
            });
            final mx = math.max(1, days.map((e) => e.value).reduce((a, b) => math.max(a, b)));
            return ListView(padding: const EdgeInsets.all(20), children: [
              const _Title('Your focus stats', size: 24),
              const SizedBox(height: 16),
              Row(children: [_stat('Today', '$today min'), _stat('Total', '$mins min')]),
              Row(children: [_stat('Trees grown', '${ok.length}'), _stat('Withered', '${l.length - ok.length}')]),
              Row(children: [_stat('Coins', '$mins')]),
              const SizedBox(height: 18),
              const _Title('Last 7 days', size: 18),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final e in days)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(width: 18, height: 100 * e.value / mx + 4, decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 4),
                        Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][e.key.weekday - 1], style: const TextStyle(color: kDark)),
                      ]),
                    ),
                ]),
              ),
            ]);
          },
        ),
      );
}

// ═══════════════════════════ APP-WIDE USER STATE + TREE CATALOG ═══════════════════════════
class AppUser {
  static String name = '', email = '', selected = 'teal';
  static int coins = 0;
  static List<String> unlocked = ['teal'];
  static int unread = 0;
  static bool notifOn = true;
  static int get hue => hueOf(selected);
}

class TreeKind {
  final String id, name;
  final int hue, cost;
  const TreeKind(this.id, this.name, this.hue, this.cost);
}

// keep in sync with backend/config/trees.js
const kTrees = [
  TreeKind('teal', 'Teal Pine', 175, 0),
  TreeKind('ocean', 'Ocean Pine', 205, 30),
  TreeKind('moss', 'Moss Pine', 140, 60),
  TreeKind('violet', 'Violet Pine', 265, 100),
  TreeKind('rose', 'Rose Pine', 335, 150),
];
int hueOf(String id) => kTrees.firstWhere((t) => t.id == id, orElse: () => kTrees.first).hue;
String idOfHue(int h) => kTrees.firstWhere((t) => t.hue == h, orElse: () => kTrees.first).id;

Future<String?> shopCall(String path, String treeId) async {
  try {
    final r = await http.post(Uri.parse('$kApiBase/api/shop/$path'), headers: ApiAuthService.headers, body: jsonEncode({'treeId': treeId}));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) return (j['message'] ?? 'Something went wrong').toString();
    AppUser.coins = (j['coins'] as num).toInt();
    AppUser.selected = j['selected'] as String;
    AppUser.unlocked = [
      for (final t in (j['trees'] as List))
        if ((t as Map)['owned'] == true) t['id'] as String
    ];
    return null;
  } catch (_) {
    return 'Cannot reach the server.';
  }
}

class TreePreviewPainter extends CustomPainter {
  final int hue;
  TreePreviewPainter(this.hue);
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    c.drawOval(Rect.fromCenter(center: const Offset(150, 268), width: 190, height: 36), Paint()..color = const Color(0x55003C30));
    _tiered(c, bx: 150, by: 266, tiers: 3, sc: .95, hue: hue.toDouble(), lb: .2, flowers: 6);
  }

  @override
  bool shouldRepaint(_) => false;
}

class ShopTab extends StatefulWidget {
  const ShopTab({super.key});
  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  bool busy = false;

  Future<void> _do(String path, String id) async {
    setState(() => busy = true);
    final err = await shopCall(path, id);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Widget _card(TreeKind t) {
    final owned = AppUser.unlocked.contains(t.id), sel = AppUser.selected == t.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        SizedBox(width: 90, height: 100, child: CustomPaint(painter: TreePreviewPainter(t.hue))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, style: const TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(owned ? 'Unlocked' : '🪙 ${t.cost}', style: const TextStyle(color: kDark)),
          ]),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kDark),
          onPressed: (busy || sel) ? null : () => _do(owned ? 'select' : 'buy', t.id),
          child: Text(sel ? 'Selected' : (owned ? 'Select' : 'Buy')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const _Title('Tree shop', size: 24),
          const SizedBox(height: 6),
          Center(child: Text('🪙 ${AppUser.coins} coins', style: const TextStyle(color: Colors.white, fontSize: 18, shadows: _shadow))),
          const SizedBox(height: 12),
          for (final t in kTrees) _card(t),
        ]),
      );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(children: [
          const SizedBox(height: 40),
          CircleAvatar(
            radius: 46,
            backgroundColor: kDark,
            child: Text(AppUser.name.isEmpty ? '?' : AppUser.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40)),
          ),
          const SizedBox(height: 14),
          _Title(AppUser.name, size: 26, w: FontWeight.w700),
          const SizedBox(height: 4),
          Text(AppUser.email, style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 10),
          Text('🪙 ${AppUser.coins} coins', style: const TextStyle(color: Colors.white, fontSize: 20, shadows: _shadow)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
            child: GestureDetector(
              onTap: () async {
                await ApiAuthService.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Onboarding()), (r) => false);
                }
              },
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(18)),
                child: const Text('Log out', style: TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      );
}

// ═══════════════════════════ REGISTER / LOGIN PAGE ═══════════════════════════
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController(), pass2 = TextEditingController();
  bool register = true, busy = false, hide = true;
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    pass.dispose();
    pass2.dispose();
    super.dispose();
  }

  String? _validate() {
    if (register && name.text.trim().isEmpty) return 'Please enter your name.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) return 'Please enter a valid email address.';
    if (pass.text.length < 8) return 'Password must be at least 8 characters.';
    if (register && pass.text != pass2.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    final v = _validate();
    if (v != null) {
      setState(() => error = v);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final err = register ? await authService.register(name.text.trim(), email.text.trim(), pass.text) : await authService.login(email.text.trim(), pass.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        busy = false;
        error = err;
      });
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool pw = false, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: pw && hide,
          keyboardType: type,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0x99FFFFFF),
            labelText: label,
            labelStyle: const TextStyle(color: kDark),
            prefixIcon: Icon(icon, color: kDark),
            suffixIcon: pw ? IconButton(icon: Icon(hide ? Icons.visibility_off : Icons.visibility, color: kDark), onPressed: () => setState(() => hide = !hide)) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _tab(String t, bool on) => Expanded(
        child: GestureDetector(
          onTap: busy
              ? null
              : () => setState(() {
                    register = on;
                    error = null;
                  }),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: register == on ? kDark : const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(22)),
            child: Text(t, style: TextStyle(color: register == on ? Colors.white : kDark, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF52A688), Color(0xFF63C9A3), Color(0xFF74E8BD)])),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(children: [
                Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white, size: 28))),
                _Title(register ? 'Create your account' : 'Welcome back', size: 28, w: FontWeight.w700),
                const SizedBox(height: 20),
                Row(children: [_tab('Sign up', true), const SizedBox(width: 10), _tab('Log in', false)]),
                const SizedBox(height: 20),
                if (register) _field(name, 'Name', Icons.person_outline),
                _field(email, 'Email', Icons.mail_outline, type: TextInputType.emailAddress),
                _field(pass, 'Password (min 8 characters)', Icons.lock_outline, pw: true),
                if (register) _field(pass2, 'Confirm password', Icons.lock_outline, pw: true),
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8B0000), fontWeight: FontWeight.w600))),
                GestureDetector(
                  onTap: busy ? null : _submit,
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(18)),
                    child: busy
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : Text(register ? 'Create account' : 'Log in', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                  ),
                ),
                if (kShowGoogle) ...[
                const SizedBox(height: 16),
                const Text('or', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: busy
                      ? null
                      : () async {
                          final e = await authService.signInWithGoogle();
                          if (e != null && mounted) setState(() => error = e);
                        },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(18)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ShaderMask(
                        shaderCallback: (r) => const SweepGradient(colors: [Color(0xFFEA4335), Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)]).createShader(r),
                        child: const Text('G', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      const Text('Continue with Google', style: TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
                ],
              ]),
            ),
          ),
        ),
      );
}

// ═══════════════════════════ NOTIFICATIONS ═══════════════════════════
class AppNotification {
  final String id, type, title, body;
  final bool read;
  final DateTime at;
  AppNotification(this.id, this.type, this.title, this.body, this.read, this.at);
}

class NotifApi {
  static Future<List<AppNotification>> list() async {
    final r = await http.get(Uri.parse('$kApiBase/api/notifications'), headers: ApiAuthService.headers);
    if (r.statusCode != 200) return [];
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    AppUser.unread = (j['unread'] as num).toInt();
    return [
      for (final m in (j['notifications'] as List).cast<Map<String, dynamic>>())
        AppNotification(m['_id'] as String, (m['type'] ?? '') as String, (m['title'] ?? '') as String, (m['body'] ?? '') as String, m['read'] == true, DateTime.parse(m['createdAt'] as String).toLocal())
    ];
  }

  static Future<void> readAll() async {
    await http.post(Uri.parse('$kApiBase/api/notifications/read-all'), headers: ApiAuthService.headers);
    AppUser.unread = 0;
  }

  static Future<void> clear() async {
    await http.delete(Uri.parse('$kApiBase/api/notifications'), headers: ApiAuthService.headers);
    AppUser.unread = 0;
  }

  static Future<void> setEnabled(bool on) async {
    await http.patch(Uri.parse('$kApiBase/api/auth/settings'), headers: ApiAuthService.headers, body: jsonEncode({'notificationsEnabled': on}));
    AppUser.notifOn = on;
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await NotifApi.list();
      if (mounted) {
        setState(() {
          items = l;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  String _ago(DateTime d) {
    final s = DateTime.now().difference(d);
    if (s.inMinutes < 1) return 'just now';
    if (s.inMinutes < 60) return '${s.inMinutes} min ago';
    if (s.inHours < 24) return '${s.inHours} h ago';
    return '${s.inDays} d ago';
  }

  Widget _tile(AppNotification n) {
    IconData ic = Icons.park;
    if (n.type == 'withered') ic = Icons.eco;
    if (n.type == 'shop') ic = Icons.shopping_bag;
    if (n.type == 'milestone') ic = Icons.emoji_events;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: n.read ? const Color(0x40FFFFFF) : const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, color: kDark, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: const TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(n.body, style: const TextStyle(color: kDark)),
            const SizedBox(height: 4),
            Text(_ago(n.at), style: const TextStyle(color: kDark, fontSize: 12)),
          ]),
        ),
        if (!n.read) Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF52A688), Color(0xFF63C9A3), Color(0xFF74E8BD)])),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 12, 0),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.chevron_left, color: kDark, size: 34)),
                  const Expanded(child: Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, shadows: _shadow))),
                  TextButton(
                    onPressed: () async {
                      try {
                        await NotifApi.readAll();
                      } catch (_) {}
                      await _load();
                    },
                    child: const Text('Read all', style: TextStyle(color: kDark)),
                  ),
                  IconButton(
                    tooltip: 'Clear all',
                    onPressed: () async {
                      try {
                        await NotifApi.clear();
                      } catch (_) {}
                      await _load();
                    },
                    icon: const Icon(Icons.delete_outline, color: kDark),
                  ),
                ]),
              ),
              SwitchListTile(
                value: AppUser.notifOn,
                activeColor: kDark,
                title: const Text('Notifications', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Updates about your trees and coins', style: TextStyle(color: Colors.white70)),
                onChanged: (v) async {
                  setState(() => AppUser.notifOn = v);
                  try {
                    await NotifApi.setEnabled(v);
                  } catch (_) {}
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: loading
                      ? ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())])
                      : items.isEmpty
                          ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No notifications yet', style: TextStyle(color: Colors.white, fontSize: 18)))])
                          : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) => _tile(items[i])),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ═══════════════════════════ FLOW ═══════════════════════════
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, this.notice});
  final String? notice;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int step = 0;
  bool fwd = true;

  @override
  void initState() {
    super.initState();
    if (widget.notice != null) {
      step = 7; // show the account screen with a message (e.g. Google login failed)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.notice!)));
      });
    }
  }

  void go(int s) => setState(() {
        fwd = s >= step;
        step = s;
      });
  void back() {
    if (step > 0) go(step - 1);
  }

  @override
  Widget build(BuildContext context) {
    final splash = step == 0;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: splash
                ? const [Color(0xFF119C86), Color(0xFF1FC491), Color(0xFF8EF5AE)]
                : const [Color(0xFF52A688), Color(0xFF63C9A3), Color(0xFF74E8BD)],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (w, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(fwd ? .12 : -.12, 0), end: Offset.zero).animate(a),
                child: w,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(step), child: _screen()),
          ),
        ),
      ),
    );
  }

  Widget _page({required int bar, required String title, required Widget art, Widget? bottom}) => Column(children: [
        _Header(bar: bar, onBack: back),
        Padding(padding: const EdgeInsets.fromLTRB(26, 20, 26, 0), child: _Title(title)),
        Expanded(child: Center(child: art)),
        Padding(padding: const EdgeInsets.fromLTRB(26, 0, 26, 28), child: bottom ?? const SizedBox(height: 56)),
      ]);

  Widget _bowl(int kind) => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: BowlTree(kind: kind));

  Widget _screen() {
    switch (step) {
      case 0:
        return _Splash(onStart: () => go(1), onHave: () => go(7));
      case 1:
        return _PlantStep(onBack: back, onNext: () => go(2));
      case 2:
        return _page(bar: 2, title: 'Stay focused and your seedling starts to grow.', art: _bowl(0), bottom: _Cta('Continue', () => go(3)));
      case 3:
        return _page(bar: 3, title: 'If you use your phone, your tree will wither.', art: _bowl(2), bottom: _Cta('I’ll focus', () => go(4)));
      case 4:
        return _page(bar: 4, title: 'Stay focused, and your seedling will become a beautiful tree.', art: _bowl(1), bottom: _Cta('Keep focusing', () => go(5)));
      case 5:
        return _page(
          bar: 5,
          title: 'Each tree adds up, watch it grow to your own Grove.',
          art: _BigArt(ratio: 345 / 300, wf: 1.35, hf: 1.0, child: CustomPaint(painter: BlockPainter())),
          bottom: _Cta('Grow Change', () => go(6)),
        );
      case 6:
        return Column(children: [
          _Header(bar: 6, onBack: back),
          Padding(padding: const EdgeInsets.fromLTRB(26, 20, 26, 0), child: _Title('Every focus session is saved. Build habits, see progress.')),
          const SizedBox(height: 10),
          for (final t in const ['See your focus', 'Track your growth', 'Build your life']) _Check(t),
          Expanded(child: _BigArt(ratio: 330 / 300, wf: 1.3, hf: 1.0, child: const ThreeBlocks())),
          Padding(padding: const EdgeInsets.fromLTRB(26, 0, 26, 28), child: _Cta('Start Now', () => go(7))),
        ]);
      default:
        return _Account(onClose: back);
    }
  }
}

// ═══════════════════════════ SMALL WIDGETS ═══════════════════════════
class _Title extends StatelessWidget {
  final String t;
  final double size;
  final FontWeight w;
  const _Title(this.t, {this.size = 26, this.w = FontWeight.w500});
  @override
  Widget build(BuildContext context) =>
      Text(t, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: size, fontWeight: w, height: 1.3, shadows: _shadow));
}

class _Header extends StatelessWidget {
  final int bar;
  final VoidCallback onBack;
  const _Header({required this.bar, required this.onBack});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 22, 0),
        child: Row(children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left, color: kDark, size: 34)),
          Expanded(
            child: Row(children: [
              for (int i = 0; i < 6; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      height: 7,
                      decoration: BoxDecoration(color: i < bar ? kDark : const Color(0x3800535F), borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );
}

class _Cta extends StatelessWidget {
  final String t;
  final VoidCallback f;
  const _Cta(this.t, this.f);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: f,
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF046A78), Color(0xFF00505C)]),
            boxShadow: const [BoxShadow(color: Color(0x5900464F), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(t, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
          ]),
        ),
      );
}

class _Check extends StatelessWidget {
  final String t;
  const _Check(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 17, color: Color(0xFF1A8DA0)),
          ),
          const SizedBox(width: 12),
          Text(t, style: const TextStyle(color: Colors.white, fontSize: 22, shadows: _shadow)),
        ]),
      );
}

/// Draws big art anchored at the bottom, may bleed past the screen edges.
class _BigArt extends StatelessWidget {
  final double ratio, wf, hf;
  final Widget child;
  const _BigArt({required this.ratio, required this.wf, required this.hf, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, box) {
        double h = box.maxWidth * wf * ratio;
        h = math.min(h, box.maxHeight * hf);
        final w = h / ratio;
        return OverflowBox(
          alignment: Alignment.bottomCenter,
          maxWidth: w,
          maxHeight: h,
          child: SizedBox(
            width: w,
            height: h,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0.0, 0.78, 1.0],
              ).createShader(r),
              child: child,
            ),
          ),
        );
      });
}

/// Keeps the screen from overflowing on short windows (scrolls if needed)
class _Scroll extends StatelessWidget {
  final Widget child;
  const _Scroll({required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, box) => SingleChildScrollView(
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: IntrinsicHeight(child: child)),
        ),
      );
}

// ═══════════════════════════ SPLASH ═══════════════════════════
class _Splash extends StatelessWidget {
  final VoidCallback onStart, onHave;
  const _Splash({required this.onStart, required this.onHave});
  @override
  Widget build(BuildContext context) => _Scroll(child: Column(children: [
        const Spacer(),
        Container(
          width: 130,
          height: 130,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xBFD2FFEB),
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [BoxShadow(color: Color(0x99DCFFF0), blurRadius: 40)],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE4FF7A), Color(0xFFC8F257)]),
            ),
            child: CustomPaint(painter: _IconPainter()),
          ),
        ),
        const SizedBox(height: 44),
        const _Title('Ready to focus?\nLet your forest grow.', size: 30, w: FontWeight.w700),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
          child: Column(children: [
            GestureDetector(
              onTap: onStart,
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(18)),
                child: const Text('Get started', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onHave,
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(18)),
                child: const Text('Already have an account?', style: TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('By continuing, you agree to our Privacy Policy and Terms of Service.',
                textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF064E45), fontSize: 13, height: 1.5)),
          ]),
        ),
      ]));
}

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 100);
    c.drawPath(Path()..moveTo(12, 62)..arcTo(Rect.fromCenter(center: const Offset(50, 62), width: 76, height: 56), math.pi, -math.pi, false)..close(),
        Paint()..color = const Color(0xFF8A4C05));
    c.drawOval(Rect.fromCenter(center: const Offset(50, 62), width: 76, height: 14), Paint()..color = const Color(0xFFA1590A));
    c.drawLine(const Offset(50, 60), const Offset(51, 42), Paint()..color = const Color(0xFF52B030)..strokeWidth = 3..strokeCap = StrokeCap.round);
    _leaf(c, const Offset(51, 46), -.6, 20, 7, const Color(0xFF5CC93C));
    _leaf(c, const Offset(51, 47), -2.55, 18, 6, const Color(0xFF7BD851));
  }

  @override
  bool shouldRepaint(_) => false;
}

// ═══════════════════════════ PLANT STEP (swipe down) ═══════════════════════════
class _PlantStep extends StatefulWidget {
  final VoidCallback onBack, onNext;
  const _PlantStep({required this.onBack, required this.onNext});
  @override
  State<_PlantStep> createState() => _PlantStepState();
}

class _PlantStepState extends State<_PlantStep> with TickerProviderStateMixin {
  late final AnimationController drop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  bool planted = false;

  void plant() {
    if (planted || drop.isAnimating) return;
    drop.forward().then((_) {
      if (mounted) setState(() => planted = true);
    });
  }

  @override
  void dispose() {
    drop.dispose();
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: plant,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 150) plant();
        },
        child: Column(children: [
          _Header(bar: 1, onBack: widget.onBack),
          const Padding(padding: EdgeInsets.fromLTRB(30, 22, 30, 0), child: _Title('Welcome To Grove! Ready to Focus? Plant a seedling!', size: 20, w: FontWeight.w400)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: AspectRatio(
                  aspectRatio: 300 / 370,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([drop, spin]),
                    builder: (_, __) => CustomPaint(painter: PlantPainter(Curves.easeInOutCubic.transform(drop.value), spin.value)),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 28),
            child: SizedBox(
              height: 56,
              child: planted
                  ? _Cta('Continue', widget.onNext)
                  : const Center(child: Text('Swipe down to plant', style: TextStyle(color: Colors.white, fontSize: 19))),
            ),
          ),
        ]),
      );
}

// ═══════════════════════════ BOWL + TREE SCENES ═══════════════════════════
class BowlTree extends StatefulWidget {
  final int kind; // 0 = sapling, 1 = big tree, 2 = withered
  const BowlTree({super.key, required this.kind});
  @override
  State<BowlTree> createState() => _BowlTreeState();
}

class _BowlTreeState extends State<BowlTree> with TickerProviderStateMixin {
  late final AnimationController grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  late final AnimationController loop = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void dispose() {
    grow.dispose();
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 300 / 330,
        child: AnimatedBuilder(
          animation: Listenable.merge([grow, loop]),
          builder: (_, __) => CustomPaint(painter: BowlTreePainter(widget.kind, Curves.easeOutCubic.transform(grow.value), loop.value)),
        ),
      );
}

class BowlTreePainter extends CustomPainter {
  final int kind;
  final double grow, t;
  BowlTreePainter(this.kind, this.grow, this.t);
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _bowl(c);
    if (kind == 2) {
      _withered(c, t);
      return;
    }
    c.save();
    c.translate(150, 206);
    c.scale(math.max(.05, grow));
    c.translate(-150, -206);
    if (kind == 0) {
      _sapling(c);
    } else {
      _tiered(c, bx: 150, by: 206, tiers: 4, sc: 1, hue: 175, lb: .2, flowers: 34, sprout: true, roots: true);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_) => true;
}

class PlantPainter extends CustomPainter {
  final double drop, t;
  PlantPainter(this.drop, this.t);
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    // bowl (design: top at y=262)
    c.save();
    c.translate(0, 62);
    _bowl(c);
    c.restore();
    c.save();
    c.translate(150, 70 + 166 * drop);
    c.scale(1 - .15 * drop);
    c.translate(-150, -70);
    final g = (1 - ((drop - .7) / .3)).clamp(0.0, 1.0).toDouble();
    if (g > 0) {
      c.drawCircle(const Offset(150, 70), 66, Paint()..shader = RadialGradient(colors: [const Color(0xFFE9FFD0).withOpacity(.75 * g), const Color(0xFFE9FFD0).withOpacity(0)], stops: const [.55, 1.0]).createShader(Rect.fromCircle(center: const Offset(150, 70), radius: 66)));
      c.drawCircle(const Offset(150, 70), 40, Paint()..shader = RadialGradient(colors: [const Color(0xFFFBFFD0).withOpacity(g), const Color(0xFFA9EC8C).withOpacity(g)]).createShader(Rect.fromCircle(center: const Offset(150, 70), radius: 40)));
      const pal = [Color(0xFFE6F2A0), Color(0xFFFBF8D2), Color(0xFFD4EA86)];
      for (int i = 0; i < 9; i++) {
        final a = i * 40 * math.pi / 180 + t * 2 * math.pi, r = 50.0 + (i % 2) * 5;
        _leaf(c, Offset(150 + math.cos(a) * r, 70 + math.sin(a) * r), a + math.pi / 2, 20.0 + (i % 3) * 3, 6, pal[i % 3].withOpacity(g), vein: false);
      }
    }
    c.drawPath(Path()..moveTo(150, 99)..quadraticBezierTo(145, 88, 150, 76), Paint()..color = const Color(0xFF4AAE52)..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
    _leaf(c, const Offset(150, 88), -.6, 32, 11, const Color(0xFF5CC95A));
    _leaf(c, const Offset(150, 88), -math.pi + .6, 32, 11, const Color(0xFF7BD86C));
    c.restore();
    final a = (1 - drop * 3).clamp(0.0, 1.0).toDouble();
    if (a > 0) {
      final b = 4 * math.sin(t * 2 * math.pi * 8);
      c.drawPath(Path()..moveTo(150, 152 + b)..lineTo(150, 188 + b)..moveTo(139, 176 + b)..lineTo(150, 189 + b)..lineTo(161, 176 + b),
          Paint()..color = Colors.white.withOpacity(a)..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

// ═══════════════════════════ MEADOW BLOCK SCREENS ═══════════════════════════
class _It {
  final double y;
  final VoidCallback d;
  _It(this.y, this.d);
}

void _run(List<_It> l) {
  l.sort((a, b) => a.y.compareTo(b.y));
  for (final i in l) {
    i.d();
  }
}

class BlockPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _slab(c, 150, 150, 180, 75, 46);
    _tufts(c, 150, 150, 180, 75, 70);
    _run([
      _It(216, () => _oak(c, 36, 218, 1.1, 12, .42, 21)),
      _It(208, () => _oak(c, 98, 210, 1.0, 215, .74, 22)),
      _It(204, () => _tiered(c, bx: 160, by: 206, tiers: 5, sc: .8, hue: 185, lb: .2, sprout: true)),
      _It(206, () => _orb(c, 243, 176, 1.4)),
      _It(244, () => _strel(c, 62, 246, 1.15)),
      _It(238, () => _bush(c, 128, 238, 1.25, const [Color(0xFFE03B4A), Color(0xFFFFF4D6)], 5)),
      _It(242, () => _mush(c, 205, 244, 1.2)),
      _It(242, () => _monst(c, 258, 242, 1.1)),
      _It(270, () => _bush(c, 100, 270, 1.2, const [Color(0xFF4B6FE0), Color(0xFF8FB0FF), Color(0xFF6A8CFF)], 6)),
      _It(262, () => _daisy(c, 152, 262, 1.1)),
      _It(270, () => _tulips(c, 210, 270, 1.15)),
      _It(292, () => _bush(c, 152, 292, 1.1, const [Color(0xFFFFCF3A), Color(0xFFFFF4D6), Color(0xFFFFB02E)], 7)),
    ]);
  }

  @override
  bool shouldRepaint(_) => false;
}

class ThreeBlocks extends StatefulWidget {
  const ThreeBlocks({super.key});
  @override
  State<ThreeBlocks> createState() => _ThreeBlocksState();
}

class _ThreeBlocksState extends State<ThreeBlocks> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..forward();
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Widget layer(CustomPainter p, double a, double b, Offset from) {
    final v = Curves.easeOutCubic.transform(Interval(a, b).transform(ctl.value));
    return Opacity(
      opacity: v,
      child: FractionalTranslation(translation: Offset(from.dx * (1 - v), from.dy * (1 - v)), child: CustomPaint(painter: p)),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: ctl,
        builder: (_, __) => Stack(fit: StackFit.expand, children: [
          layer(CenterPainter(), 0, .55, const Offset(0, .25)), // centre rises
          layer(LeftPainter(), .2, .8, const Offset(-.6, 0)), // left slides in
          layer(RightPainter(), .3, .9, const Offset(.6, 0)), // right slides in
        ]),
      );
}

class CenterPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _slab(c, 150, 40, 168, 75, 42);
    _tufts(c, 150, 40, 168, 75, 50);
    _run([
      _It(80, () => _tiered(c, bx: 150, by: 80, tiers: 5, sc: 0.68, hue: 195, lb: .18)),
      _It(100, () => _tiered(c, bx: 112, by: 100, tiers: 5, sc: 0.57, hue: 200, lb: .18)),
      _It(118, () => _oak(c, 70, 118, 0.68, 175, .3, 41)),
      _It(98, () => _orb(c, 226, 76, 1.30)),
      _It(104, () => _orb(c, 190, 82, 1.17)),
      _It(118, () => _orb(c, 150, 96, 1.17)),
      _It(126, () => _tiered(c, bx: 232, by: 126, tiers: 5, sc: 0.54, hue: 195, lb: .18)),
      _It(142, () => _tiered(c, bx: 96, by: 142, tiers: 5, sc: 0.54, hue: 200, lb: .18)),
      _It(140, () => _oak(c, 140, 140, 0.74, 175, .3, 42)),
      _It(140, () => _orb(c, 190, 118, 1.17)),
      _It(160, () => _orb(c, 118, 140, 1.17)),
      _It(166, () => _oak(c, 172, 166, 0.68, 175, .3, 43)),
      _It(150, () => _tiered(c, bx: 215, by: 150, tiers: 4, sc: 0.46, hue: 195, lb: .18)),
      _It(124, () => _orb(c, 60, 102, 1.10)),
      _It(180, () => _tiered(c, bx: 150, by: 180, tiers: 4, sc: 0.41, hue: 195, lb: .18)),
    ]);
  }

  @override
  bool shouldRepaint(_) => false;
}

class LeftPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _slab(c, 10, 205, 100, 45, 26);
    _oak(c, -10, 262, 0.68, 345, .56, 31);
    _oak(c, 48, 256, 0.61, 330, .84, 32);
    _bush(c, 22, 284, 1.04, const [Color(0xFFFF6F8E), Color(0xFFFFFFFF)], 3);
  }

  @override
  bool shouldRepaint(_) => false;
}

class RightPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 300);
    _slab(c, 292, 215, 100, 45, 26);
    _oak(c, 262, 268, 0.68, 215, .72, 33);
    _bush(c, 302, 288, 1.04, const [Color(0xFFA9C4FF), Color(0xFFFFFFFF)], 4);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ═══════════════════════════ ACCOUNT SCREEN ═══════════════════════════
class _Account extends StatelessWidget {
  final VoidCallback onClose;
  const _Account({required this.onClose});

  void _home(BuildContext ctx) => Navigator.of(ctx).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));

  void _msg(BuildContext ctx, String m) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _google(BuildContext ctx) async {
    final err = await authService.signInWithGoogle();
    if (!ctx.mounted) return;
    if (err != null) {
      _msg(ctx, err);
      return;
    }
    // success: the browser is being sent to Google, nothing else to do here
  }

  Future<void> _email(BuildContext ctx) async {
    final n = TextEditingController(), e = TextEditingController(), p = TextEditingController();
    bool register = false, busy = false;
    String? error;
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(
        builder: (dc, setS) => AlertDialog(
          title: Text(register ? 'Create account' : 'Log in'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (register) TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: e, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 8 characters)')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error ?? '', style: const TextStyle(color: Colors.red))),
            TextButton(
              onPressed: busy ? null : () => setS(() {
                    register = !register;
                    error = null;
                  }),
              child: Text(register ? 'I already have an account' : 'Create a new account'),
            ),
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dc), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      final err = register ? await authService.register(n.text.trim(), e.text.trim(), p.text) : await authService.login(e.text.trim(), p.text);
                      if (err != null) {
                        setS(() {
                          busy = false;
                          error = err;
                        });
                        return;
                      }
                      if (dc.mounted) Navigator.pop(dc);
                      if (ctx.mounted) _home(ctx);
                    },
              child: Text(busy ? 'Please wait…' : (register ? 'Sign up' : 'Log in')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Scroll(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 28, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Colors.white, size: 30)),
            const Icon(Icons.public, color: Colors.white, size: 32),
          ]),
        ),
        const Spacer(),
        Container(
          width: 148,
          height: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xCCBEFFE1),
            borderRadius: BorderRadius.circular(38),
            boxShadow: const [BoxShadow(color: Color(0x99D2FFEB), blurRadius: 36)],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(27),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF46D000), Color(0xFF9FF20C)]),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white, size: 76),
          ),
        ),
        const SizedBox(height: 40),
        const SizedBox(width: 240, child: _Title('Create an account to track your focus hours', size: 30, w: FontWeight.w700)),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 28),
          child: Column(children: [
            if (kShowGoogle) ...[
            GestureDetector(
              onTap: () => _google(context),
              child: Container(
                height: 60,
                decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ShaderMask(
                    shaderCallback: (r) => const SweepGradient(colors: [Color(0xFFEA4335), Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)]).createShader(r),
                    child: const Text('G', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  const Text('Continue with Google', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ],
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
              child: Container(
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(30)),
                child: const Text('Continue with Email', style: TextStyle(color: kDark, fontSize: 19, fontWeight: FontWeight.w500)),
              ),
            ),
          ]),
        ),
      ]));
}

// ═══════════════════════════ DRAWING HELPERS ═══════════════════════════
double _r(int i) {
  final s = math.sin(i * 127.1 + 311.7) * 43758.5453;
  return s - s.floorToDouble();
}

Color _hsl(double h, double s, double l) => HSLColor.fromAHSL(
        1, ((h % 360) + 360) % 360, s.clamp(0.0, 1.0).toDouble(), l.clamp(0.0, 1.0).toDouble())
    .toColor();

void _leaf(Canvas c, Offset o, double ang, double len, double wid, Color col, {bool vein = true}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.rotate(ang);
  final p = Path()
    ..moveTo(0, 0)
    ..cubicTo(len * .2, -wid, len * .75, -wid * 1.1, len, 0)
    ..cubicTo(len * .75, wid * 1.1, len * .2, wid, 0, 0);
  c.drawPath(p, Paint()..color = col);
  if (vein) {
    c.drawLine(Offset(len * .1, 0), Offset(len * .88, 0), Paint()..color = Colors.white.withOpacity(.28)..strokeWidth = .7);
  }
  c.restore();
}

void _ball(Canvas c, Offset o, double r, Color col) {
  c.drawCircle(o, r, Paint()..color = col);
  c.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.36, -.44),
          radius: .85,
          colors: [Colors.white.withOpacity(.35), Colors.white.withOpacity(0), Colors.black.withOpacity(.3)],
          stops: const [0.0, .55, 1.0],
        ).createShader(Rect.fromCircle(center: o, radius: r)));
}

void _flower(Canvas c, double x, double y, double r, Color col) {
  final p = Paint()..color = col;
  for (int i = 0; i < 5; i++) {
    final a = i * 2 * math.pi / 5;
    c.drawCircle(Offset(x + math.cos(a) * r * 1.05, y + math.sin(a) * r * 1.05), r * .8, p);
  }
  c.drawCircle(Offset(x, y), r * .55, Paint()..color = const Color(0xFFFFE27A));
}

Paint _trunkPaint(double x0, double x1) => Paint()
  ..shader = const LinearGradient(colors: [Color(0xFF3B2410), Color(0xFF7A5230), Color(0xFF2E1C0C)]).createShader(Rect.fromLTRB(x0, 0, x1, 300));

/// Bowl: soil top at y=200, radius 83 (design coordinates 300 wide)
void _bowl(Canvas c) {
  const cx = 150.0, cy = 200.0, rx = 83.0, depth = 66.0;
  c.drawOval(Rect.fromCenter(center: const Offset(cx, cy + depth + 14), width: rx * 1.5, height: 14),
      Paint()..color = const Color(0x55003C30)..maskFilter = MaskFilter.blur(BlurStyle.normal, 6));
  final body = Path()
    ..moveTo(cx - rx, cy)
    ..arcTo(Rect.fromCenter(center: const Offset(cx, cy), width: rx * 2, height: depth * 2), math.pi, -math.pi, false)
    ..close();
  c.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA5620D), Color(0xFF7A4306), Color(0xFF5E3203)])
            .createShader(Rect.fromLTWH(cx - rx, cy, rx * 2, depth)));
  c.drawOval(Rect.fromCenter(center: const Offset(cx, cy), width: rx * 2, height: 36),
      Paint()..shader = const RadialGradient(colors: [Color(0xFFB86A0B), Color(0xFF8A4C05)]).createShader(Rect.fromCircle(center: const Offset(cx, cy - 4), radius: rx)));
  c.drawOval(Rect.fromCenter(center: const Offset(cx, cy + 5), width: rx * .85, height: 10), Paint()..color = const Color(0x665A3205));
}

/// natural tapered roots lying on the soil
void _roots(Canvas c, double bx, double by, int n, double sc) {
  for (int i = 0; i < n; i++) {
    final dir = i.isEven ? -1.0 : 1.0, len = (16 + _r(i + 90) * 18) * sc * 1.5;
    final tip = Offset(bx + dir * len * (1 - i * .08), by + 3 + _r(i + 95) * 6);
    final mid = Offset(bx + dir * len * .45, by - 2 + _r(i + 99) * 3);
    final m = (Path()..moveTo(bx + dir * 2, by - 6)..quadraticBezierTo(mid.dx, mid.dy - 3, tip.dx, tip.dy)).computeMetrics().first;
    const seg = 6;
    for (int k = 0; k < seg; k++) {
      c.drawPath(
          m.extractPath(m.length * k / seg, m.length * (k + 1) / seg),
          Paint()
            ..color = const Color(0xFF5A3A1C)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(.8, (4.2 * sc) * (1 - k / seg * .85)));
    }
  }
}

/// Stage 1: slim trunk, two twigs, only a handful of leaves, tiny flowers
void _sapling(Canvas c) {
  const bx = 150.0, by = 206.0;
  _roots(c, bx, by, 3, .45);
  c.drawPath(
      Path()
        ..moveTo(bx - 3.6, by)
        ..quadraticBezierTo(bx - 2.4, by - 34, bx - 1.4, by - 66)
        ..lineTo(bx + 1.4, by - 66)
        ..quadraticBezierTo(bx + 2.4, by - 34, bx + 3.6, by)
        ..close(),
      _trunkPaint(bx - 4, bx + 4));
  final bp = Paint()..color = const Color(0xFF6B4524)..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round;
  c.drawPath(Path()..moveTo(bx, by - 36)..quadraticBezierTo(bx - 10, by - 44, bx - 18, by - 52), bp);
  c.drawPath(Path()..moveTo(bx, by - 46)..quadraticBezierTo(bx + 10, by - 54, bx + 18, by - 64), bp);
  const cols = [Color(0xFF4F8FE8), Color(0xFF3B76D4), Color(0xFF6BA8F2)];
  const L = [
    [132.0, 154.0, -2.6], [132.0, 154.0, -3.4], [132.0, 154.0, -1.9],
    [168.0, 142.0, -.4], [168.0, 142.0, -1.0], [168.0, 142.0, .3],
    [150.0, 140.0, -1.57], [150.0, 140.0, -2.1], [150.0, 140.0, -1.05],
    [149.0, 170.0, -2.9], [151.0, 162.0, -.25],
  ];
  for (int i = 0; i < L.length; i++) {
    _leaf(c, Offset(L[i][0], L[i][1]), L[i][2], 15, 5.5, cols[i % 3]);
  }
  const fc = [Color(0xFFFF8FB8), Color(0xFFFFFFFF), Color(0xFFFFD84A), Color(0xFFC9A6FF)];
  const fp = [[132.0, 154.0], [168.0, 141.0], [150.0, 139.0], [150.0, 160.0]];
  for (int i = 0; i < 4; i++) {
    _flower(c, fp[i][0], fp[i][1], 2.4, fc[i]);
  }
}

/// Stage 2+: real tree – roots, tapering trunk, branches, and leaf TIERS (steps)
void _tiered(Canvas c,
    {required double bx, required double by, required int tiers, required double sc, required double hue, required double lb, int flowers = 0, bool sprout = false, bool roots = false}) {
  final gap = 30 * sc, st = 26 * sc;
  double w(int i) => (1 - i / tiers * .78) * 50 * sc;
  double ty(int i) => by - gap - i * st - 12 * sc;
  final topY = ty(tiers - 1);
  if (roots) _roots(c, bx, by, 5, 1);
  final t0 = 6.5 * sc, t1 = 2.5 * sc;
  c.drawPath(
      Path()
        ..moveTo(bx - t0 - 5 * sc, by + 1)
        ..quadraticBezierTo(bx - t0, by - 6 * sc, bx - t0 * .7, by - 20 * sc)
        ..lineTo(bx - t1, topY - 8 * sc)
        ..lineTo(bx + t1, topY - 8 * sc)
        ..lineTo(bx + t0 * .7, by - 20 * sc)
        ..quadraticBezierTo(bx + t0, by - 6 * sc, bx + t0 + 5 * sc, by + 1)
        ..close(),
      _trunkPaint(bx - t0 - 6, bx + t0 + 6));
  final bp = Paint()..color = const Color(0xFF5A3A1C)..style = PaintingStyle.stroke..strokeWidth = 3 * sc..strokeCap = StrokeCap.round;
  int n = 0;
  for (int i = 0; i < tiers; i++) {
    final y = ty(i), W = w(i);
    for (final sd in const [-1.0, 1.0]) {
      c.drawPath(Path()..moveTo(bx, y + 4 * sc)..quadraticBezierTo(bx + sd * W * .5, y - 3 * sc, bx + sd * W * .85, y + 3 * sc), bp);
    }
    c.drawOval(Rect.fromCenter(center: Offset(bx, y + 5 * sc), width: W * 2.1, height: 20 * sc), Paint()..color = _hsl(hue, .45, .2));
    final cnt = math.max(4, (W / 4.5).round());
    for (int row = 0; row < 2; row++) {
      for (int k = 0; k <= cnt; k++) {
        n++;
        final u = k / cnt * 2 - 1, rj = _r(n);
        final x = bx + u * W * (row == 1 ? .9 : 1), yy = y + (1 - u * u) * 4 * sc + (row == 1 ? 6 : 0) * sc;
        final ang = math.pi / 2 - u * .55 + (rj - .5) * .25;
        _leaf(c, Offset(x, yy), ang, (20 - i * 1.2) * sc, 7.5 * sc, _hsl(hue + rj * 10, .55 + _r(n + 5) * .15, lb + i / tiers * .24 - u * .07 + rj * .07 + (row == 1 ? -.04 : .03)));
      }
    }
  }
  const fc = [0xFFFF8FB8, 0xFFFFFFFF, 0xFFFFD84A, 0xFFC9A6FF, 0xFFFF7A7A];
  for (int i = 0; i < flowers; i++) {
    final t = (_r(i + 700) * tiers).floor(), u = _r(i + 710) * 1.7 - .85;
    _flower(c, bx + u * w(t) * .95, ty(t) + (1 - u * u) * 4 * sc + 3 * sc + _r(i + 720) * 8 * sc, 2.2 * sc, Color(fc[i % 5]));
  }
  c.drawCircle(Offset(bx, topY - 6 * sc), 22 * sc,
      Paint()..shader = RadialGradient(colors: [const Color(0xF2DFFCFF), const Color(0x00DFFCFF)]).createShader(Rect.fromCircle(center: Offset(bx, topY - 6 * sc), radius: 22 * sc)));
  if (sprout) {
    _leaf(c, Offset(bx, topY - 8 * sc), -1.2, 14 * sc, 5 * sc, const Color(0xFFBFF3FF));
    _leaf(c, Offset(bx, topY - 8 * sc), -1.95, 14 * sc, 5 * sc, const Color(0xFFBFF3FF));
  }
}

void _withered(Canvas c, double t) {
  const bx = 150.0, by = 206.0;
  _roots(c, bx, by, 4, .8);
  c.drawPath(Path()..moveTo(bx - 8, by)..quadraticBezierTo(bx - 4, by - 70, bx, by - 140)..quadraticBezierTo(bx + 4, by - 70, bx + 8, by)..close(), _trunkPaint(bx - 9, bx + 9));
  final bp = Paint()..color = const Color(0xFF5B4222)..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
  for (int i = 0; i < 7; i++) {
    final y = by - 26 - i * 17, sd = i.isEven ? -1.0 : 1.0, l = 36 - i * 4.0;
    bp.strokeWidth = 3.4 - i * .38;
    c.drawPath(Path()..moveTo(bx, y)..quadraticBezierTo(bx + sd * l * .6, y - 8, bx + sd * l, y + 6), bp);
  }
  c.drawOval(Rect.fromCenter(center: const Offset(bx - 34, by + 6), width: 26, height: 7), Paint()..color = const Color(0xFF4D7A74));
  for (int i = 0; i < 3; i++) {
    final ph = (t + i / 3) % 1.0;
    final x = bx + const [-30.0, 38.0, -8.0][i] + ph * 18, y = by - const [100.0, 70.0, 130.0][i] + ph * const [90.0, 60.0, 120.0][i];
    c.save();
    c.translate(x, y);
    c.rotate(ph * 3);
    _leaf(c, Offset.zero, 0, 16, 6, const Color(0xFF5E8C86).withOpacity((1 - ph).clamp(0.0, 1.0).toDouble()));
    c.restore();
  }
}

// ── meadow pieces ──
void _slab(Canvas c, double cx, double cy, double w, double h, double th) {
  final L = Offset(cx - w, cy + h), B = Offset(cx, cy + 2 * h), Q = Offset(cx + w, cy + h);
  c.drawOval(Rect.fromCenter(center: Offset(cx, cy + 2 * h + th + 4), width: w * 1.8, height: h * .56),
      Paint()..color = const Color(0x55003C30)..maskFilter = MaskFilter.blur(BlurStyle.normal, 8));
  Paint grad(List<Color> cols, Rect r) => Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: cols).createShader(r);
  c.drawPath(Path()..moveTo(L.dx, L.dy)..lineTo(B.dx, B.dy)..lineTo(B.dx, B.dy + th)..lineTo(L.dx, L.dy + th)..close(),
      grad(const [Color(0xFF8C6224), Color(0xFF5A3813)], Rect.fromLTWH(L.dx, L.dy, w, th + h)));
  c.drawPath(Path()..moveTo(B.dx, B.dy)..lineTo(Q.dx, Q.dy)..lineTo(Q.dx, Q.dy + th)..lineTo(B.dx, B.dy + th)..close(),
      grad(const [Color(0xFF6E4817), Color(0xFF3F260B)], Rect.fromLTWH(B.dx, Q.dy, w, th + h)));
  for (int i = 0; i < 10; i++) {
    final a = i.isEven ? L : B, b = i.isEven ? B : Q, p = Offset.lerp(a, b, _r(i + 600))!;
    c.drawOval(Rect.fromCenter(center: Offset(p.dx, p.dy + th * (.35 + _r(i + 620) * .5)), width: (5 + _r(i + 640) * 5) * 2, height: (3 + _r(i + 660) * 3) * 2),
        Paint()..color = const Color(0x8CB07A3F));
  }
  c.drawPath(Path()..moveTo(cx, cy)..lineTo(Q.dx, Q.dy)..lineTo(B.dx, B.dy)..lineTo(L.dx, L.dy)..close(),
      Paint()..shader = const RadialGradient(colors: [Color(0xFFBFF060), Color(0xFF6DB93C)]).createShader(Rect.fromCenter(center: Offset(cx, cy + h), width: w * 2, height: h * 2)));
  for (int e = 0; e < 2; e++) {
    final a = e == 0 ? L : B, b = e == 0 ? B : Q, n = math.max(6, (w / 8).round());
    for (int i = 0; i < n; i++) {
      final p1 = Offset.lerp(a, b, i / n)!, p2 = Offset.lerp(a, b, (i + 1) / n)!, m = Offset.lerp(p1, p2, .5)!;
      c.drawPath(Path()..moveTo(p1.dx, p1.dy)..lineTo(m.dx, m.dy + 7)..lineTo(p2.dx, p2.dy)..close(),
          Paint()..color = (i + e).isEven ? const Color(0xFF7EC23C) : const Color(0xFF69B032));
    }
  }
}

void _tufts(Canvas c, double cx, double cy, double w, double h, int N) {
  final p = Paint()..color = const Color(0xFF4D9A2A)..style = PaintingStyle.stroke..strokeWidth = 1.3..strokeCap = StrokeCap.round;
  int n = 0;
  for (int i = 0; i < 500 && n < N; i++) {
    final x = cx - w + _r(i + 500) * 2 * w, y = cy + _r(i + 520) * 2 * h;
    if ((x - cx).abs() / w + (y - (cy + h)).abs() / h > .92) continue;
    n++;
    c.drawPath(Path()..moveTo(x, y)..relativeLineTo(-2, -7)..moveTo(x + 3, y)..relativeLineTo(1, -8)..moveTo(x + 5, y)..relativeLineTo(3, -6), p);
  }
}

void _oak(Canvas c, double x, double y, double s, double h, double l, int sd) {
  c.drawOval(Rect.fromCenter(center: Offset(x + 8 * s, y + 2 * s), width: 68 * s, height: 16 * s), Paint()..color = const Color(0x44003C30));
  c.drawPath(Path()..moveTo(x - 7 * s, y)..quadraticBezierTo(x - 3 * s, y - 14 * s, x - 4 * s, y - 34 * s)..lineTo(x + 4 * s, y - 34 * s)..quadraticBezierTo(x + 3 * s, y - 14 * s, x + 8 * s, y)..close(),
      Paint()..color = const Color(0xFF6B4524));
  final bp = Paint()..color = const Color(0xFF4A2F17)..strokeWidth = 3.2 * s..strokeCap = StrokeCap.round;
  c.drawLine(Offset(x, y - 24 * s), Offset(x - 15 * s, y - 46 * s), bp);
  c.drawLine(Offset(x, y - 28 * s), Offset(x + 16 * s, y - 48 * s), bp);
  final cy0 = y - 58 * s;
  c.drawOval(Rect.fromCenter(center: Offset(x, cy0 + 4 * s), width: 62 * s, height: 50 * s), Paint()..color = _hsl(h, .55, l - .06));
  for (int i = 0; i < 46; i++) {
    final a = _r(sd * 50 + i) * 2 * math.pi, r = math.sqrt(_r(sd * 50 + i + 99)) * 29 * s;
    final px = x + math.cos(a) * r * 1.05, py = cy0 + math.sin(a) * r * .85;
    final lit = (.5 - ((px - x) * .5 + (py - cy0) * .8) / (30 * s) * .5).clamp(0.0, 1.0).toDouble();
    _blob(c, Offset(px, py), (7 + _r(sd * 50 + i + 7) * 6) * s, sd * 100 + i, _hsl(h + _r(sd * 50 + i + 3) * 18 - 9, .52 + _r(sd * 50 + i + 4) * .22, l + lit * .26 + _r(sd * 50 + i + 5) * .06));
  }
}

/// wobbly (organic) leaf-cluster blob, so canopy edges don't look like perfect circles
void _blob(Canvas c, Offset o, double r, int seed, Color col) {
  const n = 10;
  final pts = <Offset>[];
  for (int i = 0; i < n; i++) {
    final a = i * 2 * math.pi / n, k = 1 + (_r(seed + i * 7) - .5) * .4;
    pts.add(Offset(o.dx + math.cos(a) * r * k, o.dy + math.sin(a) * r * k));
  }
  Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final start = mid(pts[n - 1], pts[0]);
  final p = Path()..moveTo(start.dx, start.dy);
  for (int i = 0; i < n; i++) {
    final m = mid(pts[i], pts[(i + 1) % n]);
    p.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
  }
  p.close();
  c.drawPath(p, Paint()..color = col);
  c.drawPath(
      p,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.36, -.44),
          radius: .85,
          colors: [Colors.white.withOpacity(.35), Colors.white.withOpacity(0), Colors.black.withOpacity(.3)],
          stops: const [0.0, .55, 1.0],
        ).createShader(Rect.fromCircle(center: o, radius: r)));
}

void _bush(Canvas c, double x, double y, double s, List<Color> fl, int sd) {
  for (final b in const [[0.0, -14.0, 17.0], [-15.0, -8.0, 13.0], [15.0, -8.0, 13.0], [0.0, -27.0, 13.0]]) {
    _ball(c, Offset(x + b[0] * s, y + b[1] * s), b[2] * s, _hsl(135, .42, .3));
  }
  for (int i = 0; i < 11; i++) {
    _flower(c, x + (_r(i + sd * 3) - .5) * 44 * s, y - 6 * s - _r(i + 23 + sd) * 30 * s, 3.4 * s, fl[i % fl.length]);
  }
}

void _daisy(Canvas c, double x, double y, double s) {
  for (final d in const [-14.0, -3.0, 9.0, 18.0]) {
    final X = x + d * s, Y = y - (36 + (d.abs().toInt() % 2) * 14) * s;
    c.drawPath(Path()..moveTo(x + d * .4 * s, y)..quadraticBezierTo(X, y - 20 * s, X, Y), Paint()..color = const Color(0xFF4AA545)..style = PaintingStyle.stroke..strokeWidth = 2.4 * s);
    _flower(c, X, Y, 4.6 * s, Colors.white);
  }
}

void _strel(Canvas c, double x, double y, double s) {
  _leaf(c, Offset(x, y), -2.1, 28 * s, 8 * s, const Color(0xFF4FAE48));
  _leaf(c, Offset(x, y), -1.0, 28 * s, 8 * s, const Color(0xFF3F9A45));
  const a = [-2.2, -1.9, -1.3, -1.0];
  for (int i = 0; i < 4; i++) {
    final tx = x + (i - 1.5) * 3 * s;
    c.drawLine(Offset(x, y), Offset(tx, y - 30 * s), Paint()..color = const Color(0xFF3F9A45)..strokeWidth = 2 * s);
    _leaf(c, Offset(tx, y - 30 * s), a[i], 26 * s, 5 * s, i.isEven ? const Color(0xFFFF8A1F) : const Color(0xFFFFB02E));
  }
}

void _tulips(Canvas c, double x, double y, double s) {
  const cols = [0xFFFF6A3A, 0xFFFFB02E, 0xFFFF7B4A];
  for (int i = 0; i < 3; i++) {
    final dx = (i - 1) * 13 * s, h = (34 + (i % 2) * 12) * s, X = x + dx;
    c.drawPath(Path()..moveTo(X, y)..quadraticBezierTo(X + 3 * s, y - h / 2, X, y - h), Paint()..color = const Color(0xFF3F9A45)..style = PaintingStyle.stroke..strokeWidth = 2.6 * s);
    c.drawPath(
        Path()
          ..moveTo(X - 6 * s, y - h)
          ..quadraticBezierTo(X - 7 * s, y - h - 12 * s, X, y - h - 15 * s)
          ..quadraticBezierTo(X + 7 * s, y - h - 12 * s, X + 6 * s, y - h)
          ..quadraticBezierTo(X, y - h + 4 * s, X - 6 * s, y - h)
          ..close(),
        Paint()..color = Color(cols[i]));
  }
  _leaf(c, Offset(x, y), -2.0, 26 * s, 6 * s, const Color(0xFF4FAE48));
  _leaf(c, Offset(x, y), -1.1, 26 * s, 6 * s, const Color(0xFF3F9A45));
}

void _mush(Canvas c, double x, double y, double s) {
  c.drawPath(Path()..moveTo(x - 7 * s, y)..quadraticBezierTo(x - 5 * s, y - 18 * s, x - 6 * s, y - 26 * s)..lineTo(x + 6 * s, y - 26 * s)..quadraticBezierTo(x + 5 * s, y - 18 * s, x + 7 * s, y),
      Paint()..color = const Color(0xFFF3DCC0));
  c.drawPath(Path()..moveTo(x - 27 * s, y - 24 * s)..quadraticBezierTo(x, y - 64 * s, x + 27 * s, y - 24 * s)..quadraticBezierTo(x, y - 17 * s, x - 27 * s, y - 24 * s),
      Paint()..color = const Color(0xFF7A3FA0));
  c.drawPath(Path()..moveTo(x - 22 * s, y - 27 * s)..quadraticBezierTo(x, y - 23 * s, x + 22 * s, y - 27 * s),
      Paint()..color = const Color(0xFFD9A441)..style = PaintingStyle.stroke..strokeWidth = 3 * s);
}

void _monst(Canvas c, double x, double y, double s) {
  for (int i = 0; i < 3; i++) {
    _leaf(c, Offset(x, y), -math.pi / 2 + (i - 1) * .75, 50 * s, 22 * s, _hsl(165 + i * 8, .45, .28 + i * .05));
  }
}

void _orb(Canvas c, double x, double y, double s) {
  c.drawOval(Rect.fromCenter(center: Offset(x, y + 24 * s), width: 38 * s, height: 8 * s), Paint()..color = const Color(0x44003C30));
  c.drawCircle(
      Offset(x, y),
      25 * s,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFEAFFD0), Color(0xD97FE0C0), Color(0xE63FB89A)], stops: [0.0, .6, 1.0])
            .createShader(Rect.fromCircle(center: Offset(x, y), radius: 25 * s)));
  c.drawCircle(Offset(x - 7 * s, y - 9 * s), 8 * s, Paint()..color = Colors.white.withOpacity(.3));
  _leaf(c, Offset(x, y + 8 * s), -1.9, 18 * s, 6 * s, const Color(0xFFFFE36A));
  _leaf(c, Offset(x, y + 8 * s), -1.25, 18 * s, 6 * s, const Color(0xFFFFD23F));
}