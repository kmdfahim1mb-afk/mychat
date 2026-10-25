import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

const kGreen = Color(0xFF075E54);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const MyChatApp());
}

class MyChatApp extends StatelessWidget {
  const MyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyChat',
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
          return snap.hasData ? const UsersPage() : const AuthPage();
        },
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
      _msg('সব ঘর পূরণ করুন');
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
            .set({'uid': cred.user!.uid, 'name': name, 'email': email});
      }
    } on FirebaseAuthException catch (e) {
      _msg(e.message ?? 'কিছু একটা ভুল হয়েছে');
    } catch (e) {
      _msg('ত্রুটি: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _msg(String t) {
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
                const Icon(Icons.chat, size: 72, color: kGreen),
                const SizedBox(height: 8),
                const Text('MyChat',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kGreen)),
                const SizedBox(height: 24),
                if (!_isLogin)
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'আপনার নাম', border: OutlineInputBorder()),
                  ),
                if (!_isLogin) const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'ইমেইল', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)',
                      border: OutlineInputBorder()),
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
                        : Text(_isLogin ? 'লগইন' : 'সাইন-আপ'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? 'নতুন অ্যাকাউন্ট খুলুন'
                      : 'আগেই অ্যাকাউন্ট আছে? লগইন করুন'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- ইউজার তালিকা ----------------
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'লগআউট',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('ত্রুটি: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .where((u) => u['uid'] != me.uid)
              .toList();
          if (users.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'এখনো কেউ নেই।\nআরেকটা অ্যাকাউন্ট খুললে এখানে দেখা যাবে।',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = users[i];
              final name = (u['name'] ?? '?').toString();
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: kGreen,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white)),
                ),
                title: Text(name),
                subtitle: Text((u['email'] ?? '').toString()),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                        otherUid: u['uid'].toString(), otherName: name),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- চ্যাট স্ক্রিন ----------------
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

  String get chatId {
    final ids = [me.uid, widget.otherUid]..sort();
    return ids.join('_');
  }

  CollectionReference get _msgs => FirebaseFirestore.instance
      .collection('chats')
      .doc(chatId)
      .collection('messages');

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await _msgs.add({
      'text': t,
      'senderId': me.uid,
      'time': FieldValue.serverTimestamp(),
    });
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _msgs.orderBy('time', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('ত্রুটি: ${snap.error}'));
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
                    final m = docs[i].data() as Map<String, dynamic>;
                    final mine = m['senderId'] == me.uid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFFDCF8C6) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text((m['text'] ?? '').toString(),
                                style: const TextStyle(fontSize: 16)),
                            Text(_fmt(m['time'] as Timestamp?),
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black54)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'মেসেজ লিখুন',
                        filled: true,
                        fillColor: const Color(0xFFF0F0F0),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
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
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
