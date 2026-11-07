import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ganti password.
///
/// [forced]: tampil otomatis setelah login pertama dengan password sementara
/// dari pengelola; aplikasi baru bisa dipakai setelah password diganti.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});

  final bool forced;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _new.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.changePassword(
        current: widget.forced ? null : _current.text,
        newPassword: _new.text,
      );
      if (!mounted) return;
      if (widget.forced) {
        // main.dart otomatis membuka aplikasi setelah flag dihapus.
        showSnack(context, 'Password berhasil dibuat. Selamat datang!');
      } else {
        showSnack(context, 'Password berhasil diganti');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Tampilkan' : 'Sembunyikan',
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = store.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forced ? 'Buat Password Baru' : 'Ganti Password'),
        automaticallyImplyLeading: !widget.forced,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.forced) ...[
              TwoToneHeading('Halo, ${user?.name ?? ''}', 'amankan akun Anda'),
              const SizedBox(height: 8),
              Text(
                'Anda masuk dengan password sementara dari pengelola. Buat '
                'password baru yang hanya Anda ketahui sebelum melanjutkan.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
            ] else ...[
              if (user?.email != null)
                Text('Akun: ${user!.email}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _current,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: _decoration('Password lama'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Isi password lama' : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _new,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: _decoration('Password baru',
                  helper: 'Minimal 8 karakter, berisi huruf dan angka'),
              validator: (v) => passwordProblem(v ?? ''),
            ),
            const SizedBox(height: 8),
            PasswordStrength(_new.text),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: _decoration('Ulangi password baru'),
              validator: (v) => v != _new.text ? 'Password tidak sama' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.forced ? 'Simpan & lanjutkan' : 'Simpan'),
            ),
            if (widget.forced)
              TextButton(
                onPressed: _busy ? null : () => store.logout(),
                child: const Text('Keluar'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Indikator kekuatan password sederhana.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength(this.password, {super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    final (label, color) = switch (score) {
      <= 1 => ('Lemah', Colors.red.shade600),
      2 || 3 => ('Cukup', Colors.orange.shade700),
      _ => ('Kuat', AppColors.limeDark),
    };
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 5,
              minHeight: 6,
              color: color,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
