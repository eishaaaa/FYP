import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

const _kEmailJsServiceId  = 'service_snjia2f';
const _kEmailJsTemplateId = 'template_avx4nsx';
const _kEmailJsPublicKey  = 'q6aXVmoxxbB1KTe3i';

const _kSupportEmail = 'digitalgoods.support@gmail.com';
const _kTeal         = Color(0xFF2D8C8C);
const _kTealDark     = Color(0xFF1F5C5C);
const _kTealLight    = Color(0xFFE8F4F4);

class _Topic {
  final String label;
  final IconData icon;
  final String subjectPrefix;
  const _Topic({required this.label, required this.icon, required this.subjectPrefix});
}

const _topics = [
  _Topic(label: 'General Inquiry',       icon: Icons.help_outline_rounded,             subjectPrefix: '[General]'),
  _Topic(label: 'Account & Profile',     icon: Icons.manage_accounts_rounded,          subjectPrefix: '[Account]'),
  _Topic(label: 'Transaction Issue',     icon: Icons.swap_horiz_rounded,               subjectPrefix: '[Transaction]'),
  _Topic(label: 'Stolen Asset Report',   icon: Icons.report_problem_rounded,           subjectPrefix: '[Stolen Report]'),
  _Topic(label: 'Blockchain / Wallet',   icon: Icons.account_balance_wallet_outlined,  subjectPrefix: '[Blockchain]'),
  _Topic(label: 'Bug / Technical Problem', icon: Icons.bug_report_outlined,            subjectPrefix: '[Bug]'),
  _Topic(label: 'Other',                 icon: Icons.more_horiz_rounded,               subjectPrefix: '[Other]'),
];

class EmailSupportScreen extends StatefulWidget {
  const EmailSupportScreen({super.key});
  @override
  State<EmailSupportScreen> createState() => _EmailSupportScreenState();
}

class _EmailSupportScreenState extends State<EmailSupportScreen>
    with TickerProviderStateMixin {

  final _formKey      = GlobalKey<FormState>();
  final _subjectCtrl  = TextEditingController();
  final _bodyCtrl     = TextEditingController();
  final _subjectFocus = FocusNode();
  final _bodyFocus    = FocusNode();

  int  _selectedTopic = 0;
  bool _isSubmitting  = false;
  bool _submitted     = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;
  late AnimationController _successCtrl;
  late Animation<double>   _successScale;

  String _userEmail = '';
  String _userName  = '';
  String _userUid   = '';

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);

    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userUid   = user.uid;
    _userEmail = user.email ?? '';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) setState(() => _userName = doc.data()?['name'] ?? user.displayName ?? '');
    } catch (_) {}
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _successCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _subjectFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final topic   = _topics[_selectedTopic];
    final subject = '${topic.subjectPrefix} ${_subjectCtrl.text.trim()}';
    final body    = _bodyCtrl.text.trim();

    try {
      await _sendViaEmailJs(
        subject  : subject,
        message  : body,
        fromName : _userName.isNotEmpty ? _userName : 'App User',
        replyTo  : _userEmail,
        uid      : _userUid,
        topic    : topic.label,
      );

      await FirebaseFirestore.instance.collection('support_emails').add({
        'uid'       : _userUid,
        'email'     : _userEmail,
        'name'      : _userName,
        'topic'     : topic.label,
        'subject'   : subject,
        'body'      : body,
        'status'    : 'open',
        'createdAt' : FieldValue.serverTimestamp(),
        'platform'  : Theme.of(context).platform.name,
      });

      if (mounted) {
        setState(() { _isSubmitting = false; _submitted = true; });
        _successCtrl.forward();
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('Could not send — please email $_kSupportEmail directly.', isError: true);
      }
    }
  }

Future<void> _sendViaEmailJs({
  required String subject,
  required String message,
  required String fromName,
  required String replyTo,
  required String uid,
  required String topic,
}) async {
  final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'origin': 'http://localhost',
    },
    body: jsonEncode({
      'service_id'  : _kEmailJsServiceId,
      'template_id' : _kEmailJsTemplateId,
      'user_id'     : _kEmailJsPublicKey,
      'template_params': {
        'title'   : subject,   // matches {{title}} in your template Subject line
        'name'    : fromName,  // matches {{name}} in your template body
        'message' : message,   // matches {{message}} in your template body
        'email'   : replyTo.isNotEmpty ? replyTo : 'no-reply@digitalgoods.com', // matches {{email}} in Reply To
        'uid'     : uid,
        'topic'   : topic,
      },
    }),
  );

  debugPrint('EmailJS status: ${response.statusCode}');
  debugPrint('EmailJS body:   ${response.body}');

  if (response.statusCode != 200) {
    throw Exception('EmailJS ${response.statusCode}: ${response.body}');
  }
}

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _kTeal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appScaffold,
    appBar: _buildAppBar(),
    body: FadeTransition(opacity: _fadeAnim, child: _submitted ? _buildSuccessState() : _buildForm()),
  );

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: context.appSurface,
    elevation: 0,
    centerTitle: true,
    title: Text('Email Support', style: TextStyle(color: context.appTextPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
    leading: IconButton(
      icon: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: context.appSurfaceMuted, borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.chevron_left_rounded, color: context.appTextPrimary, size: 24),
      ),
      onPressed: () => Navigator.pop(context),
    ),
  );

  Widget _buildSuccessState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _successScale,
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _kTealLight, shape: BoxShape.circle,
                border: Border.all(color: _kTeal.withOpacity(0.25), width: 2),
              ),
              child: const Icon(Icons.mark_email_read_rounded, color: _kTeal, size: 48),
            ),
          ),
          const SizedBox(height: 28),
          Text('Message sent!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.appTextPrimary)),
          const SizedBox(height: 10),
          Text(
            'Your support request has been recorded.\nWe will reply to ${_userEmail.isNotEmpty ? _userEmail : 'your email'} within 24–48 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6, color: context.appTextSecondary),
          ),
          const SizedBox(height: 36),
         GestureDetector(
  onTap: () {
    Clipboard.setData(const ClipboardData(text: _kSupportEmail));
    _showSnack('Email address copied');
  },
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: _kTealLight,
      borderRadius: BorderRadius.circular(50),
      border: Border.all(color: _kTeal.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mail_outline_rounded, size: 16, color: _kTeal),
        const SizedBox(width: 6),
        Flexible(                          // ← key fix
          child: Text(
            _kSupportEmail,
            overflow: TextOverflow.ellipsis, // ← prevents overflow
            style: const TextStyle(
              fontSize: 13,
              color: _kTealDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.copy_rounded, size: 14, color: _kTeal),
      ],
    ),
  ),
),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kTeal, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildForm() => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _HeaderBanner(email: _userEmail),
        const SizedBox(height: 20),
        _SectionLabel(label: 'Topic', icon: Icons.label_outline_rounded),
        const SizedBox(height: 10),
        _TopicGrid(topics: _topics, selected: _selectedTopic, onSelect: (i) => setState(() => _selectedTopic = i)),
        const SizedBox(height: 20),
        _SectionLabel(label: 'Subject', icon: Icons.title_rounded),
        const SizedBox(height: 10),
        _StyledField(
          controller: _subjectCtrl, focusNode: _subjectFocus,
          hintText: 'Brief summary of your issue…', maxLines: 1,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_bodyFocus),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Please add a subject';
            if (v.trim().length < 5) return 'Subject is too short';
            return null;
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel(label: 'Message', icon: Icons.message_outlined),
        const SizedBox(height: 10),
        _StyledField(
          controller: _bodyCtrl, focusNode: _bodyFocus,
          hintText: 'Describe your issue in detail. Include any relevant asset IDs, transaction IDs, or error messages…',
          maxLines: 8, textInputAction: TextInputAction.newline,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Please describe your issue';
            if (v.trim().length < 20) return 'Please provide more detail (min 20 chars)';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _bodyCtrl,
            builder: (_, val, __) => Text('${val.text.length} chars', style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
          ),
        ),
        const SizedBox(height: 24),
        _MetadataCard(name: _userName, email: _userEmail, topic: _topics[_selectedTopic].label),
        const SizedBox(height: 28),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kTeal, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 20),
            label: Text(_isSubmitting ? 'Sending…' : 'Send Email', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}

// ─── sub-widgets (unchanged) ──────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: _kTeal),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.appTextSecondary, letterSpacing: 0.4)),
    ],
  );
}

class _HeaderBanner extends StatelessWidget {
  final String email;
  const _HeaderBanner({required this.email});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: _kTealLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kTeal.withOpacity(0.2))),
    child: Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: _kTeal.withOpacity(0.15), shape: BoxShape.circle),
          child: const Icon(Icons.support_agent_rounded, color: _kTeal, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('We are here to help', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.appTextPrimary)),
              const SizedBox(height: 3),
              Text(
                'Replies sent to ${email.isNotEmpty ? email : 'your registered email'} within 24–48 h.',
                style: TextStyle(fontSize: 12, color: context.appTextSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TopicGrid extends StatelessWidget {
  final List<_Topic> topics;
  final int selected;
  final ValueChanged<int> onSelect;
  const _TopicGrid({required this.topics, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: List.generate(topics.length, (i) {
      final isSelected = i == selected;
      final topic = topics[i];
      return GestureDetector(
        onTap: () => onSelect(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _kTeal : context.appSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? _kTeal : context.appBorder, width: isSelected ? 1.5 : 1),
            boxShadow: isSelected ? [BoxShadow(color: _kTeal.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(topic.icon, size: 15, color: isSelected ? Colors.white : _kTeal),
              const SizedBox(width: 6),
              Text(topic.label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? Colors.white : context.appTextPrimary)),
            ],
          ),
        ),
      );
    }),
  );
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final int maxLines;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  const _StyledField({required this.controller, required this.focusNode, required this.hintText, required this.maxLines, required this.textInputAction, this.onFieldSubmitted, this.validator});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller, focusNode: focusNode, maxLines: maxLines,
    textInputAction: textInputAction, onFieldSubmitted: onFieldSubmitted, validator: validator,
    style: TextStyle(fontSize: 14, color: context.appTextPrimary, height: 1.5),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: context.appTextSecondary, fontSize: 14),
      filled: true, fillColor: context.appSurface,
      contentPadding: const EdgeInsets.all(16),
      border:             OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
      enabledBorder:      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
      focusedBorder:      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kTeal, width: 1.5)),
      errorBorder:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1.5)),
    ),
  );
}

class _MetadataCard extends StatelessWidget {
  final String name, email, topic;
  const _MetadataCard({required this.name, required this.email, required this.topic});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.appBorder),
      boxShadow: [BoxShadow(color: context.appShadow, blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: _kTeal),
          const SizedBox(width: 6),
          Text('This info is attached to your ticket', style: TextStyle(fontSize: 12, color: context.appTextSecondary, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 12),
        _MetaRow(label: 'Name',  value: name.isNotEmpty  ? name  : '—'),
        const SizedBox(height: 6),
        _MetaRow(label: 'Email', value: email.isNotEmpty ? email : '—'),
        const SizedBox(height: 6),
        _MetaRow(label: 'Topic', value: topic),
      ],
    ),
  );
}

class _MetaRow extends StatelessWidget {
  final String label, value;
  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 52, child: Text(label, style: TextStyle(fontSize: 12, color: context.appTextSecondary))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.appTextPrimary), overflow: TextOverflow.ellipsis)),
    ],
  );
}