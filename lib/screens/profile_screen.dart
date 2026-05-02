// lib/screens/profile_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../blockchain/ipfs_service.dart';   // ← your existing service
import '../blockchain/blockchain_service.dart';
import 'shared_screens.dart';
import 'asset_screen.dart';
import 'stolen_report_screen.dart';
import 'auth_screens.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _db = FirebaseFirestore.instance;
final IPFSService _ipfs = IPFSService();

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {

  final VoidCallback? onBack;
  const ProfileScreen({super.key, this.onBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  bool _uploadingPhoto = false;

  static const Color _teal = Color(0xFF2D8C8C);

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _userDocStream = _db.collection('users').doc(user.uid).snapshots();
    }
  }

  // ── Photo bottom sheet ────────────────────────────────────────────────────
  void _showPhotoOptions({
    required String currentPhotoUrl,
    required String currentCid,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Profile Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _sheetTile(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            _sheetTile(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (currentPhotoUrl.isNotEmpty)
              _sheetTile(
                icon: Icons.delete_outline_rounded,
                label: 'Remove photo',
                color: Colors.red.shade400,
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto(cid: currentCid);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = _teal,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color),
      ),
      title: Text(label,
          style: TextStyle(
              color: color == _teal ? const Color(0xFF1A1A2E) : color,
              fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  // ── Pick image → upload to IPFS via IPFSService ───────────────────────────
  Future<void> _pickAndUpload(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Pick image
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      // 2. Read bytes (IPFSService needs Uint8List)
      final bytes = await picked.readAsBytes();
      final fileName = 'profile_${user.uid}.jpg';

      // 3. Upload via your IPFSService
      final result = await _ipfs.uploadFile(
        fileBytes: bytes,
        fileName: fileName,
        metadata: {'uid': user.uid, 'type': 'profile_photo'},
      );

      if (!result.success) {
        throw Exception(result.error ?? 'IPFS upload failed');
      }

      final photoUrl = result.ipfsUrl!;
      final photoCid = result.ipfsHash!;

      // 4. Persist to Firestore + Firebase Auth profile
      await _db.collection('users').doc(user.uid).update({
        'photoUrl': photoUrl,
        'photoCid': photoCid,
      });
      await user.updatePhotoURL(photoUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated ✅')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto({required String cid}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      await _db.collection('users').doc(user.uid).update({
        'photoUrl': '',
        'photoCid': '',
      });
      await user.updatePhotoURL(null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Reset password ────────────────────────────────────────────────────────
  Future<void> _sendResetPasswordEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _auth.sendPasswordResetEmail(email: user.email ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reset password email sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    clearRoleCache(); // 🚀 Clear cache
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _menuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = _teal,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A2E))),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
      ],
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: children),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.data() == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: AppBar(title: const Text('Profile')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No profile found. Please register.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text('Go to Registration'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snap.data!.data()!;
        final displayEmail = user.email ?? '';
        final name         = data['name']     ?? user.displayName ?? '';
        final role         = data['role']     ?? 'user';
        final photoUrl     = (data['photoUrl'] as String?) ?? user.photoURL ?? '';
        final photoCid     = (data['photoCid'] as String?) ?? '';
        final displayName  = name.isNotEmpty ? name : displayEmail;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),

          // ── AppBar ───────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: const Text('Profile',
                style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F4),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.chevron_left_rounded,
                    color: Color(0xFF1A1A2E), size: 24),
              ),
              onPressed: () {
                // Switches bottom-nav back to Home (index 0) — no crash
                if (widget.onBack != null) {
                  widget.onBack!();
                } else if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
          ),

          body: Column(
            children: [
              // ── Profile header ───────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Row(
                  children: [
                    // Tappable avatar
                    GestureDetector(
                      onTap: () => _showPhotoOptions(
                          currentPhotoUrl: photoUrl,
                          currentCid: photoCid),
                      child: Stack(
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _teal.withOpacity(0.12),
                              border: Border.all(
                                  color: _teal.withOpacity(0.3),
                                  width: 2.5),
                            ),
                            child: ClipOval(
                              child: _uploadingPhoto
                                  ? const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _teal))
                                  : photoUrl.isNotEmpty
                                  ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                // Show spinner while loading
                                loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                    child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _teal)),
                                errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person_rounded,
                                    size: 38, color: _teal),
                              )
                                  : const Icon(Icons.person_rounded,
                                  size: 38, color: _teal),
                            ),
                          ),
                          // Edit badge
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                  color: _teal,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2)),
                              child: const Icon(Icons.edit_rounded,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 18),

                    // Name / email / role
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E))),
                          const SizedBox(height: 4),
                          Text(displayEmail,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: _teal.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              role.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _teal,
                                  letterSpacing: 1.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Menu sections ────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Section 1 — main features
                      _card(children: [
                        _menuTile(
                          icon: Icons.favorite_rounded,
                          label: 'Favorites',
                          iconColor: const Color(0xFFE57373),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FavoritesScreen())),
                        ),
                        _menuTile(
                          icon: Icons.report_problem_rounded,
                          label: 'Stolen Reports',
                          iconColor: const Color(0xFFFF8A65),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const StolenReportScreen())),
                        ),
                        _menuTile(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Transactions',
                          showDivider: false,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const TransactionsScreen())),
                        ),
                      ]),

                      const SizedBox(height: 12),

                      // Section 2 — account
                      _card(children: [
                        _menuTile(
                          icon: Icons.lock_reset_rounded,
                          label: 'Reset Password',
                          iconColor: const Color(0xFF7986CB),
                          onTap: _sendResetPasswordEmail,
                        ),
                        _menuTile(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          showDivider: false,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen())),
                        ),
                      ]),

                      const SizedBox(height: 12),

                      // Section 3 — support
                      _card(children: [
                        _menuTile(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & Support',
                          iconColor: const Color(0xFF4DB6AC),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const HelpScreen())),
                        ),
                        _menuTile(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Terms & Privacy',
                          iconColor: const Color(0xFF78909C),
                          showDivider: false,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TermsScreen())),
                        ),
                      ]),

                      if (role == 'admin') ...[
                        const SizedBox(height: 12),
                        _card(children: [
                          _menuTile(
                            icon: Icons.admin_panel_settings_rounded,
                            label: 'Admin Tools',
                            iconColor: const Color(0xFF673AB7),
                            showDivider: false,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AdminPanelScreen())),
                          ),
                        ]),
                      ],

                      const SizedBox(height: 24),

                      // Logout
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _teal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(14)),
                            ),
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded,
                                size: 20),
                            label: const Text('Logout',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading         = false;
  bool _darkMode        = false;
  bool _lastSeenEnabled = true;

  static const Color _teal = Color(0xFF2D8C8C);

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    setState(() {
      _darkMode        = doc.data()?['darkMode']        ?? false;
      _lastSeenEnabled = doc.data()?['lastSeenEnabled'] ?? true;
    });
  }

  Future<void> _setLastSeen(bool val) async {
    setState(() => _lastSeenEnabled = val);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'lastSeenEnabled': val});
  }

  Future<void> _setDarkMode(bool v) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).update({'darkMode': v});
    setState(() => _darkMode = v);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Preference saved')));
    }
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete account'),
        content: const Text(
          'This will delete your Firebase account and user document. '
              'This requires recent login. Are you sure?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      clearRoleCache(); // 🚀 Clear cache
      await _db
          .collection('users')
          .doc(user.uid)
          .delete()
          .catchError((_) {});
      await user.delete();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Settings',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFFF0F4F4),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF1A1A2E), size: 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Dark Mode',
                        style: TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    subtitle:
                    const Text('Save preference to your account'),
                    value: _darkMode,
                    activeColor: _teal,
                    onChanged: _setDarkMode,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16))),
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade100),
                  SwitchListTile(
                    title: const Text('Last Seen',
                        style: TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    subtitle: const Text(
                        'Show others when you were last active'),
                    value: _lastSeenEnabled,
                    activeColor: _teal,
                    onChanged: _setLastSeen,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(16))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _deleteAccount,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20),
                label: const Text('Delete Account',
                    style:
                    TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELP SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Help & Support',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFFF0F4F4),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF1A1A2E), size: 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('For support, contact: support@digitalgoods.com'),
            SizedBox(height: 16),
            Text('FAQ', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• How to buy?\n• How to sell?\n• How to verify assets?'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TERMS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Terms & Privacy',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFFF0F4F4),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF1A1A2E), size: 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Your terms and privacy policy content goes here. '
              'Replace this placeholder with your real legal text.',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN PANEL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _addressCtrl = TextEditingController();
  final _bs = BlockchainServiceEnhanced();
  bool _loading = false;
  String _roleType = 'VENDOR_ROLE';

  Future<void> _grantRole() async {
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty || !addr.startsWith('0x')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Wallet Address')));
      return;
    }

    setState(() => _loading = true);
    try {
      if (_roleType == 'VENDOR_ROLE') {
        await _bs.grantVendorRole(addr);
      } else {
        await _bs.grantRetailerRole(addr);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_roleType granted successfully to $addr')));
        _addressCtrl.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Admin Tools',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFFF0F4F4),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF1A1A2E), size: 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Grant Roles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Assign VENDOR or RETAILER roles to specific wallet addresses to authorize them to receive products.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Wallet Address (0x...)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _roleType,
                    items: const [
                      DropdownMenuItem(value: 'VENDOR_ROLE', child: Text('VENDOR_ROLE')),
                      DropdownMenuItem(value: 'RETAILER_ROLE', child: Text('RETAILER_ROLE')),
                    ],
                    onChanged: (v) => setState(() => _roleType = v!),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _grantRole,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D8C8C),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Grant Role', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}