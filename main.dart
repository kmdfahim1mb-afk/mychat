import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// অ্যাপের নাম বদলাতে শুধু নিচের লাইনের নামটা বদলান (ইংরেজি অক্ষরে লিখুন)
const kAppName = 'Alap';

const kGreen = Color(0xFF075E54);

// ছবি/ফাইল/ভয়েসের সর্বোচ্চ আকার (Firestore-এর ১ MB সীমার কারণে)
const kMaxBytes = 700000;

// ---------------- ভাষা (বাংলা / English) ----------------
final ValueNotifier<String> appLang = ValueNotifier<String>('bn');

bool get isBn => appLang.value == 'bn';

/// বাংলা লেখাটা দিলে, ভাষা English হলে তার ইংরেজি রূপ ফেরত দেয়
String tr(String bn) => isBn ? bn : (_en[bn] ?? bn);

/// বাংলা ভাষায় সংখ্যাকে বাংলা অঙ্কে (০১২৩) বদলে দেয়
String numL(String s) {
  if (!isBn) return s;
  const d = '০১২৩৪৫৬৭৮৯';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => d[int.parse(m[0]!)]);
}

Future<void> setLang(String l) async {
  appLang.value = l;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
  } catch (_) {}
}

Future<void> pickLanguage(BuildContext context) async {
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('ভাষা / Language'),
      children: [
        ListTile(
          title: const Text('বাংলা'),
          trailing: isBn ? const Icon(Icons.check, color: kGreen) : null,
          onTap: () => Navigator.pop(ctx, 'bn'),
        ),
        ListTile(
          title: const Text('English'),
          trailing: !isBn ? const Icon(Icons.check, color: kGreen) : null,
          onTap: () => Navigator.pop(ctx, 'en'),
        ),
      ],
    ),
  );
  if (r != null && r != appLang.value) await setLang(r);
}

const Map<String, String> _en = {
  'সব ঘর পূরণ করুন': 'Please fill in all fields',
  'কিছু একটা ভুল হয়েছে': 'Something went wrong',
  'ত্রুটি': 'Error',
  'আপনার নাম': 'Your name',
  'ইমেইল': 'Email',
  'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)': 'Password (at least 6 characters)',
  'লগইন': 'Log in',
  'সাইন-আপ': 'Sign up',
  'নতুন অ্যাকাউন্ট খুলুন': 'Create a new account',
  'আগেই অ্যাকাউন্ট আছে? লগইন করুন': 'Already have an account? Log in',
  'ভুল ইমেইল বা পাসওয়ার্ড': 'Wrong email or password',
  'এই ইমেইলে অ্যাকাউন্ট নেই': 'No account with this email',
  'এই ইমেইল আগেই ব্যবহার হয়েছে': 'This email is already in use',
  'পাসওয়ার্ড খুব ছোট (কমপক্ষে ৬ অক্ষর)': 'Password is too short (min 6 characters)',
  'ইমেইলটা সঠিক নয়': 'The email address is not valid',
  'ইন্টারনেট সংযোগ পরীক্ষা করুন': 'Check your internet connection',
  'অ্যাকাউন্ট ডিলিট': 'Delete account',
  'এই অ্যাকাউন্ট, ফ্রেন্ড তালিকা ও সব চ্যাট মুছে যাবে। এটা আর ফেরানো যাবে না। নিশ্চিত করতে পাসওয়ার্ড দিন।':
      'This account, your friends and all chats will be deleted. This cannot be undone. Enter your password to confirm.',
  'পাসওয়ার্ড': 'Password',
  'বাতিল': 'Cancel',
  'ডিলিট করুন': 'Delete',
  'অ্যাকাউন্ট ডিলিট হয়েছে': 'Account deleted',
  'ডিলিট করা যায়নি': 'Could not delete',
  'ব্যর্থ হয়েছে': 'Failed',
  'ফ্রেন্ড হয়ে গেছেন': 'You are now friends',
  'রিকোয়েস্ট বাতিল হয়েছে': 'Request cancelled',
  'ফ্রেন্ড রিকোয়েস্ট পাঠানো হয়েছে': 'Friend request sent',
  'ফ্রেন্ড রিকোয়েস্ট পাঠান': 'Send friend request',
  'ফ্রেন্ড রিকোয়েস্ট': 'Friend requests',
  'ফ্রেন্ড': 'Friend',
  'গ্রহণ': 'Accept',
  'গ্রহণ করুন': 'Accept',
  'ফিরিয়ে দিন': 'Decline',
  'পাঠানো হয়েছে': 'Sent',
  'আমাকে পাঠানো': 'Received',
  'আমি পাঠিয়েছি': 'Sent by me',
  'কিছু নেই': 'Nothing here',
  'এখনো কোনো চ্যাট বা ফ্রেন্ড নেই।\nউপরের সার্চবারে নাম বা পুরো ইমেইল লিখে কাউকে খুঁজুন।':
      'No chats or friends yet.\nUse the search bar above to find someone by name or full email.',
  'ফ্রেন্ড — মেসেজ করতে ট্যাপ করুন': 'Friend — tap to message',
  'কাউকে পাওয়া যায়নি।\nনামের শুরুর অংশ অথবা পুরো ইমেইল লিখুন।':
      'No one found.\nType the beginning of a name or a full email.',
  'সার্চ করা যায়নি': 'Search failed',
  'নাম বা পুরো ইমেইল দিয়ে খুঁজুন': 'Search by name or full email',
  'চ্যাট তালিকা থেকে সরান': 'Remove from chat list',
  'ফ্রেন্ড থেকে বাদ দিন': 'Remove friend',
  'বাদ দিন': 'Remove',
  'কে ফ্রেন্ড তালিকা থেকে বাদ দেবেন?': 'Remove from your friends?',
  'লগআউট': 'Log out',
  'অ্যাকাউন্ট ডিলিট করুন': 'Delete account',
  'মেসেজ লিখুন': 'Type a message',
  'পাঠান': 'Send',
  'ভয়েস মেসেজ রেকর্ড করুন': 'Record voice message',
  'ভয়েস মেসেজ': 'Voice message',
  'ছবি': 'Photo',
  'রেকর্ড হচ্ছে': 'Recording',
  'মাইক্রোফোনের অনুমতি দিন (ফোনের সেটিংস থেকেও দেওয়া যায়)':
      'Allow microphone access (you can also do it from phone settings)',
  'রেকর্ড শুরু করা যায়নি': 'Could not start recording',
  'ভয়েস মেসেজ বেশি বড় হয়ে গেছে': 'Voice message is too long',
  'আরেকটু বেশি সময় ধরে বলুন': 'Please record for a little longer',
  'ভয়েস মেসেজ পাঠানো যায়নি': 'Could not send voice message',
  'চালানো যায়নি': 'Could not play',
  'পাঠানো যায়নি': 'Could not send',
  'আজ': 'Today',
  'গতকাল': 'Yesterday',
  'সম্পাদিত': 'edited',
  'কপি করুন': 'Copy',
  'কপি হয়েছে': 'Copied',
  'মেসেজ এডিট করুন': 'Edit message',
  'মেসেজ মুছুন': 'Delete message',
  'মেসেজটা সবার জন্য মুছে যাবে।': 'This message will be deleted for everyone.',
  'সেভ করুন': 'Save',
  'গ্যালারি থেকে ছবি': 'Photo from gallery',
  'ক্যামেরা': 'Camera',
  'ফাইল': 'File',
  'ছবি বেশি বড় (সর্বোচ্চ প্রায় ৭০০ KB)': 'Photo is too large (max about 700 KB)',
  'ফাইল বেশি বড় (সর্বোচ্চ প্রায় ৭০০ KB)': 'File is too large (max about 700 KB)',
  'ছবি পাঠানো যায়নি': 'Could not send photo',
  'ফাইল পাঠানো যায়নি': 'Could not send file',
  'ফাইল খোলা যায়নি': 'Could not open file',
  'ছবি দেখা যাচ্ছে না': 'Cannot show photo',
};

// ---------------- সাধারণ সাহায্যকারী ফাংশন ----------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final p = await SharedPreferences.getInstance();
    appLang.value = p.getString('lang') ?? 'bn';
  } catch (_) {}
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const MyChatApp());
}

/// দুজনের uid থেকে একটাই আইডি বানায় (চ্যাট ও ফ্রেন্ডশিপের জন্য)
String pairId(String a, String b) {
  final ids = [a, b]..sort();
  return ids.join('_');
}

/// আমার নাম
String get myName {
  final u = FirebaseAuth.instance.currentUser;
  final n = (u?.displayName ?? '').trim();
  if (n.isNotEmpty) return n;
  return (u?.email ?? 'User').split('@').first;
}

/// ইমেইল আংশিক লুকিয়ে দেখায়: ab***@gmail.com
String maskEmail(String e) {
  final i = e.indexOf('@');
  if (i <= 0) return '';
  final name = e.substring(0, i);
  final shown = name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
  return '$shown***${e.substring(i)}';
}

String clock(int s) {
  final m = (s ~/ 60).toString();
  final r = (s % 60).toString().padLeft(2, '0');
  return numL('$m:$r');
}

String hhmm(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return numL('$h:$m');
}

const _monthsBn = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
];
const _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "আজ", "গতকাল" অথবা "২৬ অক্টোবর ২০২৬"
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return tr('আজ');
  if (diff == 1) return tr('গতকাল');
  final month = (isBn ? _monthsBn : _monthsEn)[d.month - 1];
  return numL('${d.day} $month ${d.year}');
}

/// চ্যাট তালিকার জন্য: আজকে হলে সময়, নইলে তারিখ
String fmtTime(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  if (sameDay(d, DateTime.now())) return hhmm(d);
  return numL('${d.day}/${d.month}/${d.year % 100}');
}

void toast(BuildContext context, String t) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
}

Future<bool> confirmDialog(
    BuildContext context, String title, String body, String okText) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('বাতিল'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return r == true;
}

String authMsg(FirebaseAuthException e) {
  switch (e.code) {
    case 'wrong-password':
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return tr('ভুল ইমেইল বা পাসওয়ার্ড');
    case 'user-not-found':
      return tr('এই ইমেইলে অ্যাকাউন্ট নেই');
    case 'email-already-in-use':
      return tr('এই ইমেইল আগেই ব্যবহার হয়েছে');
    case 'weak-password':
      return tr('পাসওয়ার্ড খুব ছোট (কমপক্ষে ৬ অক্ষর)');
    case 'invalid-email':
      return tr('ইমেইলটা সঠিক নয়');
    case 'network-request-failed':
      return tr('ইন্টারনেট সংযোগ পরীক্ষা করুন');
  }
  return e.message ?? tr('কিছু একটা ভুল হয়েছে');
}

/// ইউজারের প্রোফাইল ডকুমেন্ট ঠিক রাখে (সার্চের জন্য nameLower/emailLower লাগে)।
/// পুরোনো অ্যাকাউন্টগুলোও লগইন করলে এখানে আপডেট হয়ে যায়।
Future<void> ensureProfile() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  try {
    final email = u.email ?? '';
    final name = (u.displayName ?? '').trim();
    final data = <String, dynamic>{
      'uid': u.uid,
      'email': email,
      'emailLower': email.toLowerCase(),
    };
    if (name.isNotEmpty) {
      data['name'] = name;
      data['nameLower'] = name.toLowerCase();
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .set(data, SetOptions(merge: true));
  } catch (_) {}
}

/// চ্যাট তালিকায় শেষ মেসেজের সারাংশ (ভাষা-নিরপেক্ষ ভাবে জমা থাকে)
Map<String, dynamic> previewOf(Map<String, dynamic>? m) {
  if (m == null) return {'lastType': 'text', 'lastText': ''};
  switch (m['type']) {
    case 'voice':
      return {'lastType': 'voice', 'lastText': ''};
    case 'image':
      return {'lastType': 'image', 'lastText': ''};
    case 'file':
      return {
        'lastType': 'file',
        'lastText': (m['fileName'] ?? '').toString()
      };
    default:
      final t = (m['text'] ?? '').toString();
      return {
        'lastType': 'text',
        'lastText': String.fromCharCodes(t.runes.take(60))
      };
  }
}

String previewLabel(Map<String, dynamic> chat) {
  final text = (chat['lastText'] ?? '').toString();
  switch (chat['lastType']) {
    case 'voice':
      return '🎤 ${tr('ভয়েস মেসেজ')}';
    case 'image':
      return '📷 ${tr('ছবি')}';
    case 'file':
      return '📎 $text';
    default:
      return text;
  }
}

// ---------------- অ্যাপ ----------------
class MyChatApp extends StatelessWidget {
  const MyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
          appBarTheme: const AppBarTheme(
            backgroundColor: kGreen,
            foregroundColor: Colors.white,
          ),
          useMaterial3: true,
        ),
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            final user = snap.data;
            if (user == null) return const AuthPage();
            return HomePage(key: ValueKey(user.uid));
          },
        ),
      ),
    );
  }
}

// ---------------- লগইন / সাইন-আপ ----------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text.trim();
    final name = _name.text.trim();
    if (email.isEmpty || pass.isEmpty || (!_isLogin && name.isEmpty)) {
      _msg(tr('সব ঘর পূরণ করুন'));
      return;
    }
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: pass);
      } else {
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: pass);
        await cred.user!.updateDisplayName(name);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'uid': cred.user!.uid,
          'name': name,
          'nameLower': name.toLowerCase(),
          'email': email,
          'emailLower': email.toLowerCase(),
        });
      }
    } on FirebaseAuthException catch (e) {
      _msg(authMsg(e));
    } catch (e) {
      _msg('${tr('ত্রুটি')}: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => pickLanguage(context),
                    icon: const Icon(Icons.language),
                    label: Text(isBn ? 'বাংলা' : 'English'),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'icon.png',
                    width: 96,
                    height: 96,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.chat, size: 72, color: kGreen),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(kAppName,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kGreen)),
                const SizedBox(height: 24),
                if (!_isLogin)
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                        labelText: tr('আপনার নাম'),
                        border: const OutlineInputBorder()),
                  ),
                if (!_isLogin) const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: tr('ইমেইল'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: tr('পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? tr('লগইন') : tr('সাইন-আপ')),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? tr('নতুন অ্যাকাউন্ট খুলুন')
                      : tr('আগেই অ্যাকাউন্ট আছে? লগইন করুন')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- অ্যাকাউন্ট ডিলিট ----------------
// নিজের অ্যাকাউন্ট ও তার সব তথ্য (ফ্রেন্ড, রিকোয়েস্ট, চ্যাট) মুছে ফেলে।
Future<void> deleteMyAccount(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.email == null) return;
  final pass = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('অ্যাকাউন্ট ডিলিট')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.email!,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(tr(
              'এই অ্যাকাউন্ট, ফ্রেন্ড তালিকা ও সব চ্যাট মুছে যাবে। এটা আর ফেরানো যাবে না। নিশ্চিত করতে পাসওয়ার্ড দিন।')),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: true,
            decoration: InputDecoration(
                labelText: tr('পাসওয়ার্ড'),
                border: const OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('বাতিল'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('ডিলিট করুন')),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final cred = EmailAuthProvider.credential(
        email: user.email!, password: pass.text.trim());
    await user.reauthenticateWithCredential(cred);

    final db = FirebaseFirestore.instance;
    final uid = user.uid;

    // ফ্রেন্ডশিপ
    final fr = await db
        .collection('friendships')
        .where('members', arrayContains: uid)
        .get();
    for (final d in fr.docs) {
      await d.reference.delete();
    }
    // রিকোয়েস্ট (পাঠানো ও আসা)
    final r1 =
        await db.collection('requests').where('from', isEqualTo: uid).get();
    final r2 =
        await db.collection('requests').where('to', isEqualTo: uid).get();
    for (final d in [...r1.docs, ...r2.docs]) {
      await d.reference.delete();
    }
    // চ্যাট ও মেসেজ
    final chats = await db
        .collection('chats')
        .where('members', arrayContains: uid)
        .get();
    for (final c in chats.docs) {
      final msgs = await c.reference.collection('messages').get();
      for (var i = 0; i < msgs.docs.length; i += 400) {
        final b = db.batch();
        for (final m in msgs.docs.skip(i).take(400)) {
          b.delete(m.reference);
        }
        await b.commit();
      }
      await c.reference.delete();
    }
    // প্রোফাইল ও লগইন অ্যাকাউন্ট
    await db.collection('users').doc(uid).delete();
    await user.delete();
    messenger
        .showSnackBar(SnackBar(content: Text(tr('অ্যাকাউন্ট ডিলিট হয়েছে'))));
  } on FirebaseAuthException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(authMsg(e))));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('${tr('ডিলিট করা যায়নি')}: $e')));
  } finally {
    nav.pop();
  }
}

// ---------------- ফ্রেন্ড রিকোয়েস্ট ----------------
Future<void> sendFriendRequest(String otherUid, String otherName) async {
  final me = FirebaseAuth.instance.currentUser!;
  await FirebaseFirestore.instance
      .collection('requests')
      .doc('${me.uid}_$otherUid')
      .set({
    'from': me.uid,
    'to': otherUid,
    'fromName': myName,
    'toName': otherName,
    'time': FieldValue.serverTimestamp(),
  });
}

/// রিকোয়েস্ট বাতিল (নিজের পাঠানো) বা ফিরিয়ে দেওয়া (অন্যের পাঠানো)
Future<void> removeRequest(String fromUid, String toUid) {
  return FirebaseFirestore.instance
      .collection('requests')
      .doc('${fromUid}_$toUid')
      .delete();
}

Future<void> acceptFriendRequest(String fromUid, String fromName) async {
  final me = FirebaseAuth.instance.currentUser!;
  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  batch.set(db.collection('friendships').doc(pairId(me.uid, fromUid)), {
    'members': [me.uid, fromUid],
    'names': {me.uid: myName, fromUid: fromName},
    'time': FieldValue.serverTimestamp(),
  });
  batch.delete(db.collection('requests').doc('${fromUid}_${me.uid}'));
  await batch.commit();
}

// ---------------- হোম: চ্যাট তালিকা + সার্চ ----------------
class _Entry {
  final String uid;
  String name;
  String lastText;
  Timestamp? time;
  bool chat;
  bool friend;
  _Entry(this.uid, this.name,
      {this.lastText = '', this.time, this.chat = false, this.friend = false});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final me = FirebaseAuth.instance.currentUser!;
  final _search = TextEditingController();
  final List<StreamSubscription> _subs = [];
  Timer? _debounce;
  int _token = 0;

  Map<String, Map<String, dynamic>> _chats = {}; // অন্যজনের uid -> চ্যাট ডেটা
  Map<String, String> _friends = {}; // ফ্রেন্ডের uid -> নাম
  Set<String> _outgoing = {}; // যাদের রিকোয়েস্ট পাঠিয়েছি
  Set<String> _incoming = {}; // যারা আমাকে রিকোয়েস্ট পাঠিয়েছে

  String _q = '';
  bool _searching = false;
  String? _searchErr;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    ensureProfile();
    final db = FirebaseFirestore.instance;

    void onErr(Object e) {
      if (mounted) setState(() => _error = '$e');
    }

    String otherOf(Map<String, dynamic> data) {
      final members = List<String>.from(data['members'] ?? const []);
      return members.firstWhere((x) => x != me.uid, orElse: () => '');
    }

    _subs.add(db
        .collection('chats')
        .where('members', arrayContains: me.uid)
        .snapshots()
        .listen((s) {
      final m = <String, Map<String, dynamic>>{};
      for (final d in s.docs) {
        final data = d.data();
        final other = otherOf(data);
        if (other.isEmpty) continue;
        final hidden = List<String>.from(data['hiddenBy'] ?? const []);
        if (hidden.contains(me.uid)) continue;
        m[other] = data;
      }
      if (mounted) setState(() => _chats = m);
    }, onError: onErr));

    _subs.add(db
        .collection('friendships')
        .where('members', arrayContains: me.uid)
        .snapshots()
        .listen((s) {
      final m = <String, String>{};
      for (final d in s.docs) {
        final data = d.data();
        final other = otherOf(data);
        if (other.isEmpty) continue;
        final names = Map<String, dynamic>.from(data['names'] ?? {});
        m[other] = (names[other] ?? '?').toString();
      }
      if (mounted) setState(() => _friends = m);
    }, onError: onErr));

    _subs.add(db
        .collection('requests')
        .where('to', isEqualTo: me.uid)
        .snapshots()
        .listen((s) {
      final ids = <String>{};
      for (final d in s.docs) {
        final from = (d.data()['from'] ?? '').toString();
        if (from.isNotEmpty) ids.add(from);
      }
      if (mounted) setState(() => _incoming = ids);
    }, onError: onErr));

    _subs.add(db
        .collection('requests')
        .where('from', isEqualTo: me.uid)
        .snapshots()
        .listen((s) {
      final ids = <String>{};
      for (final d in s.docs) {
        final to = (d.data()['to'] ?? '').toString();
        if (to.isNotEmpty) ids.add(to);
      }
      if (mounted) setState(() => _outgoing = ids);
    }, onError: onErr));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ---------- সার্চ ----------
  void _onQuery(String v) {
    _debounce?.cancel();
    final q = v.trim().toLowerCase();
    setState(() {
      _q = q;
      _searchErr = null;
      if (q.isEmpty) {
        _results = [];
        _searching = false;
        _token++;
      } else {
        _searching = true;
      }
    });
    if (q.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final my = ++_token;
    try {
      final users = FirebaseFirestore.instance.collection('users');
      final found = <String, Map<String, dynamic>>{};
      if (q.contains('@')) {
        // ইমেইল দিয়ে খুঁজলে পুরো ইমেইল মিলতে হবে
        final s = await users.where('emailLower', isEqualTo: q).limit(5).get();
        for (final d in s.docs) {
          found[d.id] = d.data();
        }
      } else {
        // নামের শুরু দিয়ে খোঁজা
        final s = await users
            .where('nameLower', isGreaterThanOrEqualTo: q)
            .where('nameLower', isLessThanOrEqualTo: '$q')
            .limit(20)
            .get();
        for (final d in s.docs) {
          found[d.id] = d.data();
        }
      }
      found.remove(me.uid);
      if (!mounted || my != _token) return;
      setState(() {
        _results = found.values.toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted || my != _token) return;
      setState(() {
        _results = [];
        _searching = false;
        _searchErr = '$e';
      });
    }
  }

  void _clearSearch() {
    _search.clear();
    _onQuery('');
  }

  void _openChat(String uid, String name) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChatPage(otherUid: uid, otherName: name)),
    );
  }

  Future<void> _guard(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (ok != null) toast(context, ok);
    } catch (e) {
      toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  // ---------- চ্যাট তালিকা ----------
  List<_Entry> _entries() {
    final map = <String, _Entry>{};
    _chats.forEach((uid, data) {
      final names = Map<String, dynamic>.from(data['names'] ?? {});
      map[uid] = _Entry(
        uid,
        (names[uid] ?? '?').toString(),
        lastText: previewLabel(data),
        time: data['lastTime'] as Timestamp?,
        chat: true,
      );
    });
    _friends.forEach((uid, name) {
      final e = map[uid];
      if (e == null) {
        map[uid] = _Entry(uid, name, friend: true);
      } else {
        e.friend = true;
      }
    });
    final list = map.values.toList();
    DateTime t(_Entry e) =>
        e.time?.toDate() ??
        (e.chat ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0));
    list.sort((a, b) => t(b).compareTo(t(a)));
    return list;
  }

  Future<void> _manage(_Entry e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(e.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (e.chat)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(tr('চ্যাট তালিকা থেকে সরান')),
                onTap: () => Navigator.pop(ctx, 'hide'),
              ),
            if (e.friend)
              ListTile(
                leading: const Icon(Icons.person_remove, color: Colors.red),
                title: Text(tr('ফ্রেন্ড থেকে বাদ দিন'),
                    style: const TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'unfriend'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final db = FirebaseFirestore.instance;
    final id = pairId(me.uid, e.uid);
    if (action == 'hide') {
      await _guard(() => db.collection('chats').doc(id).update({
            'hiddenBy': FieldValue.arrayUnion([me.uid])
          }));
    } else if (action == 'unfriend') {
      final yes = await confirmDialog(
          context,
          tr('ফ্রেন্ড থেকে বাদ দিন'),
          '${e.name} ${tr('কে ফ্রেন্ড তালিকা থেকে বাদ দেবেন?')}',
          tr('বাদ দিন'));
      if (yes && mounted) {
        await _guard(() => db.collection('friendships').doc(id).delete());
      }
    }
  }

  Widget _chatList() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('ত্রুটি')}: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    final entries = _entries();
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('এখনো কোনো চ্যাট বা ফ্রেন্ড নেই।\nউপরের সার্চবারে নাম বা পুরো ইমেইল লিখে কাউকে খুঁজুন।'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          leading: _avatar(e.name),
          title: Row(
            children: [
              Flexible(child: Text(e.name, overflow: TextOverflow.ellipsis)),
              if (e.friend)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.verified_user, size: 14, color: kGreen),
                ),
            ],
          ),
          subtitle: Text(
            e.lastText.isNotEmpty
                ? e.lastText
                : tr('ফ্রেন্ড — মেসেজ করতে ট্যাপ করুন'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(fmtTime(e.time),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          onTap: () => _openChat(e.uid, e.name),
          onLongPress: () => _manage(e),
        );
      },
    );
  }

  // ---------- সার্চ ফলাফল ----------
  Widget _avatar(String name) => CircleAvatar(
        backgroundColor: kGreen,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white)),
      );

  Widget _action(String uid, String name) {
    if (_friends.containsKey(uid)) {
      return Text(tr('ফ্রেন্ড'),
          style:
              const TextStyle(color: kGreen, fontWeight: FontWeight.bold));
    }
    if (_incoming.contains(uid)) {
      return FilledButton.tonal(
        onPressed: () => _guard(
            () => acceptFriendRequest(uid, name), tr('ফ্রেন্ড হয়ে গেছেন')),
        child: Text(tr('গ্রহণ')),
      );
    }
    if (_outgoing.contains(uid)) {
      return TextButton(
        onPressed: () => _guard(
            () => removeRequest(me.uid, uid), tr('রিকোয়েস্ট বাতিল হয়েছে')),
        child: Text('${tr('পাঠানো হয়েছে')}\n(${tr('বাতিল')})',
            textAlign: TextAlign.center),
      );
    }
    return IconButton(
      icon: const Icon(Icons.person_add_alt_1, color: kGreen),
      tooltip: tr('ফ্রেন্ড রিকোয়েস্ট পাঠান'),
      onPressed: () => _guard(() => sendFriendRequest(uid, name),
          tr('ফ্রেন্ড রিকোয়েস্ট পাঠানো হয়েছে')),
    );
  }

  Widget _searchList() {
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_searchErr != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('সার্চ করা যায়নি')}: $_searchErr',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('কাউকে পাওয়া যায়নি।\nনামের শুরুর অংশ অথবা পুরো ইমেইল লিখুন।'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final u = _results[i];
        final uid = (u['uid'] ?? '').toString();
        final name = (u['name'] ?? '?').toString();
        return ListTile(
          leading: _avatar(name),
          title: Text(name),
          subtitle: Text(maskEmail((u['email'] ?? '').toString())),
          trailing: _action(uid, name),
          onTap: () => _openChat(uid, name), // সরাসরি মেসেজ পাঠানো যাবে
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: tr('ফ্রেন্ড রিকোয়েস্ট'),
            icon: Badge.count(
              count: _incoming.length,
              isLabelVisible: _incoming.isNotEmpty,
              child: const Icon(Icons.group_add),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestsPage()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'lang') {
                pickLanguage(context);
              } else if (v == 'logout') {
                FirebaseAuth.instance.signOut();
              } else if (v == 'delete') {
                deleteMyAccount(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'lang',
                child: Row(children: [
                  Icon(Icons.language),
                  SizedBox(width: 8),
                  Text('ভাষা / Language'),
                ]),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  const Icon(Icons.logout),
                  const SizedBox(width: 8),
                  Text(tr('লগআউট')),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  const Icon(Icons.delete_forever, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(tr('অ্যাকাউন্ট ডিলিট করুন'),
                      style: const TextStyle(color: Colors.red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: kGreen,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _search,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr('নাম বা পুরো ইমেইল দিয়ে খুঁজুন'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close), onPressed: _clearSearch),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _q.isEmpty ? _chatList() : _searchList()),
        ],
      ),
    );
  }
}

// ---------------- ফ্রেন্ড রিকোয়েস্ট পেজ ----------------
class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!;
    final db = FirebaseFirestore.instance;

    Widget section(String title, Query<Map<String, dynamic>> q, bool incoming) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Text('${tr('ত্রুটি')}: ${snap.error}');
          final docs = snap.data?.docs ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: kGreen)),
              ),
              if (docs.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(tr('কিছু নেই'),
                      style: const TextStyle(color: Colors.black54)),
                ),
              for (final d in docs)
                Builder(builder: (context) {
                  final data = d.data();
                  final from = (data['from'] ?? '').toString();
                  final to = (data['to'] ?? '').toString();
                  final name =
                      ((incoming ? data['fromName'] : data['toName']) ?? '?')
                          .toString();
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kGreen,
                      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(name),
                    trailing: incoming
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: tr('ফিরিয়ে দিন'),
                              onPressed: () async {
                                try {
                                  await removeRequest(from, to);
                                } catch (e) {
                                  toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle,
                                  color: kGreen),
                              tooltip: tr('গ্রহণ করুন'),
                              onPressed: () async {
                                try {
                                  await acceptFriendRequest(from, name);
                                  toast(context, tr('ফ্রেন্ড হয়ে গেছেন'));
                                } catch (e) {
                                  toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
                                }
                              },
                            ),
                          ])
                        : TextButton(
                            onPressed: () async {
                              try {
                                await removeRequest(from, to);
                              } catch (e) {
                                toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
                              }
                            },
                            child: Text(tr('বাতিল')),
                          ),
                  );
                }),
            ],
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('ফ্রেন্ড রিকোয়েস্ট'))),
      body: ListView(
        children: [
          section(tr('আমাকে পাঠানো'),
              db.collection('requests').where('to', isEqualTo: me.uid), true),
          section(tr('আমি পাঠিয়েছি'),
              db.collection('requests').where('from', isEqualTo: me.uid), false),
        ],
      ),
    );
  }
}

// ---------------- চ্যাট স্ক্রিন ----------------
typedef MsgDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

class ChatPage extends StatefulWidget {
  final String otherUid;
  final String otherName;
  const ChatPage({super.key, required this.otherUid, required this.otherName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final me = FirebaseAuth.instance.currentUser!;
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _starting = false;
  bool _busy = false; // ছবি/ফাইল পাঠানো চলছে
  bool _hasText = false;
  int _secs = 0;
  Timer? _timer;
  String? _recPath;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    _text.dispose();
    super.dispose();
  }

  String get chatId => pairId(me.uid, widget.otherUid);

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(chatId);

  CollectionReference<Map<String, dynamic>> get _msgs =>
      _chatRef.collection('messages');

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// চ্যাট ডকুমেন্ট তৈরি/আপডেট করে — এর ফলে দুজনের হোম তালিকায় চ্যাটটা দেখা যায়
  Future<void> _touchChat(Map<String, dynamic> preview) {
    return _chatRef.set({
      'members': [me.uid, widget.otherUid],
      'names': {me.uid: myName, widget.otherUid: widget.otherName},
      ...preview,
      'lastTime': FieldValue.serverTimestamp(),
      'lastSender': me.uid,
      'hiddenBy': <String>[],
    }, SetOptions(merge: true));
  }

  Future<void> _post(Map<String, dynamic> msg) async {
    final a = _touchChat(previewOf(msg));
    final b = _msgs.add({
      ...msg,
      'senderId': me.uid,
      'time': FieldValue.serverTimestamp(),
    });
    await Future.wait([a, b]);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      await _post({'type': 'text', 'text': t});
    } catch (e) {
      _snack('${tr('পাঠানো যায়নি')}: $e');
    }
  }

  // ---------- ছবি ও ফাইল ----------
  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: kGreen),
              title: Text(tr('গ্যালারি থেকে ছবি')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: kGreen),
              title: Text(tr('ক্যামেরা')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: kGreen),
              title: Text(tr('ফাইল')),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'file') {
      await _sendFile();
    } else {
      await _sendImage(
          choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Future<void> _sendImage(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(
        source: src,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 60,
      );
      if (x == null) return;
      setState(() => _busy = true);
      final bytes = await x.readAsBytes();
      if (bytes.length > kMaxBytes) {
        _snack(tr('ছবি বেশি বড় (সর্বোচ্চ প্রায় ৭০০ KB)'));
      } else {
        await _post({'type': 'image', 'image': base64Encode(bytes)});
      }
    } catch (e) {
      _snack('${tr('ছবি পাঠানো যায়নি')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendFile() async {
    try {
      final x = await openFile();
      if (x == null) return;
      setState(() => _busy = true);
      final len = await x.length();
      if (len > kMaxBytes) {
        _snack(tr('ফাইল বেশি বড় (সর্বোচ্চ প্রায় ৭০০ KB)'));
      } else {
        final bytes = await x.readAsBytes();
        await _post({
          'type': 'file',
          'fileData': base64Encode(bytes),
          'fileName': x.name,
          'size': len,
        });
      }
    } catch (e) {
      _snack('${tr('ফাইল পাঠানো যায়নি')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- মেসেজ এডিট / ডিলিট ----------
  Future<void> _msgMenu(List<MsgDoc> docs, int i) async {
    final d = docs[i];
    final m = d.data();
    final mine = m['senderId'] == me.uid;
    final isText = (m['type'] ?? 'text') == 'text';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isText)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(tr('কপি করুন')),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (mine && isText)
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(tr('মেসেজ এডিট করুন')),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(tr('মেসেজ মুছুন'),
                    style: const TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final isLatest = i == 0;
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: (m['text'] ?? '').toString()));
        _snack(tr('কপি হয়েছে'));
      } else if (action == 'edit') {
        final c = TextEditingController(text: (m['text'] ?? '').toString());
        final res = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('মেসেজ এডিট করুন')),
            content: TextField(
              controller: c,
              autofocus: true,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('বাতিল'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, c.text.trim()),
                  child: Text(tr('সেভ করুন'))),
            ],
          ),
        );
        if (res == null || res.isEmpty || res == m['text']) return;
        await d.reference.update({'text': res, 'edited': true});
        if (isLatest) {
          await _chatRef.update(previewOf({'type': 'text', 'text': res}));
        }
      } else if (action == 'delete') {
        final yes = await confirmDialog(
            context,
            tr('মেসেজ মুছুন'),
            tr('মেসেজটা সবার জন্য মুছে যাবে।'),
            tr('ডিলিট করুন'));
        if (!yes) return;
        await d.reference.delete();
        if (isLatest) {
          final prev = docs.length > 1 ? docs[1].data() : null;
          await _chatRef.update(previewOf(prev));
        }
      }
    } catch (e) {
      _snack('${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  // ---------- ভয়েস মেসেজ ----------
  Future<void> _startRec() async {
    if (_recording || _starting) return;
    _starting = true;
    try {
      if (!await _rec.hasPermission()) {
        _snack(tr('মাইক্রোফোনের অনুমতি দিন (ফোনের সেটিংস থেকেও দেওয়া যায়)'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recPath = path;
      if (!mounted) return;
      setState(() {
        _recording = true;
        _secs = 0;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _secs++);
        if (_secs >= 60) _stopRec(send: true);
      });
    } catch (e) {
      _snack('${tr('রেকর্ড শুরু করা যায়নি')}: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopRec({required bool send}) async {
    if (!_recording) return;
    _timer?.cancel();
    final secs = _secs;
    setState(() => _recording = false);
    try {
      final stopped = await _rec.stop();
      final p = stopped ?? _recPath;
      if (p == null) return;
      final f = File(p);
      if (send && secs >= 1) {
        final bytes = await f.readAsBytes();
        if (bytes.length > kMaxBytes) {
          _snack(tr('ভয়েস মেসেজ বেশি বড় হয়ে গেছে'));
        } else {
          await _post({
            'type': 'voice',
            'audio': base64Encode(bytes),
            'duration': secs,
          });
        }
      } else if (send) {
        _snack(tr('আরেকটু বেশি সময় ধরে বলুন'));
      }
      if (await f.exists()) await f.delete();
    } catch (e) {
      _snack('${tr('ভয়েস মেসেজ পাঠানো যায়নি')}: $e');
    }
  }

  Widget _inputBar() {
    if (_recording) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: tr('বাতিল'),
            onPressed: () => _stopRec(send: false),
          ),
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Text('${tr('রেকর্ড হচ্ছে')}  ${clock(_secs)}',
              style: const TextStyle(fontSize: 16)),
          const Spacer(),
          CircleAvatar(
            backgroundColor: kGreen,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              tooltip: tr('পাঠান'),
              onPressed: () => _stopRec(send: true),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.attach_file, color: kGreen),
          onPressed: _busy ? null : _attach,
        ),
        Expanded(
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: tr('মেসেজ লিখুন'),
              filled: true,
              fillColor: const Color(0xFFF0F0F0),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 6),
        CircleAvatar(
          backgroundColor: kGreen,
          child: IconButton(
            icon: Icon(_hasText ? Icons.send : Icons.mic, color: Colors.white),
            tooltip:
                _hasText ? tr('পাঠান') : tr('ভয়েস মেসেজ রেকর্ড করুন'),
            onPressed: _hasText ? _send : _startRec,
          ),
        ),
      ],
    );
  }

  Widget _content(Map<String, dynamic> m, String id) {
    switch (m['type']) {
      case 'voice':
        return VoiceBubble(
          key: ValueKey(id),
          audio: (m['audio'] ?? '').toString(),
          duration: (m['duration'] as num?)?.toInt() ?? 0,
        );
      case 'image':
        return ImageBubble(
            key: ValueKey(id), data: (m['image'] ?? '').toString());
      case 'file':
        return FileBubble(
          key: ValueKey(id),
          data: (m['fileData'] ?? '').toString(),
          name: (m['fileName'] ?? 'file').toString(),
          size: (m['size'] as num?)?.toInt() ?? 0,
        );
      default:
        return Text((m['text'] ?? '').toString(),
            style: const TextStyle(fontSize: 16));
    }
  }

  DateTime _dt(Map<String, dynamic> m) =>
      (m['time'] as Timestamp?)?.toDate() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgs
                  .orderBy('time', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text('${tr('ত্রুটি')}: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final mine = m['senderId'] == me.uid;
                    final d = _dt(m);
                    final showDate =
                        i == docs.length - 1 || !sameDay(d, _dt(docs[i + 1].data()));
                    final edited = m['edited'] == true;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white70,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(dayLabel(d),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black87)),
                            ),
                          ),
                        Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _msgMenu(docs, i),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: mine
                                    ? const Color(0xFFDCF8C6)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _content(m, docs[i].id),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${edited ? '${tr('সম্পাদিত')} · ' : ''}${hhmm(d)}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: _inputBar(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- ছবির মেসেজ ----------------
class ImageBubble extends StatefulWidget {
  final String data;
  const ImageBubble({super.key, required this.data});

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    try {
      _bytes = base64Decode(widget.data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return Text(tr('ছবি দেখা যাচ্ছে না'));
    }
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewPage(bytes: b)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 300),
          child: Image.memory(
            b,
            width: 220,
            fit: BoxFit.cover,
            cacheWidth: 600,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class ImageViewPage extends StatelessWidget {
  final Uint8List bytes;
  const ImageViewPage({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

// ---------------- ফাইলের মেসেজ ----------------
class FileBubble extends StatelessWidget {
  final String data;
  final String name;
  final int size;
  const FileBubble(
      {super.key, required this.data, required this.name, required this.size});

  Future<void> _open(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final folder =
          Directory('${dir.path}/f${DateTime.now().microsecondsSinceEpoch}');
      await folder.create(recursive: true);
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final f = File('${folder.path}/$safe');
      await f.writeAsBytes(base64Decode(data));
      final r = await OpenFilex.open(f.path);
      if (r.type != ResultType.done && context.mounted) {
        toast(context, '${tr('ফাইল খোলা যায়নি')}: ${r.message}');
      }
    } catch (e) {
      if (context.mounted) toast(context, '${tr('ফাইল খোলা যায়নি')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = size < 1024 ? '1' : (size / 1024).toStringAsFixed(0);
    return InkWell(
      onTap: () => _open(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 36, color: kGreen),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15)),
                Text(numL('$kb KB'),
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- ভয়েস মেসেজ প্লেয়ার ----------------
class VoiceBubble extends StatefulWidget {
  final String audio;
  final int duration;
  const VoiceBubble({super.key, required this.audio, required this.duration});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  StreamSubscription? _sub;
  bool _playing = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _sub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.stop();
        return;
      }
      if (_path == null) {
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/play_${DateTime.now().microsecondsSinceEpoch}.m4a');
        await f.writeAsBytes(base64Decode(widget.audio));
        _path = f.path;
      }
      await _player.play(DeviceFileSource(_path!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('চালানো যায়নি')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          iconSize: 38,
          color: kGreen,
          icon: Icon(_playing ? Icons.stop_circle : Icons.play_circle_fill),
          onPressed: _toggle,
        ),
        const SizedBox(width: 8),
        const Icon(Icons.graphic_eq, color: Colors.black45),
        const SizedBox(width: 8),
        Text(clock(widget.duration), style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
