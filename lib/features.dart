// ignore_for_file: deprecated_member_use
// Grove – extra features
//   • Notifications (bell + screen)      • Friends + leaderboard
//   • Achievements                       • Settings: tags, grace period, app whitelist
//   • "Focus by tag" stats               • Real tree card (Shop)
//   • Android bridge that detects which app is in front (for the whitelist)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

const _fShadow = [Shadow(color: Color(0x40003C3C), blurRadius: 10)];

/// package name of this app (same as applicationId in android/app/build.gradle.kts)
const String kOwnPackage = 'com.example.grove';

/// coins needed to request one real tree (keep in sync with backend/routes/shop.js)
const int kRealTreeCost = 500;

/// apps the user can allow while a focus session is running
const Map<String, String> kPresetApps = {
  'WhatsApp': 'com.whatsapp',
  'Telegram': 'org.telegram.messenger',
  'Spotify': 'com.spotify.music',
  'YouTube Music': 'com.google.android.apps.youtube.music',
  'Google Meet': 'com.google.android.apps.tachyon',
  'Zoom': 'us.zoom.videomeetings',
  'Google Docs': 'com.google.android.apps.docs.editors.docs',
  'Google Keep': 'com.google.android.keep',
  'Calculator': 'com.google.android.calculator',
};

// ═══════════════════════════ SMALL API HELPER ═══════════════════════════
class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Api {
  /// method: GET / POST / PUT / DELETE. Returns the decoded JSON or throws [ApiError].
  static Future<Map<String, dynamic>> call(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$kApiBase$path');
    late http.Response r;
    try {
      if (method == 'POST') {
        r = await http.post(uri, headers: ApiAuthService.headers, body: jsonEncode(body ?? {}));
      } else if (method == 'PUT') {
        r = await http.put(uri, headers: ApiAuthService.headers, body: jsonEncode(body ?? {}));
      } else if (method == 'DELETE') {
        r = await http.delete(uri, headers: ApiAuthService.headers);
      } else {
        r = await http.get(uri, headers: ApiAuthService.headers);
      }
    } catch (_) {
      throw ApiError('Cannot reach the server. Is the backend running?');
    }
    Map<String, dynamic> j = {};
    try {
      if (r.body.isNotEmpty) j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError('The server sent an unexpected answer.');
    }
    if (r.statusCode >= 400) throw ApiError((j['message'] ?? 'Something went wrong').toString());
    return j;
  }
}

// ═══════════════════════════ ANDROID: WHICH APP IS IN FRONT? ═══════════════════════════
/// Talks to MainActivity.kt. Only works on Android and after the user grants "Usage access".
class UsageBridge {
  static const MethodChannel _ch = MethodChannel('grove/usage');
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> hasAccess() async {
    if (!supported) return false;
    try {
      return (await _ch.invokeMethod<bool>('hasAccess')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('openSettings');
    } catch (_) {}
  }

  /// package name of the app that is currently in front (null = unknown)
  static Future<String?> foregroundApp() async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<String>('foregroundApp');
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════ SHARED UI ═══════════════════════════
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day}/${t.month}/${t.year}';
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Widget glassCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(14), EdgeInsets margin = const EdgeInsets.only(bottom: 12)}) => Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(color: const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(18)),
      child: child,
    );

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, shadows: _fShadow)),
    );

class GroveScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  const GroveScaffold({super.key, required this.title, required this.body, this.actions = const []});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF52A688), Color(0xFF63C9A3), Color(0xFF74E8BD)]),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: _fShadow)),
            actions: actions,
          ),
          body: SafeArea(child: body),
        ),
      );
}

Widget _centerText(String t) => Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.3, shadows: _fShadow)),
      ),
    );

const Widget _loader = Center(child: CircularProgressIndicator(color: Colors.white));

// ═══════════════════════════ NOTIFICATIONS ═══════════════════════════
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _refresh();
    _t = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (ApiAuthService.token == null) return;
    await ApiAuthService.loadMe();
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        IconButton(onPressed: _open, icon: const Icon(Icons.notifications, color: Colors.white, size: 28)),
        if (AppUser.unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                child: Text(AppUser.unread > 9 ? '9+' : '${AppUser.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('GET', '/api/notifications');
      final list = (j['notifications'] as List).cast<Map<String, dynamic>>();
      final unread = (j['unread'] as num).toInt();
      if (mounted) {
        setState(() {
          items = list;
          loading = false;
          error = null;
        });
      }
      if (unread > 0) {
        await Api.call('POST', '/api/notifications/read-all');
        AppUser.unread = 0;
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> _clear() async {
    try {
      await Api.call('DELETE', '/api/notifications');
      AppUser.unread = 0;
      if (mounted) setState(() => items = []);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add;
      case 'friend_accepted':
        return Icons.group;
      case 'achievement':
        return Icons.emoji_events;
      case 'real_tree':
        return Icons.public;
      case 'shop':
        return Icons.storefront;
      default:
        return Icons.eco;
    }
  }

  @override
  Widget build(BuildContext context) => GroveScaffold(
        title: 'Notifications',
        actions: [
          if (items.isNotEmpty) IconButton(tooltip: 'Clear all', onPressed: _clear, icon: const Icon(Icons.delete_sweep)),
        ],
        body: loading
            ? _loader
            : error != null
                ? _centerText(error ?? '')
                : items.isEmpty
                    ? _centerText('No notifications yet.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final n = items[i];
                          final fresh = n['read'] != true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: fresh ? const Color(0x99FFFFFF) : const Color(0x44FFFFFF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CircleAvatar(radius: 20, backgroundColor: kDark, child: Icon(_icon((n['type'] ?? '') as String), color: Colors.white, size: 20)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text((n['title'] ?? '') as String, style: const TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w700)),
                                  if (((n['body'] ?? '') as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(n['body'] as String, style: const TextStyle(color: kDark, fontSize: 14))),
                                  const SizedBox(height: 4),
                                  Text(timeAgo(DateTime.parse(n['createdAt'] as String).toLocal()), style: const TextStyle(color: Color(0xFF3B6F6A), fontSize: 12)),
                                ]),
                              ),
                              if (fresh) const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, color: Colors.redAccent, size: 10)),
                            ]),
                          );
                        },
                      ),
      );
}

// ═══════════════════════════ FRIENDS ═══════════════════════════
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final email = TextEditingController();
  List<Map<String, dynamic>> board = [], requests = [];
  bool loading = true, busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('GET', '/api/friends');
      if (!mounted) return;
      setState(() {
        board = (j['leaderboard'] as List).cast<Map<String, dynamic>>();
        requests = (j['requests'] as List).cast<Map<String, dynamic>>();
        loading = false;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() f, {bool clear = false}) async {
    setState(() => busy = true);
    try {
      final j = await f();
      if (mounted) toast(context, (j['message'] ?? 'Done').toString());
      if (clear) email.clear();
      await _load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _remove(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text('Remove ${f['name']} from your friends?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _act(() => Api.call('DELETE', '/api/friends/${f['id']}'));
  }

  String _medal(int i) => i == 0 ? '🥇' : (i == 1 ? '🥈' : (i == 2 ? '🥉' : '${i + 1}'));

  @override
  Widget build(BuildContext context) => GroveScaffold(
        title: 'Friends',
        body: loading
            ? _loader
            : error != null
                ? _centerText(error ?? '')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                      glassCard(
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(hintText: "Friend's email", border: InputBorder.none),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: kDark),
                            onPressed: busy ? null : () => _act(() => Api.call('POST', '/api/friends/request', {'email': email.text.trim()}), clear: true),
                            child: const Text('Add'),
                          ),
                        ]),
                      ),
                      if (requests.isNotEmpty) ...[
                        sectionTitle('Friend requests'),
                        for (final r in requests)
                          glassCard(
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text((r['name'] ?? '') as String, style: const TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w700)),
                                  Text((r['email'] ?? '') as String, style: const TextStyle(color: kDark, fontSize: 13)),
                                ]),
                              ),
                              IconButton(
                                tooltip: 'Accept',
                                onPressed: busy ? null : () => _act(() => Api.call('POST', '/api/friends/accept', {'userId': r['id']})),
                                icon: const Icon(Icons.check_circle, color: kDark, size: 30),
                              ),
                              IconButton(
                                tooltip: 'Reject',
                                onPressed: busy ? null : () => _act(() => Api.call('POST', '/api/friends/reject', {'userId': r['id']})),
                                icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 30),
                              ),
                            ]),
                          ),
                      ],
                      sectionTitle('Leaderboard (total focus time)'),
                      for (int i = 0; i < board.length; i++)
                        glassCard(
                          child: Row(children: [
                            SizedBox(width: 34, child: Text(_medal(i), style: const TextStyle(color: kDark, fontSize: 20, fontWeight: FontWeight.w700))),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(board[i]['isMe'] == true ? '${board[i]['name']} (You)' : '${board[i]['name']}', style: const TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w700)),
                                Text('${board[i]['trees']} trees · 🪙 ${board[i]['coins']}', style: const TextStyle(color: kDark, fontSize: 13)),
                              ]),
                            ),
                            Text('${board[i]['minutes']} min', style: const TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w700)),
                            if (board[i]['isMe'] != true) IconButton(tooltip: 'Remove', onPressed: busy ? null : () => _remove(board[i]), icon: const Icon(Icons.person_remove, color: kDark)),
                          ]),
                        ),
                      if (board.length <= 1) _centerText('Add a friend by email to compete together!'),
                    ]),
                  ),
      );
}

// ═══════════════════════════ ACHIEVEMENTS ═══════════════════════════
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  List<Map<String, dynamic>> list = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('GET', '/api/achievements');
      if (!mounted) return;
      setState(() {
        list = (j['achievements'] as List).cast<Map<String, dynamic>>();
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = list.where((a) => a['unlocked'] == true).length;
    return GroveScaffold(
      title: 'Achievements',
      body: loading
          ? _loader
          : error != null
              ? _centerText(error ?? '')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Center(child: Text('$done / ${list.length} unlocked', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, shadows: _fShadow))),
                  const SizedBox(height: 12),
                  for (final a in list)
                    Opacity(
                      opacity: a['unlocked'] == true ? 1 : .6,
                      child: glassCard(
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: a['unlocked'] == true ? const Color(0xCCBEFFE1) : const Color(0x55FFFFFF), shape: BoxShape.circle),
                            child: Text(a['unlocked'] == true ? (a['icon'] ?? '🏅') as String : '🔒', style: const TextStyle(fontSize: 26)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((a['title'] ?? '') as String, style: const TextStyle(color: kDark, fontSize: 17, fontWeight: FontWeight.w700)),
                              Text((a['description'] ?? '') as String, style: const TextStyle(color: kDark, fontSize: 13)),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: ((a['value'] as num) / (a['target'] as num)).toDouble().clamp(0.0, 1.0).toDouble(),
                                  minHeight: 8,
                                  backgroundColor: const Color(0x44FFFFFF),
                                  valueColor: const AlwaysStoppedAnimation<Color>(kDark),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('${a['value']} / ${a['target']}', style: const TextStyle(color: kDark, fontSize: 12)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}

// ═══════════════════════════ SETTINGS (tags, grace period, whitelist) ═══════════════════════════
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final tagCtl = TextEditingController(), appCtl = TextEditingController();
  late double grace = AppUser.graceSeconds.toDouble();
  bool access = false, busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tagCtl.dispose();
    appCtl.dispose();
    super.dispose();
  }

  // the user comes back from the Android "Usage access" screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final a = await UsageBridge.hasAccess();
    if (mounted) setState(() => access = a);
  }

  Future<void> _send(Future<Map<String, dynamic>> Function() f, {VoidCallback? onOk}) async {
    setState(() => busy = true);
    try {
      final j = await f();
      AppUser.applyExtras(j);
      grace = AppUser.graceSeconds.toDouble();
      onOk?.call();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _addTag() async {
    final name = tagCtl.text.trim();
    if (name.isEmpty) return;
    await _send(() => Api.call('POST', '/api/settings/tags', {'name': name}), onOk: tagCtl.clear);
  }

  Future<void> _deleteTag(String t) => _send(() => Api.call('DELETE', '/api/settings/tags/${Uri.encodeComponent(t)}'));

  Future<void> _saveApps(List<String> apps) => _send(() => Api.call('PUT', '/api/settings', {'whitelistApps': apps}));

  Future<void> _toggleApp(String pkg, bool on) {
    final l = List<String>.from(AppUser.whitelist);
    if (on) {
      if (!l.contains(pkg)) l.add(pkg);
    } else {
      l.remove(pkg);
    }
    return _saveApps(l);
  }

  Future<void> _addCustomApp() async {
    final pkg = appCtl.text.trim();
    if (pkg.isEmpty) return;
    final l = List<String>.from(AppUser.whitelist);
    if (!l.contains(pkg)) l.add(pkg);
    await _send(() => Api.call('PUT', '/api/settings', {'whitelistApps': l}), onOk: appCtl.clear);
  }

  @override
  Widget build(BuildContext context) {
    final presetPkgs = kPresetApps.values.toSet();
    final custom = AppUser.whitelist.where((p) => !presetPkgs.contains(p)).toList();
    return GroveScaffold(
      title: 'Settings',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        sectionTitle('Focus tags'),
        glassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final t in AppUser.tags)
                Chip(
                  label: Text(t, style: const TextStyle(color: kDark)),
                  backgroundColor: const Color(0x80FFFFFF),
                  deleteIconColor: kDark,
                  onDeleted: (busy || AppUser.tags.length <= 1) ? null : () => _deleteTag(t),
                ),
            ]),
            Row(children: [
              Expanded(child: TextField(controller: tagCtl, maxLength: 30, decoration: const InputDecoration(hintText: 'New tag (e.g. Coding)', counterText: ''))),
              IconButton(onPressed: busy ? null : _addTag, icon: const Icon(Icons.add_circle, color: kDark, size: 32)),
            ]),
          ]),
        ),
        sectionTitle('Grace period'),
        glassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(grace.round() == 0 ? 'Tree withers immediately when you leave the app' : 'You can be away for ${grace.round()} seconds', style: const TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w600)),
            Slider(
              value: grace,
              min: 0,
              max: 60,
              divisions: 12,
              label: '${grace.round()} s',
              activeColor: kDark,
              onChanged: (v) => setState(() => grace = v),
              onChangeEnd: (v) => _send(() => Api.call('PUT', '/api/settings', {'graceSeconds': v.round()})),
            ),
          ]),
        ),
        sectionTitle('Allowed apps (whitelist)'),
        glassCard(
          child: !UsageBridge.supported
              ? const Text('The app whitelist works in the Android app. In a browser, leaving the tab always counts as leaving.', style: TextStyle(color: kDark, fontSize: 14))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Apps you open from here will NOT wither your tree.', style: TextStyle(color: kDark, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (!access)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: kDark),
                      onPressed: UsageBridge.openSettings,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Allow "Usage access" for Grove'),
                    )
                  else
                    const Row(children: [Icon(Icons.check_circle, color: kDark, size: 20), SizedBox(width: 6), Text('Usage access granted', style: TextStyle(color: kDark, fontWeight: FontWeight.w600))]),
                  for (final e in kPresetApps.entries)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: kDark,
                      title: Text(e.key, style: const TextStyle(color: kDark)),
                      value: AppUser.whitelist.contains(e.value),
                      onChanged: busy ? null : (v) => _toggleApp(e.value, v),
                    ),
                  for (final p in custom)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(p, style: const TextStyle(color: kDark)),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: kDark), onPressed: busy ? null : () => _toggleApp(p, false)),
                    ),
                  Row(children: [
                    Expanded(child: TextField(controller: appCtl, decoration: const InputDecoration(hintText: 'Other app package, e.g. com.slack'))),
                    IconButton(onPressed: busy ? null : _addCustomApp, icon: const Icon(Icons.add_circle, color: kDark, size: 32)),
                  ]),
                ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ STATS: FOCUS BY TAG ═══════════════════════════
class TagBreakdown extends StatelessWidget {
  final List<Session> sessions; // completed sessions only
  const TagBreakdown({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final s in sessions) {
      totals[s.tag] = (totals[s.tag] ?? 0) + s.minutes;
    }
    if (totals.isEmpty) return const SizedBox.shrink();
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionTitle('Focus by tag'),
      glassCard(
        child: Column(children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(e.key, style: const TextStyle(color: kDark, fontWeight: FontWeight.w600)),
                  Text('${e.value} min · ${(100 * e.value / total).round()}%', style: const TextStyle(color: kDark)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: e.value / total, minHeight: 8, backgroundColor: const Color(0x44FFFFFF), valueColor: const AlwaysStoppedAnimation<Color>(kDark)),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ═══════════════════════════ SHOP: REAL TREE ═══════════════════════════
class RealTreeCard extends StatefulWidget {
  final VoidCallback onChanged;
  const RealTreeCard({super.key, required this.onChanged});
  @override
  State<RealTreeCard> createState() => _RealTreeCardState();
}

class _RealTreeCardState extends State<RealTreeCard> {
  bool busy = false;

  Future<void> _plant() async {
    setState(() => busy = true);
    final err = await shopCall('plant-real', '');
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, err ?? 'Thank you! Your real tree request was saved 🌍');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => glassCard(
        margin: const EdgeInsets.only(top: 4, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🌍 Plant a real tree', style: TextStyle(color: kDark, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Spend $kRealTreeCost coins to request one real tree.\nTrees requested so far: ${AppUser.realTrees}', style: const TextStyle(color: kDark, fontSize: 14)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kDark),
              onPressed: (busy || AppUser.coins < kRealTreeCost) ? null : _plant,
              child: Text(AppUser.coins < kRealTreeCost ? 'Need 🪙 $kRealTreeCost' : 'Plant for 🪙 $kRealTreeCost'),
            ),
          ),
        ]),
      );
}