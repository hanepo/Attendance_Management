import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/encryption_service.dart';
import '../../utils/constants.dart';

/// Live demonstration of AES-256-CBC encryption used to protect all data
/// stored in Firebase Firestore.
class EncryptionDemoScreen extends StatefulWidget {
  const EncryptionDemoScreen({super.key});

  @override
  State<EncryptionDemoScreen> createState() => _EncryptionDemoScreenState();
}

class _EncryptionDemoScreenState extends State<EncryptionDemoScreen>
    with SingleTickerProviderStateMixin {
  final _enc = EncryptionService();
  final _auth = AuthService();
  final _db = DatabaseService();
  late TabController _tabCtrl;

  // Live demo state
  final _inputCtrl = TextEditingController(text: 'Hello, my name is Ahmad');
  String _encrypted1 = '';
  String _encrypted2 = '';
  String _decrypted = '';
  bool _showDecrypt = false;

  // Stored data state
  bool _loadingStored = false;
  Map<String, _FieldRow> _storedFields = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _runDemo();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _runDemo() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    // Encrypt twice to show different ciphertext each time (random IV)
    final e1 = _enc.encrypt(text);
    final e2 = _enc.encrypt(text);
    final d = _enc.decrypt(e1);
    setState(() {
      _encrypted1 = e1;
      _encrypted2 = e2;
      _decrypted = d;
      _showDecrypt = false;
    });
  }

  Future<void> _loadStoredData() async {
    setState(() => _loadingStored = true);
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loadingStored = false);
      return;
    }
    // Read raw Firestore doc (pre-decryption)
    try {
      final doc = await _db.rawUserDoc(user.uid);
      if (doc == null) {
        setState(() => _loadingStored = false);
        return;
      }
      final rows = <String, _FieldRow>{};
      final piFields = ['name', 'email', 'ic_number', 'matrix_number'];
      for (final field in piFields) {
        final raw = doc[field] as String?;
        if (raw == null || raw.isEmpty) continue;
        rows[field] = _FieldRow(
          fieldName: field,
          encryptedValue: raw,
          decryptedValue: _enc.decrypt(raw),
        );
      }
      // face_data: just show whether it exists (too long to display)
      final faceRaw = doc['face_data'] as String?;
      if (faceRaw != null && faceRaw.isNotEmpty) {
        rows['face_data'] = _FieldRow(
          fieldName: 'face_data (biometric)',
          encryptedValue:
              '${faceRaw.substring(0, 40)}… (${faceRaw.length} chars)',
          decryptedValue: '[192-D face embedding — ${faceRaw.length} chars encrypted]',
        );
      }
      setState(() {
        _storedFields = rows;
        _loadingStored = false;
      });
    } catch (e) {
      setState(() => _loadingStored = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied to clipboard'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Encryption Demo'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.lock, size: 16), text: 'Live Demo'),
            Tab(icon: Icon(Icons.storage, size: 16), text: 'My Data'),
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Specs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLiveDemo(),
          _buildStoredData(),
          _buildSpecs(),
        ],
      ),
    );
  }

  // ── Tab 1: Live Demo ──────────────────────────────────────────────────────

  Widget _buildLiveDemo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.edit, 'Enter any text to encrypt'),
          const SizedBox(height: 8),
          TextField(
            controller: _inputCtrl,
            decoration: InputDecoration(
              hintText: 'Type anything…',
              suffixIcon: IconButton(
                icon: const Icon(Icons.lock),
                onPressed: _runDemo,
                tooltip: 'Encrypt',
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
            onSubmitted: (_) => _runDemo(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _runDemo,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Encrypt Now'),
            ),
          ),

          if (_encrypted1.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionHeader(Icons.compare_arrows,
                'Same text → different ciphertext every time'),
            const SizedBox(height: 4),
            Text(
              'This proves Random IV is used — even identical data looks different in the database each time it is saved.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            _encryptedBox('Encryption #1', _encrypted1),
            const SizedBox(height: 8),
            _encryptedBox('Encryption #2', _encrypted2),
            const SizedBox(height: 20),
            _sectionHeader(Icons.lock_open, 'Decryption (with secret key)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showDecrypt = true),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _showDecrypt
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('Tap to reveal decrypted value',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                ),
                secondChild: _resultBox(
                  label: 'Decrypted',
                  value: _decrypted,
                  color: AppColors.success,
                  icon: Icons.lock_open,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Without the secret key, the encrypted data is completely unreadable — even if someone gets direct access to the Firebase database.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: My Stored Data ─────────────────────────────────────────────────

  Widget _buildStoredData() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.storage,
              'Your data — as stored in Firebase vs what you see'),
          const SizedBox(height: 4),
          Text(
            'Tap "Load" to see how your actual profile fields are stored encrypted in Firestore, and what they decrypt to.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadingStored ? null : _loadStoredData,
              icon: _loadingStored
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: Text(_loadingStored ? 'Loading…' : 'Load My Encrypted Data'),
            ),
          ),
          if (_storedFields.isNotEmpty) ...[
            const SizedBox(height: 20),
            ..._storedFields.values.map((row) => _storedFieldCard(row)),
          ],
          if (!_loadingStored && _storedFields.isEmpty &&
              _auth.currentUser != null) ...[
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Tap "Load" above to see your encrypted data',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _storedFieldCard(_FieldRow row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  row.fieldName.toUpperCase().replaceAll('_', ' '),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 0.5),
                ),
              ],
            ),
            const Divider(height: 16),
            _labelledValue(
              '🔒 In Firebase (encrypted)',
              row.encryptedValue,
              Colors.red.shade700,
            ),
            const SizedBox(height: 8),
            _labelledValue(
              '🔓 In App (decrypted)',
              row.decryptedValue,
              AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelledValue(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600])),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _copy(value),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 3: Specs ──────────────────────────────────────────────────────────

  Widget _buildSpecs() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.security, 'Security Specifications'),
          const SizedBox(height: 12),
          // ── Client-side flow diagram ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Where does AES run?',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'AES cannot run inside Firebase. It runs on the phone (client side) before data is sent.',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // SAVE flow
                _flowDiagram(
                  title: 'Saving data (e.g. IC number)',
                  steps: [
                    _FlowStep('Phone (App)', 'Plain text:\n"930101-01-0001"',
                        Colors.blue.shade700, Icons.phone_android),
                    _FlowStep('AES-256 Encrypt', 'Runs on phone\n(not Firebase)',
                        AppColors.primary, Icons.lock),
                    _FlowStep('Firebase', 'Stores ciphertext only:\n"aBcD1234xYz…"',
                        Colors.grey.shade600, Icons.cloud),
                  ],
                ),
                const SizedBox(height: 12),
                // READ flow
                _flowDiagram(
                  title: 'Reading data back',
                  steps: [
                    _FlowStep('Firebase', 'Returns ciphertext:\n"aBcD1234xYz…"',
                        Colors.grey.shade600, Icons.cloud),
                    _FlowStep('AES-256 Decrypt', 'Runs on phone\n(not Firebase)',
                        AppColors.primary, Icons.lock_open),
                    _FlowStep('Phone (App)', 'Readable:\n"930101-01-0001"',
                        Colors.blue.shade700, Icons.phone_android),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Firebase is only a storage. It never sees the original data — only the encrypted version. Even Firebase employees cannot read your data.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _specCard('Encryption Algorithm', 'AES-256-CBC',
              'Advanced Encryption Standard with 256-bit key in Cipher Block Chaining mode — the same standard used by banks and government systems.'),
          _specCard('Key Size', '256 bits (32 bytes)',
              'Maximum AES key length. Brute-force cracking would take longer than the age of the universe with current computers.'),
          _specCard('Initialization Vector (IV)', 'Random 16 bytes per value',
              'Every encryption uses a freshly generated random IV. This means the same data encrypted twice produces completely different ciphertext, preventing pattern analysis attacks.'),
          _specCard('Storage Format', 'base64(IV) : base64(ciphertext)',
              'The IV is stored alongside the ciphertext so decryption is always possible, but only with the correct 256-bit key.'),
          _specCard('Biometric Data', 'AES-256 encrypted 192-D face vector',
              'Face embeddings from MobileFaceNet are encrypted before storing. Raw face images are never saved anywhere.'),
          _specCard('Password Storage', 'Firebase Authentication',
              'Passwords are never stored in the app or database. Firebase Auth uses bcrypt hashing server-side.'),
          _specCard('Data in Transit', 'TLS 1.3 (Firebase SDK)',
              'All communication between the app and Firebase is over encrypted HTTPS. No plain-text network traffic.'),
          _specCard('Fields Encrypted in Database', 'All PII fields',
              'name, email, IC number, matrix number, session name, class name, attendance records — everything personally identifiable is encrypted at field level.'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.accent.withValues(alpha: 0.1)
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user,
                    color: AppColors.primary, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Defence in Depth',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 4),
                      Text(
                        'Even if an attacker gains direct access to the Firebase console, they will only see encrypted ciphertext. The AES key lives only inside the application.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _encryptedBox(String label, String value) {
    return GestureDetector(
      onTap: () => _copy(value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700)),
                const Spacer(),
                const Icon(Icons.copy, size: 13, color: Colors.red),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.red.shade800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultBox(
      {required String label,
      required String value,
      required Color color,
      required IconData icon}) {
    return GestureDetector(
      onTap: () => _copy(value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const Spacer(),
                const Icon(Icons.copy, size: 13),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flowDiagram(
      {required String title, required List<_FlowStep> steps}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Flexible(child: _buildFlowStep(steps[i])),
                if (i < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.arrow_forward,
                        size: 14, color: Colors.black38),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlowStep(_FlowStep step) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: step.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: step.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(step.icon, size: 18, color: step.color),
          const SizedBox(height: 4),
          Text(step.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: step.color),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(step.value,
              style: TextStyle(fontSize: 9, color: step.color.withValues(alpha: 0.8)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _specCard(String title, String value, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(description,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _FieldRow {
  final String fieldName;
  final String encryptedValue;
  final String decryptedValue;

  const _FieldRow({
    required this.fieldName,
    required this.encryptedValue,
    required this.decryptedValue,
  });
}

class _FlowStep {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _FlowStep(this.label, this.value, this.color, this.icon);
}
