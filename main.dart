import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// অ্যাপের নাম বদলাতে শুধু নিচের লাইনের নামটা বদলান (ইংরেজি অক্ষরে লিখুন)
const kAppName = 'Alap';

/// কলের পুশ পাঠানোর Cloudflare Worker-এর ঠিকানা। খালি থাকলে অ্যাপ বন্ধ অবস্থায় কল বাজবে না।
const kCallWorkerUrl = 'https://raspy-surf-cfe5.kmdfahim1mb.workers.dev';


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
          trailing: isBn ? Icon(Icons.check, color: brand(ctx)) : null,
          onTap: () => Navigator.pop(ctx, 'bn'),
        ),
        ListTile(
          title: const Text('English'),
          trailing: !isBn ? Icon(Icons.check, color: brand(ctx)) : null,
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
  'অ্যাকাউন্ট সেটিংস': 'Account settings',
  'নাম পরিবর্তন': 'Change name',
  'নতুন নাম': 'New name',
  'নাম বদলানো হয়েছে': 'Name updated',
  'ইমেইল পরিবর্তন': 'Change email',
  'নতুন ইমেইল': 'New email',
  'বর্তমান পাসওয়ার্ড': 'Current password',
  'নতুন ইমেইলে একটা ভেরিফিকেশন লিংক পাঠানো হয়েছে। লিংকে ট্যাপ করলে ইমেইল বদলে যাবে, তারপর নতুন ইমেইল দিয়ে আবার লগইন করুন।':
      'A verification link was sent to the new email. Tap the link to change your email, then log in again with the new email.',
  'ঠিক আছে': 'OK',
  'রিংটোন': 'Ringtone',
  'ক্লাসিক': 'Classic',
  'নরম ঘণ্টা': 'Soft chime',
  'ডিজিটাল বিপ': 'Digital beep',
  'ক্রমশ উঁচু': 'Rising tone',
  'ফোন থেকে বাছুন': 'Pick from phone',
  'নিজের বাছাই করা অডিও': 'My own audio',
  'অডিও বাছা যায়নি': 'Could not pick the audio',
  'অ্যাপ খোলা থাকলে এই রিংটোন বাজবে। অ্যাপ বন্ধ থাকলে ফোনের সেটিংসের (অ্যাপস > Alap > নোটিফিকেশন > Calls > সাউন্ড) রিংটোন বাজবে।':
      'This ringtone plays while the app is open. When the app is closed, the sound set in phone settings (Apps > Alap > Notifications > Calls > Sound) plays.',
  'ছবি সেভ করুন': 'Save image',
  'ছবি গ্যালারিতে সেভ হয়েছে': 'Image saved to gallery',
  'ছবি সেভ করা যায়নি': 'Could not save the image',
  'নতুন গ্রুপ': 'New group',
  'গ্রুপের নাম': 'Group name',
  'গ্রুপ তৈরি করুন': 'Create group',
  'গ্রুপে কাদের নেবেন বেছে নিন (সর্বোচ্চ ১৯ জন)': 'Choose who to add (up to 19 people)',
  'গ্রুপের নাম লিখুন': 'Enter a group name',
  'কমপক্ষে একজনকে বেছে নিন': 'Choose at least one person',
  'সর্বোচ্চ ১৯ জনকে নেওয়া যায়': 'You can add up to 19 people',
  'এখনো কোনো গ্রুপ নেই': 'No groups yet',
  'বন্ধুদের নিয়ে গ্রুপ খুলে একসাথে চ্যাট করুন।': 'Create a group and chat with your friends together.',
  'গ্রুপ': 'Groups',
  'গ্রুপ চ্যাট': 'Group chat',
  'জন সদস্য': 'members',
  'গ্রুপের তথ্য': 'Group info',
  'সদস্য': 'Members',
  'অ্যাডমিন': 'Admin',
  'সদস্য যোগ করুন': 'Add members',
  'যোগ করুন': 'Add',
  'যোগ করার মতো কোনো ফ্রেন্ড নেই': 'No friends left to add',
  'গ্রুপ ছেড়ে যান': 'Leave group',
  'গ্রুপটা ছেড়ে গেলে আর মেসেজ দেখতে পাবেন না।': 'If you leave, you will no longer see messages.',
  'ছেড়ে যান': 'Leave',
  'গ্রুপ মুছে ফেলুন': 'Delete group',
  'গ্রুপ ও সব মেসেজ সবার জন্য মুছে যাবে।': 'The group and all messages will be deleted for everyone.',
  'গ্রুপের নাম বদলান': 'Rename group',
  'সদস্যকে বাদ দিন': 'Remove member',
  'গ্রুপ কলে সর্বোচ্চ ৫ জন থাকতে পারে': 'A group call can have at most 5 people',
  'গ্রুপ কলের জন্য বন্ধু বেছে নিন': 'Pick friends for a group call',
  'আপনি': 'You',
  'গ্রুপ কল': 'Group call',
  'রিং হচ্ছে…': 'Ringing…',
  'সংযুক্ত': 'Connected',
  'সংযোগ হয়নি': 'Could not connect',
  'আপনাকে গ্রুপ কলে ডাকছে': 'is inviting you to a group call',
  'গ্রুপ কলে কাদের ডাকবেন বেছে নিন (সর্বোচ্চ ৪ জন)':
      'Choose who to call (up to 4 people)',
  'গ্রুপ কল শুরু করুন': 'Start group call',
  'গ্রুপ কল করতে আগে কিছু ফ্রেন্ড যোগ করুন।':
      'Add some friends first to start a group call.',
  'সর্বোচ্চ ৪ জনকে ডাকা যায়': 'You can call up to 4 people',
  'পাসওয়ার্ড ভুলে গেছেন?': 'Forgot password?',
  'পাসওয়ার্ড রিসেট': 'Reset password',
  'আপনার ইমেইল দিন। সেখানে পাসওয়ার্ড বদলানোর লিংক পাঠানো হবে।':
      'Enter your email. A link to reset your password will be sent there.',
  'লিংক পাঠান': 'Send link',
  'রিসেট লিংক পাঠানো হয়েছে। ইমেইল (স্প্যাম ফোল্ডারও) দেখুন।':
      'Reset link sent. Check your email (and spam folder).',
  'পাসওয়ার্ড পরিবর্তন': 'Change password',
  'নতুন পাসওয়ার্ড': 'New password',
  'নতুন পাসওয়ার্ড আবার লিখুন': 'Confirm new password',
  'দুইবারের নতুন পাসওয়ার্ড মেলেনি': 'The new passwords do not match',
  'পাসওয়ার্ড বদলানো হয়েছে': 'Password changed',
  'অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।':
      'Too many attempts. Please try again later.',
  'থিম': 'Theme',
  'রঙ': 'Color',
  'সিস্টেম': 'System',
  'লাইট': 'Light',
  'ডার্ক': 'Dark',
  'ডিলিট করলে বিপ সাউন্ড': 'Beep sound on delete',
  'ভাষা': 'Language',
  'ভয়েস কল': 'Voice call',
  'ভয়েস কল আসছে': 'Incoming voice call',
  'কল করা হচ্ছে…': 'Calling…',
  'সংযুক্ত হচ্ছে…': 'Connecting…',
  'কল শেষ': 'Call ended',
  'কল করা যায়নি': 'Could not start the call',
  'মিসড কল': 'Missed call',
  'কল ফিরিয়ে দেওয়া হয়েছে': 'Call declined',
  'অন্য একটা কল চলছে': 'Another call is in progress',
  'মিউট': 'Mute',
  'স্পিকার': 'Speaker',
  'কল ধরুন': 'Answer',
  'কল কাটুন': 'End call',
  'প্রোফাইল': 'Profile',
  'চ্যাট': 'Chats',
  'কন্টাক্ট': 'Contacts',
  'সেটিংস': 'Settings',
  'আর কোনো চ্যাট নেই': 'No more chats yet',
  'বন্ধুদের সাথে কথোপকথন শুরু করুন': 'Start a conversation with your friends',
  'কন্টাক্ট খুঁজুন': 'Find Contacts',
  'এখনো কোনো ফ্রেন্ড নেই': 'No friends yet',
  'সার্চ করে ফ্রেন্ড রিকোয়েস্ট পাঠান': 'Search and send a friend request',
  'গ্রুপ চ্যাট শীঘ্রই আসছে': 'Group chats are coming soon',
  'গ্রুপ চ্যাটের ফিচার এখনো তৈরি হয়নি, পরে যোগ হবে।':
      'Group chat is not built yet and will be added later.',
  'সব চ্যাট': 'All chats',
  'শুধু ফ্রেন্ড': 'Friends only',
  'ফিল্টার': 'Filter',
  'নতুন চ্যাট': 'New chat',
};

// ---------------- থিম (রঙ), সাউন্ড ----------------
const kDefaultGreen = Color(0xFF075E54);

final ValueNotifier<int> themeSeed = ValueNotifier<int>(0xFF075E54);
final ValueNotifier<String> themeModeN = ValueNotifier<String>('system');
final ValueNotifier<bool> deleteSoundOn = ValueNotifier<bool>(true);
final ValueNotifier<String> ringToneN = ValueNotifier<String>('classic');
String ringCustomPath = '';

const kThemeColors = <int>[
  0xFF075E54, // সবুজ
  0xFF1565C0, // নীল
  0xFF6A1B9A, // বেগুনি
  0xFFE65100, // কমলা
  0xFFC62828, // লাল
  0xFFAD1457, // গোলাপি
  0xFF00695C, // টিল
  0xFF37474F, // ধূসর
];

/// অ্যাপের মূল রঙ (থিম থেকে নেয়, তাই রঙ বদলালে নিজে বদলে যায়)
Color brand(BuildContext c) =>
    Theme.of(c).appBarTheme.backgroundColor ?? kDefaultGreen;

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Future<void> savePref(String key, Object value) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (value is String) await p.setString(key, value);
    if (value is int) await p.setInt(key, value);
    if (value is bool) await p.setBool(key, value);
  } catch (_) {}
}

Future<void> setThemeColor(int c) async {
  themeSeed.value = c;
  await savePref('themeSeed', c);
}

Future<void> setThemeMode(String m) async {
  themeModeN.value = m;
  await savePref('themeMode', m);
}

Future<void> setRingTone(String k) async {
  ringToneN.value = k;
  await savePref('ringTone', k);
}

Future<void> setDeleteSound(bool v) async {
  deleteSoundOn.value = v;
  await savePref('deleteSound', v);
}

/// সহজ টোন (WAV) বানায়। প্রতিটা অংশ: [শুরুর ফ্রিকোয়েন্সি, শেষের ফ্রিকোয়েন্সি, সেকেন্ড, জোর]
/// ফ্রিকোয়েন্সি 0 মানে নীরবতা।
Uint8List makeWav(List<List<double>> parts) {
  const rate = 22050;
  final counts = [for (final p in parts) (rate * p[2]).round()];
  final total = counts.fold<int>(0, (a, b) => a + b);
  final data = ByteData(44 + total * 2);
  void str(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + total * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, total * 2, Endian.little);

  var pos = 44;
  for (var k = 0; k < parts.length; k++) {
    final f1 = parts[k][0];
    final f2 = parts[k][1];
    final vol = parts[k][3];
    final n = counts[k];
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = n <= 1 ? 0.0 : i / (n - 1);
      final f = f1 + (f2 - f1) * t;
      phase += 2 * math.pi * f / rate;
      final att = math.min(1.0, i / (rate * 0.01));
      final rel = math.min(1.0, (n - i) / (rate * 0.03));
      final v = (f1 == 0 && f2 == 0) ? 0.0 : math.sin(phase) * vol * att * rel;
      data.setInt16(pos, (v * 32767).round(), Endian.little);
      pos += 2;
    }
  }
  return data.buffer.asUint8List();
}

Future<String> _wavFile(String name, List<List<double>> parts) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  if (!await f.exists()) await f.writeAsBytes(makeWav(parts));
  return f.path;
}

/// এখন কোনো কল চলছে কি না
bool inCall = false;

String? _beepPath;
AudioPlayer? _ringPlayer;

/// ডিলিট করলে ছোট্ট একটা নরম "বিপ" (নিচের দিকে নামা টোন, বাদ্যযন্ত্রের মতো নয়)
Future<void> playDeleteBeep() async {
  if (!deleteSoundOn.value) return;
  try {
    HapticFeedback.mediumImpact();
    _beepPath ??= await _wavFile('alap_delete_v1.wav', [
      [950, 480, 0.13, 0.35]
    ]);
    final p = AudioPlayer();
    p.onPlayerComplete.first.then((_) => p.dispose());
    await p.play(DeviceFileSource(_beepPath!));
  } catch (_) {}
}

/// কলের রিং (ফোনের মতো দুই বিপ, থেমে থেমে)
/// রিংটোনের ধরন (নাম -> [শুরুর হার্জ, শেষের হার্জ, সময়, জোর])
const kRingTones = <String, List<List<double>>>{
  'classic': [
    [425, 425, 0.4, 0.25],
    [0, 0, 0.2, 0],
    [425, 425, 0.4, 0.25],
    [0, 0, 1.8, 0],
  ],
  'soft': [
    [660, 660, 0.25, 0.3],
    [0, 0, 0.05, 0],
    [880, 880, 0.35, 0.3],
    [0, 0, 1.6, 0],
  ],
  'digital': [
    [1000, 1000, 0.12, 0.3],
    [0, 0, 0.08, 0],
    [1000, 1000, 0.12, 0.3],
    [0, 0, 0.08, 0],
    [1000, 1000, 0.12, 0.3],
    [0, 0, 0.08, 0],
    [1000, 1000, 0.12, 0.3],
    [0, 0, 1.3, 0],
  ],
  'rising': [
    [500, 900, 0.5, 0.3],
    [0, 0, 0.1, 0],
    [500, 900, 0.5, 0.3],
    [0, 0, 1.5, 0],
  ],
};

Future<String> _ringFileFor(String key) async {
  if (key == 'custom') {
    if (ringCustomPath.isNotEmpty && await File(ringCustomPath).exists()) {
      return ringCustomPath;
    }
    key = 'classic';
  }
  final parts = kRingTones[key] ?? kRingTones['classic']!;
  return _wavFile('alap_ring_${key}_v1.wav', parts);
}

/// কলের রিং। incoming = true হলে (কল আসছে) নিজের বাছাই করা রিংটোন বাজে,
/// নইলে (আমি কল করছি) সাধারণ রিংব্যাক টোন।
Future<void> startRing({bool incoming = false}) async {
  try {
    await stopRing();
    final path = await _ringFileFor(incoming ? ringToneN.value : 'classic');
    final p = AudioPlayer();
    _ringPlayer = p;
    await p.setReleaseMode(ReleaseMode.loop);
    await p.play(DeviceFileSource(path));
  } catch (_) {}
}

/// সেটিংসে রিংটোন শুনে দেখা (কয়েক সেকেন্ড বাজে)
Future<void> previewRingTone(String key) async {
  if (inCall) return;
  try {
    await stopRing();
    final path = await _ringFileFor(key);
    final p = AudioPlayer();
    _ringPlayer = p;
    await p.setReleaseMode(ReleaseMode.loop);
    await p.play(DeviceFileSource(path));
    Future.delayed(const Duration(seconds: 5), () {
      if (identical(_ringPlayer, p) && !inCall) stopRing();
    });
  } catch (_) {}
}

Future<void> stopRing() async {
  final p = _ringPlayer;
  _ringPlayer = null;
  if (p != null) {
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}

// ---------------- সাধারণ সাহায্যকারী ফাংশন ----------------

// ---------------- অ্যাপ বন্ধ থাকলেও কল (পুশ নোটিফিকেশন) ----------------
final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();
const int kCallNotifId = 7001;
bool _lnReady = false;

Future<void> initNotifications() async {
  if (_lnReady) return;
  await _ln.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final android = _ln.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    'calls_v1',
    'Calls',
    description: 'Incoming call alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  ));
  _lnReady = true;
}

Future<void> showCallNotification(Map<String, dynamic> data) async {
  await initNotifications();
  final name = (data['name'] ?? '?').toString();
  final group = data['kind'] == 'group';
  await _ln.show(
    id: kCallNotifId,
    title: name,
    body: group ? 'Incoming group call' : 'Incoming voice call',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'calls_v1',
        'Calls',
        channelDescription: 'Incoming call alerts',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: true,
        timeoutAfter: 45000,
        visibility: NotificationVisibility.public,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 600, 800, 600, 800]),
        additionalFlags: Int32List.fromList([4]), // বারবার বাজবে
      ),
    ),
  );
}

Future<void> cancelCallNotification() async {
  try {
    await _ln.cancel(id: kCallNotifId);
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> fcmBackground(RemoteMessage m) async {
  if (m.data['type'] == 'call') {
    await showCallNotification(Map<String, dynamic>.from(m.data));
  }
}

bool _tokenWatching = false;

/// এই ফোনের পুশ-টোকেন নিজের ইউজারের নামে জমা রাখে (সার্ভার এটা দিয়ে ফোন বাজায়)
Future<void> registerPushToken() async {
  try {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final msg = FirebaseMessaging.instance;
    await msg.requestPermission();
    final android = _ln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
    final t = await msg.getToken();
    if (t != null) {
      await FirebaseFirestore.instance
          .collection('pushTokens')
          .doc(u.uid)
          .set({'token': t, 'time': FieldValue.serverTimestamp()});
    }
    if (!_tokenWatching) {
      _tokenWatching = true;
      msg.onTokenRefresh.listen((nt) {
        final cu = FirebaseAuth.instance.currentUser;
        if (cu == null) return;
        FirebaseFirestore.instance
            .collection('pushTokens')
            .doc(cu.uid)
            .set({'token': nt, 'time': FieldValue.serverTimestamp()}).catchError(
                (_) {});
      });
    }
  } catch (_) {}
}

Future<void> signOutClean() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u != null) {
    try {
      await FirebaseFirestore.instance
          .collection('pushTokens')
          .doc(u.uid)
          .delete();
    } catch (_) {}
  }
  await FirebaseAuth.instance.signOut();
}

/// কল শুরু হলে সার্ভারকে বলে ফোন বাজাতে (type: call | group)
Future<void> pushRing(String type, String id) async {
  if (kCallWorkerUrl.isEmpty) return;
  try {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final idToken = await u.getIdToken();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final r = await c.postUrl(Uri.parse(kCallWorkerUrl));
    r.headers.contentType = ContentType.json;
    r.add(utf8.encode(jsonEncode({'idToken': idToken, 'type': type, 'id': id})));
    final resp = await r.close().timeout(const Duration(seconds: 10));
    await resp.drain();
    c.close();
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final p = await SharedPreferences.getInstance();
    appLang.value = p.getString('lang') ?? 'bn';
    themeSeed.value = p.getInt('themeSeed') ?? 0xFF075E54;
    themeModeN.value = p.getString('themeMode') ?? 'system';
    deleteSoundOn.value = p.getBool('deleteSound') ?? true;
    ringToneN.value = p.getString('ringTone') ?? 'classic';
    ringCustomPath = p.getString('ringCustom') ?? '';
  } catch (_) {}
  await Firebase.initializeApp(options: firebaseOptions);
  try {
    FirebaseMessaging.onBackgroundMessage(fcmBackground);
    await initNotifications();
  } catch (_) {}
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
    case 'too-many-requests':
      return tr('অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।');
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
    case 'call':
      return {'lastType': 'call', 'lastText': ''};
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
    case 'call':
      return '📞 ${tr('ভয়েস কল')}';
    default:
      return text;
  }
}

IconData? previewIcon(Map<String, dynamic> chat) {
  switch (chat['lastType']) {
    case 'voice':
      return Icons.mic;
    case 'image':
      return Icons.photo;
    case 'file':
      return Icons.attach_file;
    case 'call':
      return Icons.call;
    default:
      return null;
  }
}

String previewText(Map<String, dynamic> chat) {
  final text = (chat['lastText'] ?? '').toString();
  switch (chat['lastType']) {
    case 'voice':
      return tr('ভয়েস মেসেজ');
    case 'image':
      return tr('ছবি');
    case 'call':
      return tr('ভয়েস কল');
    default:
      return text;
  }
}

/// চ্যাটে মেসেজ পাঠায় এবং চ্যাট তালিকা আপডেট করে
Future<void> postGroupMessage(String gid, Map<String, dynamic> msg) async {
  final me = FirebaseAuth.instance.currentUser!;
  final g = FirebaseFirestore.instance.collection('groups').doc(gid);
  final a = g.update({
    ...previewOf(msg),
    'lastTime': FieldValue.serverTimestamp(),
    'lastSender': me.uid,
    'lastName': myName,
  });
  final b = g.collection('messages').add({
    ...msg,
    'senderId': me.uid,
    'senderName': myName,
    'time': FieldValue.serverTimestamp(),
  });
  await Future.wait([a, b]);
}

Future<void> postMessage(
    String otherUid, String otherName, Map<String, dynamic> msg) async {
  final me = FirebaseAuth.instance.currentUser!;
  final chat =
      FirebaseFirestore.instance.collection('chats').doc(pairId(me.uid, otherUid));
  final a = chat.set({
    'members': [me.uid, otherUid],
    'names': {me.uid: myName, otherUid: otherName},
    ...previewOf(msg),
    'lastTime': FieldValue.serverTimestamp(),
    'lastSender': me.uid,
    'hiddenBy': <String>[],
  }, SetOptions(merge: true));
  final b = chat.collection('messages').add({
    ...msg,
    'senderId': me.uid,
    'time': FieldValue.serverTimestamp(),
  });
  await Future.wait([a, b]);
}

// ---------------- অ্যাপ ----------------
class MyChatApp extends StatelessWidget {
  const MyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([appLang, themeSeed, themeModeN]),
      builder: (context, _) {
        final seed = Color(themeSeed.value);
        ThemeData mk(Brightness b) => ThemeData(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: seed, brightness: b),
              appBarTheme: AppBarTheme(
                backgroundColor: seed,
                foregroundColor: Colors.white,
              ),
              useMaterial3: true,
            );
        final mode = themeModeN.value == 'dark'
            ? ThemeMode.dark
            : (themeModeN.value == 'light' ? ThemeMode.light : ThemeMode.system);
        return MaterialApp(
        key: ValueKey(appLang.value),
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: mk(Brightness.light),
        darkTheme: mk(Brightness.dark),
        themeMode: mode,
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
        );
      },
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

  Future<void> _forgot() async {
    final c = TextEditingController(text: _email.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('পাসওয়ার্ড রিসেট')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('আপনার ইমেইল দিন। সেখানে পাসওয়ার্ড বদলানোর লিংক পাঠানো হবে।')),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: tr('ইমেইল'), border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('বাতিল'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('লিংক পাঠান'))),
        ],
      ),
    );
    if (ok != true) return;
    final email = c.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _msg(tr('ইমেইলটা সঠিক নয়'));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _msg(tr('রিসেট লিংক পাঠানো হয়েছে। ইমেইল (স্প্যাম ফোল্ডারও) দেখুন।'));
    } on FirebaseAuthException catch (e) {
      _msg(authMsg(e));
    } catch (e) {
      _msg('${tr('ত্রুটি')}: $e');
    }
  }

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
                Image.asset(
                  'icon.png',
                  width: 150,
                  height: 150,
                  errorBuilder: (_, __, ___) => Column(
                    children: [
                      Icon(Icons.chat, size: 72, color: brand(context)),
                      Text(kAppName,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: brand(context))),
                    ],
                  ),
                ),
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
                if (_isLogin)
                  TextButton(
                    onPressed: _forgot,
                    child: Text(tr('পাসওয়ার্ড ভুলে গেছেন?')),
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
  var deleted = false;
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
    await db.collection('pushTokens').doc(uid).delete().catchError((_) {});
    await user.delete();
    deleted = true;
    playDeleteBeep();
    messenger
        .showSnackBar(SnackBar(content: Text(tr('অ্যাকাউন্ট ডিলিট হয়েছে'))));
  } on FirebaseAuthException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(authMsg(e))));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('${tr('ডিলিট করা যায়নি')}: $e')));
  } finally {
    if (deleted) {
      nav.popUntil((r) => r.isFirst);
    } else {
      nav.pop();
    }
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
  IconData? icon;
  Timestamp? time;
  bool chat;
  bool friend;
  _Entry(this.uid, this.name,
      {this.lastText = '',
      this.icon,
      this.time,
      this.chat = false,
      this.friend = false});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final me = FirebaseAuth.instance.currentUser!;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  int _tab = 0; // 0 চ্যাট, 1 কন্টাক্ট, 2 গ্রুপ, 3 সেটিংস
  String _filter = 'all'; // all | friends
  final List<StreamSubscription> _subs = [];
  Timer? _debounce;
  int _token = 0;

  Map<String, Map<String, dynamic>> _chats = {}; // অন্যজনের uid -> চ্যাট ডেটা
  Map<String, String> _friends = {}; // ফ্রেন্ডের uid -> নাম
  Set<String> _outgoing = {}; // যাদের রিকোয়েস্ট পাঠিয়েছি
  Set<String> _incoming = {}; // যারা আমাকে রিকোয়েস্ট পাঠিয়েছে
  List<Map<String, dynamic>> _groups = []; // আমার গ্রুপগুলো
  int _gMode = 0; // 0 গ্রুপ তালিকা, 1 গ্রুপ কল

  String _q = '';
  bool _searching = false;
  String? _searchErr;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    ensureProfile();
    registerPushToken();
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

    // আমার গ্রুপগুলো
    _subs.add(db
        .collection('groups')
        .where('members', arrayContains: me.uid)
        .snapshots()
        .listen((s) {
      final l = [
        for (final d in s.docs) {...d.data(), 'id': d.id}
      ];
      l.sort((a, b) {
        final ta = (a['lastTime'] as Timestamp?)?.millisecondsSinceEpoch ?? 1 << 50;
        final tb = (b['lastTime'] as Timestamp?)?.millisecondsSinceEpoch ?? 1 << 50;
        return tb.compareTo(ta);
      });
      if (mounted) setState(() => _groups = l);
    }, onError: onErr));

    // আসা ভয়েস কল (অ্যাপ খোলা থাকলে রিং হবে)
    _subs.add(db
        .collection('calls')
        .where('callee', isEqualTo: me.uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((s) {
      for (final c in s.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final d = c.doc.data();
        if (d == null) continue;
        final t = (d['time'] as Timestamp?)?.toDate();
        if (t != null && DateTime.now().difference(t).inSeconds > 90) continue;
        if (inCall) {
          c.doc.reference.update({'status': 'declined'}).catchError((_) {});
          continue;
        }
        if (!mounted) continue;
        inCall = true;
        cancelCallNotification();
        final session = CallSession.incoming(c.doc.id, d);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CallPage(session: session)),
        );
      }
    }, onError: (_) {}));

    // আসা গ্রুপ কল
    _subs.add(db
        .collection('groupCalls')
        .where('invited', arrayContains: me.uid)
        .snapshots()
        .listen((s) {
      for (final c in s.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final d = c.doc.data();
        if (d == null || d['status'] != 'active') continue;
        final t = (d['time'] as Timestamp?)?.toDate();
        if (t == null || DateTime.now().difference(t).inSeconds > 45) continue;
        final joined = List<String>.from(d['joined'] ?? const []);
        if (joined.contains(me.uid) || inCall) continue;
        if (!mounted) continue;
        inCall = true;
        cancelCallNotification();
        final call = GroupCall.incoming(c.doc.id, d);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupCallPage(call: call)),
        );
      }
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _debounce?.cancel();
    _searchFocus.dispose();
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

  Future<bool> _guard(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (ok != null) toast(context, ok);
      return true;
    } catch (e) {
      toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
      return false;
    }
  }

  // ---------- তালিকা ----------
  List<_Entry> _entries() {
    final map = <String, _Entry>{};
    _chats.forEach((uid, data) {
      final names = Map<String, dynamic>.from(data['names'] ?? {});
      map[uid] = _Entry(
        uid,
        (names[uid] ?? '?').toString(),
        lastText: previewText(data),
        icon: previewIcon(data),
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
    var list = map.values.toList();
    if (_filter == 'friends') list = list.where((e) => e.friend).toList();
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
      final done = await _guard(() => db.collection('chats').doc(id).update({
            'hiddenBy': FieldValue.arrayUnion([me.uid])
          }));
      if (done) playDeleteBeep();
    } else if (action == 'unfriend') {
      final yes = await confirmDialog(
          context,
          tr('ফ্রেন্ড থেকে বাদ দিন'),
          '${e.name} ${tr('কে ফ্রেন্ড তালিকা থেকে বাদ দেবেন?')}',
          tr('বাদ দিন'));
      if (yes && mounted) {
        final done =
            await _guard(() => db.collection('friendships').doc(id).delete());
        if (done) playDeleteBeep();
      }
    }
  }

  Future<void> _filterSheet() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inbox),
              title: Text(tr('সব চ্যাট')),
              trailing: _filter == 'all'
                  ? Icon(Icons.check, color: brand(ctx))
                  : null,
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(tr('শুধু ফ্রেন্ড')),
              trailing: _filter == 'friends'
                  ? Icon(Icons.check, color: brand(ctx))
                  : null,
              onTap: () => Navigator.pop(ctx, 'friends'),
            ),
          ],
        ),
      ),
    );
    if (r != null && mounted) setState(() => _filter = r);
  }

  // ---------- ডিজাইনের ছোট ছোট অংশ ----------
  Widget _avatar(String name, [double r = 20]) => CircleAvatar(
        radius: r,
        backgroundColor: brand(context),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(color: Colors.white, fontSize: r * 0.95)),
      );

  Widget _sub(IconData? icon, String text) {
    final hint = Theme.of(context).hintColor;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: hint),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: hint)),
        ),
      ],
    );
  }

  Widget _card({
    required Widget leading,
    required String title,
    required Widget subtitle,
    Widget? trailing,
    String time = '',
    VoidCallback? onTap,
    VoidCallback? onLong,
  }) {
    final hint = Theme.of(context).hintColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: isDark(context) ? const Color(0xFF1B262C) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onLong,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          if (time.isNotEmpty)
                            Text(time,
                                style: TextStyle(fontSize: 13, color: hint)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      subtitle,
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                trailing ?? Icon(Icons.chevron_right, color: hint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(
      {String? title, String? sub, bool button = true, int bottom = 24}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 28, 24, bottom.toDouble()),
      child: Column(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(painter: _BubblesPainter(brand(context))),
          ),
          const SizedBox(height: 16),
          Text(title ?? tr('আর কোনো চ্যাট নেই'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(sub ?? tr('বন্ধুদের সাথে কথোপকথন শুরু করুন'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, color: Theme.of(context).hintColor)),
          if (button) ...[
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: () => _searchFocus.requestFocus(),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr('কন্টাক্ট খুঁজুন')),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('ত্রুটি')}: $_error', textAlign: TextAlign.center),
        ),
      );

  Widget _chatList() {
    if (_error != null) return _errorView();
    final entries = _entries().where((e) => e.chat).toList();
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 100),
      children: [
        for (final e in entries)
          _card(
            leading: _avatar(e.name, 28),
            title: e.name,
            time: fmtTime(e.time),
            subtitle: _sub(e.icon, e.lastText),
            onTap: () => _openChat(e.uid, e.name),
            onLong: () => _manage(e),
          ),
        _emptyHint(),
      ],
    );
  }

  Widget _contactsList() {
    if (_error != null) return _errorView();
    final list = _friends.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    if (list.isEmpty) {
      return ListView(children: [
        _emptyHint(
            title: tr('এখনো কোনো ফ্রেন্ড নেই'),
            sub: tr('সার্চ করে ফ্রেন্ড রিকোয়েস্ট পাঠান')),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 100),
      children: [
        for (final f in list)
          _card(
            leading: _avatar(f.value, 28),
            title: f.value,
            subtitle: _sub(Icons.verified_user, tr('ফ্রেন্ড')),
            onTap: () => _openChat(f.key, f.value),
            onLong: () => _manage(_Entry(f.key, f.value,
                friend: true, chat: _chats.containsKey(f.key))),
          ),
      ],
    );
  }

  final Set<String> _gSel = {};

  void _startGroupCall() {
    if (_gSel.isEmpty) return;
    if (inCall) {
      toast(context, tr('অন্য একটা কল চলছে'));
      return;
    }
    final invited = <String, String>{
      for (final u in _gSel) u: _friends[u] ?? '?'
    };
    _gSel.clear();
    inCall = true;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => GroupCallPage(call: GroupCall.outgoing(invited))),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _groupsView() {
    final b = brand(context);
    Widget chip(int i, String label, IconData icon) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
            child: ChoiceChip(
              selected: _gMode == i,
              showCheckmark: false,
              avatar: Icon(icon,
                  size: 18, color: _gMode == i ? Colors.white : b),
              label: SizedBox(
                  width: double.infinity,
                  child: Text(label, textAlign: TextAlign.center)),
              labelStyle:
                  TextStyle(color: _gMode == i ? Colors.white : b),
              selectedColor: b,
              onSelected: (_) => setState(() => _gMode = i),
            ),
          ),
        );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            chip(0, tr('গ্রুপ চ্যাট'), Icons.forum),
            chip(1, tr('গ্রুপ কল'), Icons.call),
          ]),
        ),
        Expanded(child: _gMode == 0 ? _groupList() : _callPicker()),
      ],
    );
  }

  Widget _groupList() {
    if (_friends.isEmpty && _groups.isEmpty) {
      return ListView(children: [
        _emptyHint(
          title: tr('এখনো কোনো গ্রুপ নেই'),
          sub: tr('বন্ধুদের নিয়ে গ্রুপ খুলে একসাথে চ্যাট করুন।'),
          button: false,
        ),
      ]);
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            children: [
              for (final g in _groups)
                _card(
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundColor: brand(context),
                    child: const Icon(Icons.groups, color: Colors.white),
                  ),
                  title: (g['title'] ?? '').toString(),
                  time: fmtTime(g['lastTime'] as Timestamp?),
                  subtitle: _sub(
                      previewIcon(g),
                      ((g['lastName'] ?? '').toString().isEmpty
                              ? ''
                              : '${g['lastName']}: ') +
                          previewLabel(g)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatPage(
                            groupId: g['id'].toString(),
                            otherName: (g['title'] ?? '').toString())),
                  ),
                ),
              if (_groups.isEmpty)
                _emptyHint(
                  title: tr('এখনো কোনো গ্রুপ নেই'),
                  sub: tr('বন্ধুদের নিয়ে গ্রুপ খুলে একসাথে চ্যাট করুন।'),
                  button: false,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _friends.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CreateGroupPage(
                                friends: Map<String, String>.from(_friends))),
                      ),
              icon: const Icon(Icons.group_add),
              label: Text(tr('নতুন গ্রুপ')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _callPicker() {
    if (_friends.isEmpty) {
      return ListView(children: [
        _emptyHint(
          title: tr('গ্রুপ কল'),
          sub: tr('গ্রুপ কল করতে আগে কিছু ফ্রেন্ড যোগ করুন।'),
          button: false,
        ),
      ]);
    }
    final list = _friends.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(tr('গ্রুপ কলে কাদের ডাকবেন বেছে নিন (সর্বোচ্চ ৪ জন)'),
              style: TextStyle(color: Theme.of(context).hintColor)),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final f in list)
                CheckboxListTile(
                  value: _gSel.contains(f.key),
                  secondary: _avatar(f.value, 22),
                  title: Text(f.value),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        if (_gSel.length >= kGroupMax - 1) {
                          toast(context, tr('সর্বোচ্চ ৪ জনকে ডাকা যায়'));
                        } else {
                          _gSel.add(f.key);
                        }
                      } else {
                        _gSel.remove(f.key);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _gSel.isEmpty ? null : _startGroupCall,
              icon: const Icon(Icons.groups),
              label: Text(
                  '${tr('গ্রুপ কল শুরু করুন')} (${numL('${_gSel.length}')})'),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- সার্চ ফলাফল ----------
  Widget _action(String uid, String name) {
    if (_friends.containsKey(uid)) {
      return Text(tr('ফ্রেন্ড'),
          style: TextStyle(
              color: brand(context), fontWeight: FontWeight.bold));
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
      icon: Icon(Icons.person_add_alt_1, color: brand(context)),
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
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 100),
      children: [
        for (final u in _results)
          Builder(builder: (context) {
            final uid = (u['uid'] ?? '').toString();
            final name = (u['name'] ?? '?').toString();
            return _card(
              leading: _avatar(name, 28),
              title: name,
              subtitle: _sub(null, maskEmail((u['email'] ?? '').toString())),
              trailing: _action(uid, name),
              onTap: () => _openChat(uid, name), // সরাসরি মেসেজ পাঠানো যাবে
            );
          }),
      ],
    );
  }

  // ---------- উপরের অংশ (ঢেউ-ব্যাকগ্রাউন্ড, নাম, সার্চবার) ----------
  Widget _searchBar() {
    final dark = isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F2C34) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 18, right: 8),
            child: Icon(Icons.search, size: 28),
          ),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr('নাম বা পুরো ইমেইল দিয়ে খুঁজুন'),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          if (_q.isNotEmpty)
            IconButton(
                icon: const Icon(Icons.close), onPressed: _clearSearch),
          Container(
              width: 1, height: 30, color: Theme.of(context).dividerColor),
          IconButton(
            icon: Icon(Icons.tune,
                color: _filter == 'all' ? null : brand(context)),
            tooltip: tr('ফিল্টার'),
            onPressed: _filterSheet,
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final b = brand(context);
    final deep = Color.alphaBlend(Colors.black38, b);
    return Material(
      elevation: 6,
      color: Colors.transparent,
      shadowColor: Colors.black45,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [b, deep],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _WavePainter())),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 6, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const PlaneLogo(size: 40),
                        const SizedBox(width: 12),
                        const Text(kAppName,
                            style: TextStyle(
                                fontSize: 36,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: tr('ফ্রেন্ড রিকোয়েস্ট'),
                          icon: Badge.count(
                            count: _incoming.length,
                            isLabelVisible: _incoming.isNotEmpty,
                            child: const Icon(Icons.person_add_alt_1,
                                color: Colors.white, size: 30),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RequestsPage()),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white, size: 28),
                          onSelected: (v) {
                            if (v == 'settings') {
                              setState(() => _tab = 3);
                            } else if (v == 'lang') {
                              pickLanguage(context);
                            } else if (v == 'logout') {
                              signOutClean();
                            } else if (v == 'delete') {
                              deleteMyAccount(context);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'settings',
                              child: Row(children: [
                                const Icon(Icons.settings),
                                const SizedBox(width: 8),
                                Text(tr('অ্যাকাউন্ট সেটিংস')),
                              ]),
                            ),
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
                                const Icon(Icons.delete_forever,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Text(tr('অ্যাকাউন্ট ডিলিট করুন'),
                                    style: const TextStyle(color: Colors.red)),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _searchBar(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chips() {
    final icons = [Icons.chat_bubble, Icons.people, Icons.groups];
    final labels = [tr('চ্যাট'), tr('কন্টাক্ট'), tr('গ্রুপ')];
    final b = brand(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 46,
                    decoration: BoxDecoration(
                      color: _tab == i ? b : b.withAlpha(34),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i],
                            size: 20, color: _tab == i ? Colors.white : b),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _tab == i ? Colors.white : b)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.isNotEmpty;
    final Widget body;
    if (_tab == 3) {
      body = const SettingsPage(embedded: true);
    } else {
      body = Column(
        children: [
          _header(),
          if (!searching) _chips(),
          Expanded(
            child: searching
                ? _searchList()
                : (_tab == 0
                    ? _chatList()
                    : (_tab == 1 ? _contactsList() : _groupsView())),
          ),
        ],
      );
    }
    final b = brand(context);
    return Scaffold(
      backgroundColor:
          isDark(context) ? const Color(0xFF0E1417) : const Color(0xFFF2F7F6),
      body: body,
      floatingActionButton: (_tab == 0 && !searching)
          ? FloatingActionButton(
              onPressed: () => _searchFocus.requestFocus(),
              tooltip: tr('নতুন চ্যাট'),
              backgroundColor: b,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.edit),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: b.withAlpha(46),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: b),
            label: tr('চ্যাট'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: b),
            label: tr('কন্টাক্ট'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups, color: b),
            label: tr('গ্রুপ'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: b),
            label: tr('সেটিংস'),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p1 = Paint()..color = const Color(0x14FFFFFF);
    final path1 = Path()
      ..moveTo(s.width * 0.40, 0)
      ..quadraticBezierTo(
          s.width * 0.28, s.height * 0.55, s.width, s.height * 0.62)
      ..lineTo(s.width, 0)
      ..close();
    canvas.drawPath(path1, p1);
    final p2 = Paint()..color = const Color(0x0DFFFFFF);
    final path2 = Path()
      ..moveTo(0, s.height * 0.55)
      ..quadraticBezierTo(
          s.width * 0.35, s.height * 0.35, s.width * 0.7, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BubblesPainter extends CustomPainter {
  final Color color;
  _BubblesPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Rect r(double l, double t, double rr, double b) =>
        Rect.fromLTRB(l * w, t * h, rr * w, b * h);

    // পেছনের হালকা বাবল
    final backPaint = Paint()..color = color.withAlpha(45);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r(0.42, 0.36, 0.96, 0.80), Radius.circular(w * 0.16)),
        backPaint);
    canvas.drawPath(
        Path()
          ..moveTo(0.80 * w, 0.76 * h)
          ..lineTo(0.90 * w, 0.96 * h)
          ..lineTo(0.66 * w, 0.78 * h)
          ..close(),
        backPaint);
    final dot2 = Paint()..color = color.withAlpha(90);
    canvas.drawCircle(Offset(0.60 * w, 0.58 * h), w * 0.03, dot2);
    canvas.drawCircle(Offset(0.72 * w, 0.58 * h), w * 0.03, dot2);

    // সামনের বাবল
    final front = r(0.06, 0.14, 0.70, 0.62);
    final fp = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(color, Colors.white, 0.35)!, color],
      ).createShader(front);
    canvas.drawRRect(
        RRect.fromRectAndRadius(front, Radius.circular(w * 0.18)), fp);
    canvas.drawPath(
        Path()
          ..moveTo(0.20 * w, 0.58 * h)
          ..lineTo(0.14 * w, 0.80 * h)
          ..lineTo(0.38 * w, 0.60 * h)
          ..close(),
        fp);
    final white = Paint()..color = Colors.white;
    for (final x in [0.25, 0.38, 0.51]) {
      canvas.drawCircle(Offset(x * w, 0.38 * h), w * 0.04, white);
    }

    // ঝিলিক
    final sp = Paint()
      ..color = color
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0.60 * w, 0.06 * h), Offset(0.64 * w, 0.16 * h), sp);
    canvas.drawLine(Offset(0.72 * w, 0.10 * h), Offset(0.80 * w, 0.18 * h), sp);
    canvas.drawLine(Offset(0.80 * w, 0.24 * h), Offset(0.90 * w, 0.26 * h), sp);
  }

  @override
  bool shouldRepaint(covariant _BubblesPainter old) => old.color != color;
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
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: brand(context))),
              ),
              if (docs.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(tr('কিছু নেই'),
                      style: TextStyle(color: Theme.of(context).hintColor)),
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
                      backgroundColor: brand(context),
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
                              icon: Icon(Icons.check_circle,
                                  color: brand(context)),
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
  final String? groupId; // গ্রুপ চ্যাট হলে গ্রুপের আইডি
  const ChatPage(
      {super.key, this.otherUid = '', this.otherName = '', this.groupId});

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
  Map<String, dynamic> _g = {};
  StreamSubscription? _gSub;

  bool get isGroup => widget.groupId != null;

  @override
  void initState() {
    super.initState();
    if (isGroup) {
      _gSub = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .snapshots()
          .listen((d) {
        if (!mounted) return;
        if (!d.exists) {
          Navigator.maybePop(context);
          return;
        }
        setState(() => _g = d.data() ?? {});
      }, onError: (_) {});
    }
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _gSub?.cancel();
    _timer?.cancel();
    _rec.dispose();
    _text.dispose();
    super.dispose();
  }

  String get chatId =>
      isGroup ? widget.groupId! : pairId(me.uid, widget.otherUid);

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance
          .collection(isGroup ? 'groups' : 'chats')
          .doc(chatId);

  CollectionReference<Map<String, dynamic>> get _msgs =>
      _chatRef.collection('messages');

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _post(Map<String, dynamic> msg) => isGroup
      ? postGroupMessage(widget.groupId!, msg)
      : postMessage(widget.otherUid, widget.otherName, msg);

  String get _title =>
      isGroup ? (_g['title'] ?? widget.otherName).toString() : widget.otherName;

  void _call() {
    if (isGroup) {
      final mem = List<String>.from(_g['members'] ?? const []);
      final names = <String, String>{};
      final raw = _g['names'];
      if (raw is Map) {
        raw.forEach((k, v) => names[k.toString()] = v.toString());
      }
      final others = mem.where((u) => u != me.uid).toList();
      if (others.isEmpty) return;
      if (mem.length > kGroupMax) {
        _snack(tr('গ্রুপ কলে সর্বোচ্চ ৫ জন থাকতে পারে'));
        return;
      }
      if (inCall) {
        _snack(tr('অন্য একটা কল চলছে'));
        return;
      }
      inCall = true;
      final invited = <String, String>{
        for (final u in others) u: names[u] ?? '?'
      };
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GroupCallPage(call: GroupCall.outgoing(invited))),
      );
      return;
    }
    if (inCall) {
      _snack(tr('অন্য একটা কল চলছে'));
      return;
    }
    inCall = true;
    final session = CallSession.outgoing(widget.otherUid, widget.otherName);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallPage(session: session)),
    );
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
              leading: Icon(Icons.photo_library, color: brand(ctx)),
              title: Text(tr('গ্যালারি থেকে ছবি')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: brand(ctx)),
              title: Text(tr('ক্যামেরা')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file, color: brand(ctx)),
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
        playDeleteBeep();
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
            backgroundColor: brand(context),
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
          icon: Icon(Icons.attach_file, color: brand(context)),
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
              fillColor:
                  isDark(context) ? const Color(0xFF2A3942) : const Color(0xFFF0F0F0),
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
          backgroundColor: brand(context),
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
      case 'call':
        {
          final res = (m['result'] ?? 'missed').toString();
          final dur = (m['duration'] as num?)?.toInt() ?? 0;
          final label = res == 'ended'
              ? '${tr('ভয়েস কল')} · ${clock(dur)}'
              : (res == 'declined'
                  ? tr('কল ফিরিয়ে দেওয়া হয়েছে')
                  : tr('মিসড কল'));
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(res == 'ended' ? Icons.call : Icons.call_missed,
                  size: 20,
                  color: res == 'ended' ? brand(context) : Colors.red),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(label, style: const TextStyle(fontSize: 15))),
            ],
          );
        }
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
      backgroundColor:
          isDark(context) ? const Color(0xFF0B141A) : const Color(0xFFECE5DD),
      appBar: AppBar(
        title: isGroup
            ? InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => GroupInfoPage(groupId: widget.groupId!)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                        '${numL('${List.from(_g['members'] ?? const []).length}')} ${tr('জন সদস্য')}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              )
            : Text(widget.otherName),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: tr('ভয়েস কল'),
            onPressed: _call,
          ),
        ],
      ),
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
                                color: isDark(context)
                                    ? const Color(0xCC202C33)
                                    : Colors.white70,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(dayLabel(d),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDark(context)
                                          ? Colors.white70
                                          : Colors.black87)),
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
                                    ? (isDark(context)
                                        ? const Color(0xFF005C4B)
                                        : const Color(0xFFDCF8C6))
                                    : (isDark(context)
                                        ? const Color(0xFF202C33)
                                        : Colors.white),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (isGroup && !mine)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 2),
                                        child: Text(
                                            (m['senderName'] ?? '?').toString(),
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: brand(context))),
                                      ),
                                    ),
                                  _content(m, docs[i].id),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${edited ? '${tr('সম্পাদিত')} · ' : ''}${hhmm(d)}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context).hintColor)),
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
              color: Theme.of(context).colorScheme.surface,
              child: _inputBar(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- গ্রুপ তৈরি ----------------
const kGroupBig = 20;

class CreateGroupPage extends StatefulWidget {
  final Map<String, String> friends; // uid -> নাম
  const CreateGroupPage({super.key, required this.friends});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _title = TextEditingController();
  final Set<String> _sel = {};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      toast(context, tr('গ্রুপের নাম লিখুন'));
      return;
    }
    if (_sel.isEmpty) {
      toast(context, tr('কমপক্ষে একজনকে বেছে নিন'));
      return;
    }
    final me = FirebaseAuth.instance.currentUser!;
    setState(() => _busy = true);
    try {
      final ref = FirebaseFirestore.instance.collection('groups').doc();
      await ref.set({
        'title': t,
        'owner': me.uid,
        'members': [me.uid, ..._sel],
        'names': {me.uid: myName, for (final u in _sel) u: widget.friends[u] ?? '?'},
        'lastType': 'text',
        'lastText': '',
        'lastName': '',
        'lastSender': '',
        'lastTime': FieldValue.serverTimestamp(),
        'created': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ChatPage(groupId: ref.id, otherName: t)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.friends.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: Text(tr('নতুন গ্রুপ'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: tr('গ্রুপের নাম'),
                  border: const OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('গ্রুপে কাদের নেবেন বেছে নিন (সর্বোচ্চ ১৯ জন)'),
                  style: TextStyle(color: Theme.of(context).hintColor)),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final f in list)
                  CheckboxListTile(
                    value: _sel.contains(f.key),
                    secondary: CircleAvatar(
                      backgroundColor: brand(context),
                      child: Text(
                          f.value.isEmpty ? '?' : f.value[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(f.value),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          if (_sel.length >= kGroupBig - 1) {
                            toast(context, tr('সর্বোচ্চ ১৯ জনকে নেওয়া যায়'));
                          } else {
                            _sel.add(f.key);
                          }
                        } else {
                          _sel.remove(f.key);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.group_add),
                  label: Text('${tr('গ্রুপ তৈরি করুন')} (${numL('${_sel.length}')})'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- গ্রুপের তথ্য ----------------
class GroupInfoPage extends StatefulWidget {
  final String groupId;
  const GroupInfoPage({super.key, required this.groupId});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  final me = FirebaseAuth.instance.currentUser!;
  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  Future<void> _rename(String old) async {
    final c = TextEditingController(text: old);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('গ্রুপের নাম বদলান')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('বাতিল'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(tr('সেভ করুন'))),
        ],
      ),
    );
    if (res == null || res.isEmpty || res == old) return;
    await _run(() => _ref.update({'title': res}));
  }

  Future<void> _add(List<String> members) async {
    final db = FirebaseFirestore.instance;
    Map<String, String> friends = {};
    try {
      final s = await db
          .collection('friendships')
          .where('members', arrayContains: me.uid)
          .get();
      for (final d in s.docs) {
        final data = d.data();
        final mem = List<String>.from(data['members'] ?? const []);
        final other = mem.firstWhere((x) => x != me.uid, orElse: () => '');
        if (other.isEmpty || members.contains(other)) continue;
        final names = data['names'];
        friends[other] =
            (names is Map ? names[other] : null)?.toString() ?? '?';
      }
    } catch (e) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
      return;
    }
    if (!mounted) return;
    if (friends.isEmpty) {
      toast(context, tr('যোগ করার মতো কোনো ফ্রেন্ড নেই'));
      return;
    }
    final sel = <String>{};
    final room = kGroupBig - members.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('সদস্য যোগ করুন')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in friends.entries)
                  CheckboxListTile(
                    value: sel.contains(f.key),
                    title: Text(f.value),
                    onChanged: (v) => setS(() {
                      if (v == true) {
                        if (sel.length < room) sel.add(f.key);
                      } else {
                        sel.remove(f.key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('বাতিল'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('যোগ করুন'))),
          ],
        ),
      ),
    );
    if (ok != true || sel.isEmpty) return;
    await _run(() => _ref.update({
          'members': FieldValue.arrayUnion(sel.toList()),
          for (final u in sel) 'names.$u': friends[u] ?? '?',
        }));
  }

  Future<void> _kick(String uid) async {
    await _run(() => _ref.update({
          'members': FieldValue.arrayRemove([uid]),
          'names.$uid': FieldValue.delete(),
        }));
  }

  Future<void> _leave() async {
    final yes = await confirmDialog(context, tr('গ্রুপ ছেড়ে যান'),
        tr('গ্রুপটা ছেড়ে গেলে আর মেসেজ দেখতে পাবেন না।'), tr('ছেড়ে যান'));
    if (!yes) return;
    try {
      await _ref.update({'members': FieldValue.arrayRemove([me.uid])});
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  Future<void> _deleteGroup() async {
    final yes = await confirmDialog(context, tr('গ্রুপ মুছে ফেলুন'),
        tr('গ্রুপ ও সব মেসেজ সবার জন্য মুছে যাবে।'), tr('ডিলিট করুন'));
    if (!yes) return;
    try {
      while (true) {
        final s = await _ref.collection('messages').limit(300).get();
        if (s.docs.isEmpty) break;
        final b = FirebaseFirestore.instance.batch();
        for (final d in s.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }
      await _ref.delete();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('গ্রুপের তথ্য'))),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          final g = snap.data?.data();
          if (g == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = List<String>.from(g['members'] ?? const []);
          if (!members.contains(me.uid)) {
            return const Center(child: CircularProgressIndicator());
          }
          final names = <String, String>{};
          final raw = g['names'];
          if (raw is Map) {
            raw.forEach((k, v) => names[k.toString()] = v.toString());
          }
          final owner = (g['owner'] ?? '').toString();
          final iAmOwner = owner == me.uid;
          final title = (g['title'] ?? '').toString();
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: brand(context),
                      child: const Icon(Icons.groups,
                          size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('${numL('${members.length}')} ${tr('জন সদস্য')}',
                        style: TextStyle(color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
              if (iAmOwner)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(tr('গ্রুপের নাম বদলান')),
                  onTap: () => _rename(title),
                ),
              if (iAmOwner && members.length < kGroupBig)
                ListTile(
                  leading: Icon(Icons.person_add, color: brand(context)),
                  title: Text(tr('সদস্য যোগ করুন')),
                  onTap: () => _add(members),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(tr('সদস্য'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: brand(context))),
              ),
              for (final u in members)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: brand(context),
                    child: Text(
                        (u == me.uid ? myName : (names[u] ?? '?')).isEmpty
                            ? '?'
                            : (u == me.uid ? myName : (names[u] ?? '?'))[0]
                                .toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(u == me.uid
                      ? '${tr('আপনি')} ($myName)'
                      : (names[u] ?? '?')),
                  subtitle: u == owner ? Text(tr('অ্যাডমিন')) : null,
                  trailing: (iAmOwner && u != me.uid)
                      ? IconButton(
                          icon: const Icon(Icons.person_remove,
                              color: Colors.red),
                          tooltip: tr('সদস্যকে বাদ দিন'),
                          onPressed: () => _kick(u),
                        )
                      : null,
                ),
              const Divider(),
              if (!iAmOwner)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text(tr('গ্রুপ ছেড়ে যান'),
                      style: const TextStyle(color: Colors.red)),
                  onTap: _leave,
                ),
              if (iAmOwner)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(tr('গ্রুপ মুছে ফেলুন'),
                      style: const TextStyle(color: Colors.red)),
                  onTap: _deleteGroup,
                ),
              const SizedBox(height: 24),
            ],
          );
        },
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
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: tr('ছবি সেভ করুন'),
            onPressed: () async {
              try {
                await Gal.putImageBytes(bytes);
                if (context.mounted) {
                  toast(context, tr('ছবি গ্যালারিতে সেভ হয়েছে'));
                }
              } catch (e) {
                if (context.mounted) {
                  toast(context, '${tr('ছবি সেভ করা যায়নি')}: $e');
                }
              }
            },
          ),
        ],
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
          Icon(Icons.insert_drive_file, size: 36, color: brand(context)),
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
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor)),
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
          color: brand(context),
          icon: Icon(_playing ? Icons.stop_circle : Icons.play_circle_fill),
          onPressed: _toggle,
        ),
        const SizedBox(width: 8),
        Icon(Icons.graphic_eq, color: Theme.of(context).hintColor),
        const SizedBox(width: 8),
        Text(clock(widget.duration), style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

// ---------------- অ্যাকাউন্ট সেটিংস ----------------
class SettingsPage extends StatefulWidget {
  final bool embedded;
  const SettingsPage({super.key, this.embedded = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _ringName(String k) {
    switch (k) {
      case 'soft':
        return tr('নরম ঘণ্টা');
      case 'digital':
        return tr('ডিজিটাল বিপ');
      case 'rising':
        return tr('ক্রমশ উঁচু');
      case 'custom':
        return tr('নিজের বাছাই করা অডিও');
      default:
        return tr('ক্লাসিক');
    }
  }

  Future<void> _pickCustomRing() async {
    try {
      final xf = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
          label: 'audio',
          extensions: ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'opus'],
          mimeTypes: ['audio/*'],
        ),
      ]);
      if (xf == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dot = xf.name.lastIndexOf('.');
      final ext = dot >= 0 ? xf.name.substring(dot) : '.mp3';
      final dest = File('${dir.path}/my_ringtone$ext');
      await dest.writeAsBytes(await xf.readAsBytes());
      ringCustomPath = dest.path;
      await savePref('ringCustom', dest.path);
      await setRingTone('custom');
      previewRingTone('custom');
    } catch (e) {
      if (mounted) toast(context, '${tr('অডিও বাছা যায়নি')}: $e');
    }
  }

  Future<void> _pickRingtone() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget item(String k) => ListTile(
                title: Text(_ringName(k)),
                trailing: ringToneN.value == k
                    ? Icon(Icons.check_circle, color: brand(context))
                    : null,
                onTap: () async {
                  await setRingTone(k);
                  previewRingTone(k);
                  setS(() {});
                },
              );
          return AlertDialog(
            title: Text(tr('রিংটোন')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  item('classic'),
                  item('soft'),
                  item('digital'),
                  item('rising'),
                  if (ringCustomPath.isNotEmpty) item('custom'),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(tr('ফোন থেকে বাছুন')),
                    onTap: () async {
                      await _pickCustomRing();
                      setS(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('অ্যাপ খোলা থাকলে এই রিংটোন বাজবে। অ্যাপ বন্ধ থাকলে ফোনের সেটিংসের (অ্যাপস > Alap > নোটিফিকেশন > Calls > সাউন্ড) রিংটোন বাজবে।'),
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('ঠিক আছে'))),
            ],
          );
        },
      ),
    );
    await stopRing();
    if (mounted) setState(() {});
  }

  Future<void> _changeName() async {
    final c = TextEditingController(text: myName);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('নাম পরিবর্তন')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(
              labelText: tr('নতুন নাম'), border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('বাতিল'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(tr('সেভ করুন'))),
        ],
      ),
    );
    if (res == null || res.isEmpty || res == myName) return;
    try {
      final u = FirebaseAuth.instance.currentUser!;
      await u.updateDisplayName(res);
      await u.reload();
      final db = FirebaseFirestore.instance;
      await db.collection('users').doc(u.uid).set(
          {'uid': u.uid, 'name': res, 'nameLower': res.toLowerCase()},
          SetOptions(merge: true));
      // ফ্রেন্ড ও চ্যাট তালিকায় আমার নামও বদলে দেয়
      final fr = await db
          .collection('friendships')
          .where('members', arrayContains: u.uid)
          .get();
      for (final d in fr.docs) {
        await d.reference.update({'names.${u.uid}': res});
      }
      final ch = await db
          .collection('chats')
          .where('members', arrayContains: u.uid)
          .get();
      for (final d in ch.docs) {
        await d.reference.update({'names.${u.uid}': res});
      }
      if (!mounted) return;
      setState(() {});
      toast(context, tr('নাম বদলানো হয়েছে'));
    } catch (e) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $e');
    }
  }

  Future<void> _changeEmail() async {
    final e = TextEditingController();
    final p = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ইমেইল পরিবর্তন')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: e,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: tr('নতুন ইমেইল'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: p,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: tr('বর্তমান পাসওয়ার্ড'),
                    border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('বাতিল'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('সেভ করুন'))),
        ],
      ),
    );
    if (ok != true) return;
    final newEmail = e.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      if (mounted) toast(context, tr('ইমেইলটা সঠিক নয়'));
      return;
    }
    try {
      final u = FirebaseAuth.instance.currentUser!;
      await u.reauthenticateWithCredential(EmailAuthProvider.credential(
          email: u.email!, password: p.text.trim()));
      await u.verifyBeforeUpdateEmail(newEmail);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(tr(
              'নতুন ইমেইলে একটা ভেরিফিকেশন লিংক পাঠানো হয়েছে। লিংকে ট্যাপ করলে ইমেইল বদলে যাবে, তারপর নতুন ইমেইল দিয়ে আবার লগইন করুন।')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('ঠিক আছে'))),
          ],
        ),
      );
    } on FirebaseAuthException catch (ex) {
      if (mounted) toast(context, authMsg(ex));
    } catch (ex) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $ex');
    }
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController();
    final n1 = TextEditingController();
    final n2 = TextEditingController();
    Widget field(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            obscureText: true,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('পাসওয়ার্ড পরিবর্তন')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(cur, tr('বর্তমান পাসওয়ার্ড')),
              field(n1, tr('নতুন পাসওয়ার্ড')),
              field(n2, tr('নতুন পাসওয়ার্ড আবার লিখুন')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('বাতিল'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('সেভ করুন'))),
        ],
      ),
    );
    if (ok != true) return;
    final newPass = n1.text.trim();
    if (newPass.length < 6) {
      if (mounted) toast(context, tr('পাসওয়ার্ড খুব ছোট (কমপক্ষে ৬ অক্ষর)'));
      return;
    }
    if (newPass != n2.text.trim()) {
      if (mounted) toast(context, tr('দুইবারের নতুন পাসওয়ার্ড মেলেনি'));
      return;
    }
    try {
      final u = FirebaseAuth.instance.currentUser!;
      await u.reauthenticateWithCredential(EmailAuthProvider.credential(
          email: u.email!, password: cur.text.trim()));
      await u.updatePassword(newPass);
      if (mounted) toast(context, tr('পাসওয়ার্ড বদলানো হয়েছে'));
    } on FirebaseAuthException catch (ex) {
      if (mounted) toast(context, authMsg(ex));
    } catch (ex) {
      if (mounted) toast(context, '${tr('ব্যর্থ হয়েছে')}: $ex');
    }
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: brand(context))),
      );

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final name = myName;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('অ্যাকাউন্ট সেটিংস')),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: brand(context),
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style:
                          const TextStyle(fontSize: 30, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                Text(name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text(u?.email ?? '',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(tr('নাম পরিবর্তন')),
            subtitle: Text(name),
            onTap: _changeName,
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(tr('ইমেইল পরিবর্তন')),
            subtitle: Text(u?.email ?? ''),
            onTap: _changeEmail,
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr('পাসওয়ার্ড পরিবর্তন')),
            onTap: _changePassword,
          ),
          const Divider(),
          _header('${tr('থিম')} / ${tr('রঙ')}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in kThemeColors)
                  GestureDetector(
                    onTap: () => setThemeColor(c),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(c),
                      child: themeSeed.value == c
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'system', label: Text(tr('সিস্টেম'))),
                ButtonSegment(value: 'light', label: Text(tr('লাইট'))),
                ButtonSegment(value: 'dark', label: Text(tr('ডার্ক'))),
              ],
              selected: {themeModeN.value},
              onSelectionChanged: (v) => setThemeMode(v.first),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('ভাষা')),
            subtitle: Text(isBn ? 'বাংলা' : 'English'),
            onTap: () => pickLanguage(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(tr('ডিলিট করলে বিপ সাউন্ড')),
            value: deleteSoundOn.value,
            onChanged: (v) {
              setDeleteSound(v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.ring_volume),
            title: Text(tr('রিংটোন')),
            subtitle: Text(_ringName(ringToneN.value)),
            onTap: _pickRingtone,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(tr('লগআউট')),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              signOutClean();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(tr('অ্যাকাউন্ট ডিলিট করুন'),
                style: const TextStyle(color: Colors.red)),
            onTap: () => deleteMyAccount(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------- ভয়েস কল (WebRTC) ----------------
// সিগন্যালিং (কে কাকে ফোন করছে) Firestore দিয়ে হয়; কথা সরাসরি দুই ফোনের মধ্যে চলে।
// নিজের TURN সার্ভার থাকলে নিচের তালিকায় যোগ করুন (ভিন্ন নেটওয়ার্কে কল ধরতে সাহায্য করে)।
const kIceServers = <Map<String, dynamic>>[
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ]
  },
  // {'urls': 'turn:YOUR_TURN_HOST:3478', 'username': 'USER', 'credential': 'PASS'},
];

class CallSession {
  final bool isCaller;
  final String otherUid;
  final String otherName;
  final DocumentReference<Map<String, dynamic>> ref;

  /// incoming | calling | connecting | connected | ended
  final ValueNotifier<String> state;
  String result = 'missed'; // ended | declined | missed
  String? error;
  bool muted = false;
  bool speaker = false;
  DateTime? connectedAt;

  Map<String, dynamic>? _offer;
  rtc.RTCPeerConnection? _pc;
  rtc.MediaStream? _local;
  final List<StreamSubscription> _subs = [];
  final List<rtc.RTCIceCandidate> _queue = [];
  final List<Map<String, dynamic>> _outBuf = [];
  bool _remoteSet = false;
  bool _answerStarted = false;
  bool _docReady = false;
  bool _finished = false;
  Timer? _timeout;

  CallSession._(
      this.isCaller, this.otherUid, this.otherName, this.ref, String initial)
      : state = ValueNotifier<String>(initial);

  factory CallSession.outgoing(String otherUid, String otherName) {
    final ref = FirebaseFirestore.instance.collection('calls').doc();
    return CallSession._(true, otherUid, otherName, ref, 'calling');
  }

  factory CallSession.incoming(String callId, Map<String, dynamic> data) {
    final ref = FirebaseFirestore.instance.collection('calls').doc(callId);
    final s = CallSession._(false, (data['caller'] ?? '').toString(),
        (data['callerName'] ?? '?').toString(), ref, 'incoming');
    s._offer = Map<String, dynamic>.from(data['offer'] ?? {});
    return s;
  }

  bool get finished => _finished;
  String get _myColl => isCaller ? 'callerCandidates' : 'calleeCandidates';
  String get _otherColl => isCaller ? 'calleeCandidates' : 'callerCandidates';

  Future<void> _sendCand(Map<String, dynamic> m) async {
    try {
      await ref.collection(_myColl).add(m);
    } catch (_) {}
  }

  void _markReady() {
    _docReady = true;
    for (final m in _outBuf) {
      _sendCand(m);
    }
    _outBuf.clear();
  }

  Future<void> _setup() async {
    final pc = await rtc.createPeerConnection(
        {'iceServers': kIceServers, 'sdpSemantics': 'unified-plan'});
    _pc = pc;
    final local = await rtc.navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
    _local = local;
    for (final t in local.getAudioTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      final m = <String, dynamic>{
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      if (_docReady) {
        _sendCand(m);
      } else {
        _outBuf.add(m);
      }
    };
    pc.onConnectionState = (st) {
      if (_finished) return;
      if (st == rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (connectedAt == null) {
          connectedAt = DateTime.now();
          _timeout?.cancel();
          stopRing();
          state.value = 'connected';
          rtc.Helper.setSpeakerphoneOn(speaker);
        }
      } else if (st ==
          rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        endCall();
      }
    };
  }

  void _listen() {
    _subs.add(ref.snapshots().listen(_onCallDoc));
    _subs.add(ref.collection(_otherColl).snapshots().listen(_onCands));
  }

  /// কলকারী: কল শুরু করে
  Future<void> start() async {
    try {
      await _setup();
      final me = FirebaseAuth.instance.currentUser!;
      final pc = _pc!;
      final offer = await pc.createOffer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);
      await ref.set({
        'caller': me.uid,
        'callee': otherUid,
        'callerName': myName,
        'calleeName': otherName,
        'status': 'ringing',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'time': FieldValue.serverTimestamp(),
      });
      pushRing('call', ref.id);
      _markReady();
      _listen();
      _timeout = Timer(const Duration(seconds: 45), () {
        if (state.value == 'calling') endCall();
      });
      startRing();
    } catch (e) {
      error = '$e';
      _finish();
    }
  }

  /// যাকে কল করা হয়েছে: কল ধরে
  Future<void> accept() async {
    try {
      stopRing();
      state.value = 'connecting';
      await _setup();
      final pc = _pc!;
      await pc.setRemoteDescription(
          rtc.RTCSessionDescription(_offer!['sdp'], _offer!['type']));
      _flushQueue();
      final ans = await pc.createAnswer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(ans);
      if (_finished) return;
      _markReady();
      await ref.update({
        'answer': {'sdp': ans.sdp, 'type': ans.type},
        'status': 'accepted',
      });
      _listen();
    } catch (e) {
      error = '$e';
      endCall();
    }
  }

  void _onCallDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_finished) return;
    if (!snap.exists) {
      _finish();
      return;
    }
    final d = snap.data() ?? {};
    final st = d['status'];
    if (isCaller &&
        st == 'accepted' &&
        !_answerStarted &&
        d['answer'] != null) {
      _answerStarted = true;
      final a = Map<String, dynamic>.from(d['answer']);
      stopRing();
      _timeout?.cancel();
      state.value = 'connecting';
      _pc
          ?.setRemoteDescription(rtc.RTCSessionDescription(a['sdp'], a['type']))
          .then((_) => _flushQueue())
          .catchError((e) {
        error = '$e';
        endCall();
      });
    }
    if (st == 'declined') {
      result = 'declined';
      _finish();
    } else if (st == 'ended' || st == 'missed') {
      _finish();
    }
  }

  void _onCands(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final c in snap.docChanges) {
      if (c.type != DocumentChangeType.added) continue;
      final m = c.doc.data();
      if (m == null) continue;
      final cand = rtc.RTCIceCandidate(
          m['candidate'] as String?, m['sdpMid'] as String?, m['sdpMLineIndex'] as int?);
      if (_remoteSet) {
        _pc?.addCandidate(cand).catchError((_) {});
      } else {
        _queue.add(cand);
      }
    }
  }

  void _flushQueue() {
    _remoteSet = true;
    for (final c in _queue) {
      _pc?.addCandidate(c).catchError((_) {});
    }
    _queue.clear();
  }

  /// কল কাটা / বাতিল / ফিরিয়ে দেওয়া
  Future<void> endCall() async {
    if (_finished) return;
    final connected =
        state.value == 'connected' || state.value == 'connecting';
    final status = connected ? 'ended' : (isCaller ? 'missed' : 'declined');
    if (!isCaller && !connected) result = 'declined';
    try {
      await ref.update({'status': status});
    } catch (_) {}
    _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    stopRing();
    for (final s in _subs) {
      s.cancel();
    }
    if (connectedAt != null) result = 'ended';
    final secs = connectedAt == null
        ? 0
        : DateTime.now().difference(connectedAt!).inSeconds;
    try {
      for (final t in _local?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
        t.stop();
      }
      _local?.dispose();
      _pc?.close();
    } catch (_) {}
    state.value = 'ended';
    // কলকারীর চ্যাটে কলের হিসাব (মিসড / কথা হয়েছে) লেখা থাকে
    if (isCaller && error == null) {
      postMessage(otherUid, otherName,
          {'type': 'call', 'result': result, 'duration': secs}).catchError((_) {});
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    try {
      await rtc.Helper.setSpeakerphoneOn(speaker);
    } catch (_) {}
  }
}

class CallPage extends StatefulWidget {
  final CallSession session;
  const CallPage({super.key, required this.session});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  Timer? _tick;
  bool _popped = false;

  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.state.addListener(_onState);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (s.isCaller) {
      s.start();
    } else {
      startRing(incoming: true);
    }
  }

  void _onState() {
    if (s.state.value == 'ended' && !_popped) {
      _popped = true;
      stopRing();
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.state.removeListener(_onState);
    _tick?.cancel();
    inCall = false;
    if (!s.finished) s.endCall();
    stopRing();
    super.dispose();
  }

  String _statusText() {
    final st = s.state.value;
    if (st == 'incoming') return tr('ভয়েস কল আসছে');
    if (st == 'calling') return tr('কল করা হচ্ছে…');
    if (st == 'connecting') return tr('সংযুক্ত হচ্ছে…');
    if (st == 'connected') {
      final d = s.connectedAt == null
          ? 0
          : DateTime.now().difference(s.connectedAt!).inSeconds;
      return clock(d);
    }
    return s.error != null ? tr('কল করা যায়নি') : tr('কল শেষ');
  }

  Widget _btn(IconData icon, Color bg, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: bg,
          child: IconButton(
            iconSize: 28,
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = s.state.value;
    final bg = Color.alphaBlend(Colors.black54, brand(context));
    final List<Widget> buttons;
    if (st == 'incoming') {
      buttons = [
        _btn(Icons.call_end, Colors.red, tr('কল কাটুন'), () => s.endCall()),
        _btn(Icons.call, Colors.green, tr('কল ধরুন'), () => s.accept()),
      ];
    } else if (st == 'ended') {
      buttons = [];
    } else {
      buttons = [
        _btn(s.muted ? Icons.mic_off : Icons.mic,
            s.muted ? Colors.white38 : Colors.white24, tr('মিউট'), () {
          s.toggleMute();
          setState(() {});
        }),
        _btn(Icons.call_end, Colors.red, tr('কল কাটুন'), () => s.endCall()),
        _btn(Icons.volume_up, s.speaker ? Colors.white38 : Colors.white24,
            tr('স্পিকার'), () async {
          await s.toggleSpeaker();
          if (mounted) setState(() {});
        }),
      ];
    }
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white24,
              child: Text(
                s.otherName.isEmpty ? '?' : s.otherName[0].toUpperCase(),
                style: const TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.otherName,
                style: const TextStyle(
                    fontSize: 26,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_statusText(),
                style: const TextStyle(fontSize: 18, color: Colors.white70)),
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.error!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: buttons,
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// ---------------- গ্রুপ ভয়েস কল (সর্বোচ্চ ৫ জন) ----------------
// প্রত্যেকে প্রত্যেকের সাথে সরাসরি যুক্ত হয় (mesh)। সিগন্যালিং Firestore দিয়ে।
const kGroupMax = 5;

class _GPeer {
  rtc.RTCPeerConnection? pc;
  Future<void>? ready;
  final List<rtc.RTCIceCandidate> queue = [];
  bool remoteSet = false;
  String state = 'connecting'; // connecting | connected
}

class GroupCall {
  final DocumentReference<Map<String, dynamic>> ref;
  final String me = FirebaseAuth.instance.currentUser!.uid;
  final bool isHost;
  final List<String> invitedUids; // শুধু হোস্টের জন্য
  final Map<String, String> names; // uid -> নাম
  final String hostName;

  /// incoming | active | ended
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  String state;
  String? error;
  bool muted = false;
  bool speaker = false;
  DateTime? startedAt;
  List<String> members = [];
  Set<String> joined = {};

  final Map<String, _GPeer> _peers = {};
  final Map<String, List<rtc.RTCIceCandidate>> _early = {};
  rtc.MediaStream? _local;
  final List<StreamSubscription> _subs = [];
  Timer? _aloneTimer;
  bool _finished = false;

  GroupCall._(this.ref, this.isHost, this.invitedUids, this.names,
      this.hostName, this.state);

  factory GroupCall.outgoing(Map<String, String> invited) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('groupCalls').doc();
    final names = {me: myName, ...invited};
    final g = GroupCall._(
        ref, true, invited.keys.toList(), names, myName, 'active');
    g.members = [me, ...invited.keys];
    return g;
  }

  factory GroupCall.incoming(String id, Map<String, dynamic> d) {
    final ref = FirebaseFirestore.instance.collection('groupCalls').doc(id);
    final names = <String, String>{};
    final raw = d['names'];
    if (raw is Map) {
      raw.forEach((k, v) => names[k.toString()] = v.toString());
    }
    final g = GroupCall._(ref, false, const [], names,
        (d['hostName'] ?? '?').toString(), 'incoming');
    g.members = List<String>.from(d['members'] ?? const []);
    g.joined = Set<String>.from(d['joined'] ?? const []);
    return g;
  }

  bool get finished => _finished;
  String nameOf(String uid) => uid == me ? myName : (names[uid] ?? '?');
  void _ping() => tick.value++;

  Future<void> _openMic() async {
    _local = await rtc.navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
  }

  /// হোস্ট: কল শুরু
  Future<void> start() async {
    try {
      await _openMic();
      await ref.set({
        'host': me,
        'hostName': myName,
        'members': members,
        'invited': invitedUids,
        'names': names,
        'joined': [me],
        'status': 'active',
        'time': FieldValue.serverTimestamp(),
      });
      pushRing('group', ref.id);
      joined = {me};
      startedAt = DateTime.now();
      _listen();
      _ping();
    } catch (e) {
      error = '$e';
      _finish();
    }
  }

  /// আমন্ত্রিত: কলে যোগ দেয়
  Future<void> join() async {
    try {
      stopRing();
      state = 'active';
      _ping();
      await _openMic();
      await ref.update({
        'joined': FieldValue.arrayUnion([me])
      });
      startedAt = DateTime.now();
      _listen();
    } catch (e) {
      error = '$e';
      _finish();
    }
  }

  void _listen() {
    _subs.add(ref.snapshots().listen(_onDoc, onError: (_) {}));
    _subs.add(ref
        .collection('signals')
        .where('to', isEqualTo: me)
        .snapshots()
        .listen(_onSignals, onError: (_) {}));
  }

  void _onDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_finished) return;
    if (!snap.exists || snap.data()?['status'] == 'ended') {
      _finish();
      return;
    }
    final d = snap.data()!;
    joined = Set<String>.from(d['joined'] ?? const []);
    members = List<String>.from(d['members'] ?? members);
    // যার uid ছোট সে অফার পাঠায়
    for (final u in joined) {
      if (u == me || _peers.containsKey(u)) continue;
      if (me.compareTo(u) < 0) _connectTo(u);
    }
    // যারা বেরিয়ে গেছে তাদের সংযোগ বন্ধ
    for (final u in _peers.keys.toList()) {
      if (!joined.contains(u)) _drop(u);
    }
    // একা থাকলে ৬০ সেকেন্ড পরে নিজে থেকে শেষ
    if (joined.length <= 1) {
      _aloneTimer ??= Timer(const Duration(seconds: 60), () {
        if (joined.length <= 1) leave();
      });
    } else {
      _aloneTimer?.cancel();
      _aloneTimer = null;
    }
    _ping();
  }

  _GPeer _newPeer(String u) {
    final p = _GPeer();
    _peers[u] = p;
    p.ready = () async {
      final pc = await rtc.createPeerConnection(
          {'iceServers': kIceServers, 'sdpSemantics': 'unified-plan'});
      p.pc = pc;
      for (final t in _local?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
        await pc.addTrack(t, _local!);
      }
      pc.onIceCandidate = (c) {
        if (c.candidate == null) return;
        _signal(u, 'cand', {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };
      pc.onConnectionState = (st) {
        if (_finished) return;
        if (st == rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          p.state = 'connected';
          rtc.Helper.setSpeakerphoneOn(speaker);
          _ping();
        } else if (st ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          p.state = 'failed';
          _ping();
        }
      };
    }();
    final early = _early.remove(u);
    if (early != null) p.queue.addAll(early);
    return p;
  }

  Future<void> _signal(String to, String kind, Map<String, dynamic> data) async {
    try {
      await ref.collection('signals').add({
        'from': me,
        'to': to,
        'kind': kind,
        'data': data,
        'time': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _connectTo(String u) async {
    final p = _newPeer(u);
    try {
      await p.ready;
      final pc = p.pc!;
      final offer = await pc.createOffer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);
      await _signal(u, 'offer', {'sdp': offer.sdp, 'type': offer.type});
    } catch (e) {
      error = '$e';
      _ping();
    }
  }

  void _onSignals(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final c in snap.docChanges) {
      if (c.type != DocumentChangeType.added) continue;
      final m = c.doc.data();
      if (m == null) continue;
      final from = (m['from'] ?? '').toString();
      final kind = m['kind'];
      final data = Map<String, dynamic>.from(m['data'] ?? {});
      if (from.isEmpty || _finished) continue;
      if (kind == 'offer') {
        _onOffer(from, data);
      } else if (kind == 'answer') {
        _onAnswer(from, data);
      } else if (kind == 'cand') {
        final cand = rtc.RTCIceCandidate(data['candidate'] as String?,
            data['sdpMid'] as String?, data['sdpMLineIndex'] as int?);
        final p = _peers[from];
        if (p == null) {
          _early.putIfAbsent(from, () => []).add(cand);
        } else if (p.remoteSet) {
          p.pc?.addCandidate(cand).catchError((_) {});
        } else {
          p.queue.add(cand);
        }
      }
      c.doc.reference.delete().catchError((_) {});
    }
  }

  Future<void> _onOffer(String from, Map<String, dynamic> o) async {
    _drop(from);
    final p = _newPeer(from);
    try {
      await p.ready;
      final pc = p.pc!;
      await pc.setRemoteDescription(rtc.RTCSessionDescription(o['sdp'], o['type']));
      p.remoteSet = true;
      for (final c in p.queue) {
        pc.addCandidate(c).catchError((_) {});
      }
      p.queue.clear();
      final ans = await pc.createAnswer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(ans);
      await _signal(from, 'answer', {'sdp': ans.sdp, 'type': ans.type});
    } catch (e) {
      error = '$e';
      _ping();
    }
  }

  Future<void> _onAnswer(String from, Map<String, dynamic> a) async {
    final p = _peers[from];
    if (p == null) return;
    try {
      await p.ready;
      final pc = p.pc!;
      await pc.setRemoteDescription(rtc.RTCSessionDescription(a['sdp'], a['type']));
      p.remoteSet = true;
      for (final c in p.queue) {
        pc.addCandidate(c).catchError((_) {});
      }
      p.queue.clear();
    } catch (e) {
      error = '$e';
      _ping();
    }
  }

  void _drop(String u) {
    final p = _peers.remove(u);
    try {
      p?.pc?.close();
    } catch (_) {}
  }

  String statusOf(String uid) {
    if (uid == me) return 'me';
    if (!joined.contains(uid)) return 'ringing';
    return _peers[uid]?.state ?? 'connecting';
  }

  /// কল ছেড়ে যাওয়া। শেষজন গেলে কলের ডকুমেন্ট মুছে যায়।
  Future<void> leave() async {
    if (_finished) return;
    final wasJoined = state == 'active';
    _finish();
    if (!wasJoined) return;
    try {
      await ref.update({
        'joined': FieldValue.arrayRemove([me])
      });
      final s = await ref.get();
      final left = List<String>.from(s.data()?['joined'] ?? const []);
      if (left.isEmpty) await ref.delete();
    } catch (_) {}
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _aloneTimer?.cancel();
    stopRing();
    for (final s in _subs) {
      s.cancel();
    }
    for (final u in _peers.keys.toList()) {
      _drop(u);
    }
    try {
      for (final t in _local?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
        t.stop();
      }
      _local?.dispose();
    } catch (_) {}
    state = 'ended';
    _ping();
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    _ping();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    try {
      await rtc.Helper.setSpeakerphoneOn(speaker);
    } catch (_) {}
    _ping();
  }
}

class GroupCallPage extends StatefulWidget {
  final GroupCall call;
  const GroupCallPage({super.key, required this.call});

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage> {
  Timer? _tick;
  Timer? _ringTimeout;
  bool _popped = false;
  GroupCall get g => widget.call;

  @override
  void initState() {
    super.initState();
    g.tick.addListener(_onTick);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (g.isHost) {
      g.start();
    } else {
      startRing(incoming: true);
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (g.state == 'incoming') g.leave();
      });
    }
  }

  void _onTick() {
    if (g.state == 'ended' && !_popped) {
      _popped = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    g.tick.removeListener(_onTick);
    _tick?.cancel();
    _ringTimeout?.cancel();
    inCall = false;
    if (!g.finished) g.leave();
    stopRing();
    super.dispose();
  }

  Widget _btn(IconData icon, Color bg, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: bg,
          child: IconButton(
            iconSize: 28,
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  String _label(String uid) {
    final st = g.statusOf(uid);
    if (st == 'me') return tr('আপনি');
    if (st == 'ringing') return tr('রিং হচ্ছে…');
    if (st == 'connected') return tr('সংযুক্ত');
    if (st == 'failed') return tr('সংযোগ হয়নি');
    return tr('সংযুক্ত হচ্ছে…');
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.alphaBlend(Colors.black54, brand(context));
    final incoming = g.state == 'incoming';
    final secs = g.startedAt == null
        ? 0
        : DateTime.now().difference(g.startedAt!).inSeconds;
    final subtitle = incoming
        ? '${g.hostName} ${tr('আপনাকে গ্রুপ কলে ডাকছে')}'
        : g.state == 'ended'
            ? (g.error != null ? tr('কল করা যায়নি') : tr('কল শেষ'))
            : clock(secs);
    final buttons = incoming
        ? [
            _btn(Icons.call_end, Colors.red, tr('কল কাটুন'), () => g.leave()),
            _btn(Icons.call, Colors.green, tr('কল ধরুন'), () {
              _ringTimeout?.cancel();
              g.join();
            }),
          ]
        : g.state == 'ended'
            ? <Widget>[]
            : [
                _btn(g.muted ? Icons.mic_off : Icons.mic,
                    g.muted ? Colors.white38 : Colors.white24, tr('মিউট'),
                    () => g.toggleMute()),
                _btn(Icons.call_end, Colors.red, tr('কল কাটুন'),
                    () => g.leave()),
                _btn(Icons.volume_up,
                    g.speaker ? Colors.white38 : Colors.white24, tr('স্পিকার'),
                    () => g.toggleSpeaker()),
              ];
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 28),
            Text(tr('গ্রুপ কল'),
                style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
            if (g.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(g.error!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final u in g.members)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Text(
                            g.nameOf(u).isEmpty
                                ? '?'
                                : g.nameOf(u)[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(g.nameOf(u),
                          style: const TextStyle(color: Colors.white)),
                      subtitle: incoming
                          ? null
                          : Text(_label(u),
                              style: TextStyle(
                                  color: g.statusOf(u) == 'connected' ||
                                          g.statusOf(u) == 'me'
                                      ? Colors.greenAccent
                                      : Colors.white60)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buttons,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ---------------- Alap-এর কাগজের প্লেন আইকন ----------------
class PlaneLogo extends StatelessWidget {
  final double size;
  const PlaneLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _PlanePainter());
}

class _PlanePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Offset o(double x, double y) => Offset(x * size.width, y * size.height);
    final a = o(0.02, 0.50); // বাঁ ডানার ডগা
    final b = o(0.98, 0.08); // ডান ওপরের ডগা
    final c = o(0.33, 0.60); // ভাঁজের ভেতরের বিন্দু
    final d = o(0.56, 0.95); // নিচের ডগা
    final g = o(0.36, 0.88); // লেজের ডগা
    final h = o(0.46, 0.70);

    Paint grad(Offset p1, Offset p2, Color c1, Color c2) => Paint()
      ..shader = LinearGradient(colors: [c1, c2])
          .createShader(Rect.fromPoints(p1, p2).inflate(1));

    void tri(Offset p, Offset q, Offset r, Paint paint) {
      final path = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(q.dx, q.dy)
        ..lineTo(r.dx, r.dy)
        ..close();
      canvas.drawPath(path, paint);
    }

    // ডান পাশ (হালকা পুদিনা)
    tri(b, c, d,
        grad(b, d, const Color(0xFFE6FFF3), const Color(0xFF7FF0C2)));
    // ওপরের ডানা (উজ্জ্বল সবুজ)
    tri(a, b, c,
        grad(a, b, const Color(0xFF17E89C), const Color(0xFF8CFFC8)));
    // ভাঁজের ছায়া (গাঢ় সবুজ)
    tri(c, g, h, Paint()..color = const Color(0xFF0B7A62));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
